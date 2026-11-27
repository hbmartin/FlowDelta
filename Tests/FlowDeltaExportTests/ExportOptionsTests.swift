import FlowDeltaCore
import FlowDeltaExport
import Foundation
import XCTest

final class ExportOptionsTests: XCTestCase {
    private let exporter = FlowDeltaReportExporter()

    func testNoiseOptionHidesCosmeticNodesAndSaysHowMany() throws {
        let report = makeReport(concerns: nil)
        let shown = try exporter.render(report, format: .table)
        XCTAssertTrue(shown.contains("• alpha(): 0 added, 0 removed, 1 modified, 1 affected"), shown)
        XCTAssertFalse(shown.contains("Noise:"))

        let hidden = try exporter.render(report, format: .table, options: FlowDeltaExportOptions(noise: .hideCosmetic))
        XCTAssertFalse(hidden.contains("• alpha():"), "A function left without changes has no line")
        XCTAssertTrue(hidden.contains("Noise: 1 node change hidden (hide-cosmetic)."), hidden)
        let markdown = try exporter.render(
            report,
            format: .markdown,
            options: FlowDeltaExportOptions(noise: .hideCosmetic)
        )
        XCTAssertTrue(markdown.contains("> Noise: 1 node change hidden (hide-cosmetic)."), markdown)
        let mermaid = try exporter.render(
            report,
            format: .mermaid,
            options: FlowDeltaExportOptions(noise: .hideCosmetic)
        )
        XCTAssertFalse(mermaid.contains(":::modified"))
        XCTAssertFalse(mermaid.contains(":::affected"))
    }

    func testGroupingOrdersTriageByConcernAndNotesATangledRevision() throws {
        let concerns = [
            FlowConcern(
                id: StableID(rawValue: "c.beta"),
                kind: .behavioral,
                title: "`beta`",
                memberIDs: [entityID("beta")],
                links: []
            ),
            FlowConcern(
                id: StableID(rawValue: "c.alpha"),
                kind: .behavioral,
                title: "`alpha`",
                memberIDs: [entityID("alpha")],
                links: []
            )
        ]
        let report = makeReport(concerns: concerns)
        let options = FlowDeltaExportOptions(groupByConcern: true)

        let table = try exporter.render(report, format: .table, options: options)
        let order = [
            "▸ `beta` — behavioral",
            "MODIFIED   beta()",
            "▸ `alpha` — behavioral",
            "MODIFIED   alpha()",
            "▸ Unchanged",
            "UNCHANGED"
        ]
        let positions = try order.map { try XCTUnwrap(table.range(of: $0)?.lowerBound, $0) }
        XCTAssertEqual(positions, positions.sorted(), table)
        XCTAssertTrue(table.contains("Tangled revision: 2 separate behavioral concerns."))

        let markdown = try exporter.render(report, format: .markdown, options: options)
        XCTAssertTrue(markdown.contains("### `beta` — behavioral\n\n| Change |"), markdown)
        XCTAssertTrue(markdown.contains("\n\n### Unchanged\n"), markdown)
        XCTAssertTrue(markdown.contains("> Tangled revision: 2 separate behavioral concerns."))

        let ungrouped = makeReport(concerns: nil)
        XCTAssertEqual(
            try exporter.render(ungrouped, format: .table, options: options),
            try exporter.render(ungrouped, format: .table)
        )
    }

    func testWalkthroughIsAppendedToTableMarkdownAndJSONButNotMermaid() throws {
        let report = makeReport(concerns: nil)
        let options = FlowDeltaExportOptions(includeWalkthrough: true)
        let narration = "Changes `total = a` to `total = a // sum` — affects 1 node by control."

        let table = try exporter.render(report, format: .table, options: options)
        XCTAssertTrue(table.hasSuffix("Walkthrough:\n  1. alpha(): \(narration)\n"), table)
        let markdown = try exporter.render(report, format: .markdown, options: options)
        XCTAssertTrue(markdown.contains("## Walkthrough\n\n1. **`alpha()`** — \(narration)\n"), markdown)
        let json = try exporter.render(report, format: .json, options: options)
        let document = try JSONDecoder().decode(FlowDeltaExportDocument.self, from: Data(json.utf8))
        XCTAssertEqual(document.report, report)
        XCTAssertEqual(document.walkthrough.map(\.narration), [narration])
        XCTAssertEqual(
            try exporter.render(report, format: .mermaid, options: options),
            try exporter.render(report, format: .mermaid)
        )

        let quiet = try exporter.render(
            report,
            format: .table,
            options: FlowDeltaExportOptions(noise: .hideCosmetic, includeWalkthrough: true)
        )
        XCTAssertTrue(quiet.hasSuffix("Walkthrough:\n"), "Hidden noise leaves no steps")
        XCTAssertEqual(FlowDeltaExportOptions.default, FlowDeltaExportOptions())
    }

    // MARK: Fixture

    private func entityID(_ name: String) -> StableID {
        StableID(rawValue: "entity.\(name)")
    }

    /// `alpha` changes a comment inside a statement that controls one node; `beta` changes nothing in its body;
    /// `gamma` is unchanged.
    private func makeReport(concerns: [FlowConcern]?) -> RevisionFlowDeltaReport {
        let location = SourceLocation(utf8Offset: 0, utf16Offset: 0, line: 0, utf16Column: 0)
        let range = SourceRange(start: location, end: location)
        func entity(_ name: String) -> SourceEntity {
            SourceEntity(
                id: entityID(name),
                kind: .function,
                name: name,
                qualifiedName: "\(name)()",
                path: "A.swift",
                range: range,
                body: SyntaxNode(id: StableID(rawValue: "body.\(name)"), kind: "statements", range: range, text: "")
            )
        }
        let alpha = EntityChange(kind: .modified, old: entity("alpha"), new: entity("alpha"), confidence: nil)
        let beta = EntityChange(kind: .modified, old: entity("beta"), new: entity("beta"), confidence: nil)
        let gamma = EntityChange(kind: .unchanged, old: entity("gamma"), new: entity("gamma"), confidence: nil)

        let entry = FlowNode(id: StableID(rawValue: "entry"), kind: .entry, label: "Entry", sourceOrder: 0)
        let old = FlowNode(id: StableID(rawValue: "old.total"), kind: .basicBlock, label: "total = a", sourceOrder: 1)
        let new = FlowNode(
            id: StableID(rawValue: "new.total"),
            kind: .basicBlock,
            label: "total = a // sum",
            sourceOrder: 1
        )
        let use = FlowNode(id: StableID(rawValue: "use"), kind: .basicBlock, label: "return total", sourceOrder: 2)
        func graph(_ statement: FlowNode) -> ControlFlowGraph {
            ControlFlowGraph(
                entityID: entityID("alpha"),
                nodes: [entry, statement, use],
                edges: [
                    FlowEdge(source: entry.id, target: statement.id, kind: .fallthrough),
                    FlowEdge(source: statement.id, target: use.id, kind: .fallthrough)
                ],
                entryID: entry.id,
                exitID: use.id,
                errorExitID: use.id
            )
        }
        let changed = FlowNodeDelta(
            id: StableID(rawValue: "d.total"),
            old: old,
            new: new,
            state: .modified,
            noise: .formatting
        )
        let nodes = [
            FlowNodeDelta(id: StableID(rawValue: "d.entry"), old: entry, new: entry, state: .retained),
            changed,
            FlowNodeDelta(id: StableID(rawValue: "d.use"), old: use, new: use, state: .affected, causality: [
                CausalityLink(
                    triggerID: changed.id,
                    affectedID: StableID(rawValue: "d.use"),
                    basis: .control,
                    explanation: ""
                )
            ])
        ]
        let alphaDelta = FunctionFlowDelta(
            id: StableID(rawValue: "f.alpha"),
            entityChange: alpha,
            editScript: nil,
            oldGraph: graph(old),
            newGraph: graph(new),
            nodes: nodes,
            edges: []
        )
        let snapshot = SourceSnapshot(path: "A.swift", revision: RevisionIdentity("r"), language: .swift, text: "")
        let file = FileFlowDelta(
            comparison: FileComparison(old: snapshot, new: snapshot),
            entityChanges: [alpha, beta, gamma],
            functionDeltas: [alphaDelta]
        )
        return RevisionFlowDeltaReport(
            base: RevisionIdentity("base"),
            target: RevisionIdentity("target"),
            files: [file],
            concerns: concerns
        )
    }
}
