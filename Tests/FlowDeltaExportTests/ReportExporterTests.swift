import FlowDeltaCore
import FlowDeltaExport
import Foundation
import XCTest

final class ReportExporterTests: XCTestCase {
    func testJSONIsPrettySortedAndRoundTrips() throws {
        let report = makeReport()
        let value = try FlowDeltaReportExporter().json(report)

        XCTAssertTrue(value.hasSuffix("\n"))
        XCTAssertLessThan(
            try XCTUnwrap(value.range(of: "\"base\"")?.lowerBound),
            try XCTUnwrap(value.range(of: "\"files\"")?.lowerBound)
        )
        XCTAssertEqual(try JSONDecoder().decode(RevisionFlowDeltaReport.self, from: Data(value.utf8)), report)
    }

    func testMermaidUsesStableIdentifiersEscapesLabelsAndDefinesStates() {
        let value = FlowDeltaReportExporter().mermaid(makeReport())

        XCTAssertTrue(value.contains("flowchart TD"))
        XCTAssertTrue(value.contains("&quot;quoted&quot;"))
        XCTAssertTrue(value.contains(":::affected"))
        XCTAssertTrue(value.contains("-.->|\"value\"|"))
        XCTAssertTrue(value.contains("classDef added"))
        XCTAssertFalse(value.contains("node:raw"))
    }

    func testMarkdownLeadsWithExecutiveSummaryAndEmbedsMermaid() {
        let value = FlowDeltaReportExporter().markdown(makeReport())

        XCTAssertTrue(value.hasPrefix("# FlowDelta report"))
        XCTAssertTrue(value.contains("## Entity triage"))
        XCTAssertTrue(value.contains("## Control-flow delta"))
        XCTAssertTrue(value.contains("```mermaid"))
        XCTAssertTrue(value.contains("control + data context"))
    }

    func testMarkdownOmitsContextBasisWhenNoNodesAreAffected() {
        let report = RevisionFlowDeltaReport(
            base: RevisionIdentity("base"),
            target: RevisionIdentity("target"),
            files: []
        )
        let value = FlowDeltaReportExporter().markdown(report)

        XCTAssertFalse(value.contains("Affected nodes in this report use"))
        XCTAssertFalse(value.contains("** context**"))
    }

    func testTableContainsTriageBeforeFunctionSummary() throws {
        let value = FlowDeltaReportExporter().table(makeReport())

        XCTAssertLessThan(
            try XCTUnwrap(value.range(of: "CHANGE")?.lowerBound),
            try XCTUnwrap(value.range(of: "Summary:")?.lowerBound)
        )
        XCTAssertTrue(value.contains("MODIFIED"))
        XCTAssertTrue(value.contains("exactName 100%"))
        XCTAssertTrue(value.contains("1 affected"))
    }

    private func makeReport() -> RevisionFlowDeltaReport {
        let range = SourceRange(
            start: SourceLocation(utf8Offset: 0, utf16Offset: 0, line: 0, utf16Column: 0),
            end: SourceLocation(utf8Offset: 5, utf16Offset: 5, line: 0, utf16Column: 5)
        )
        let syntax = SyntaxNode(id: StableID(rawValue: "syntax"), kind: "statements", range: range, text: "if x")
        let entity = SourceEntity(
            id: StableID(rawValue: "entity"),
            kind: .function,
            name: "review",
            qualifiedName: "review(\"quoted\")",
            path: "Review.swift",
            range: range,
            body: syntax
        )
        let change = EntityChange(
            kind: .modified,
            old: entity,
            new: entity,
            confidence: MatchConfidence(tier: .exactName, score: 1)
        )
        let entry = FlowNode(id: StableID(rawValue: "entry"), kind: .entry, label: "Entry", sourceOrder: 0)
        let affected = FlowNode(
            id: StableID(rawValue: "affected"),
            kind: .basicBlock,
            label: "return value",
            sourceRanges: [range],
            sourceOrder: 1
        )
        let edge = FlowEdge(source: entry.id, target: affected.id, kind: .fallthrough)
        let graph = ControlFlowGraph(
            entityID: entity.id,
            nodes: [entry, affected],
            edges: [edge],
            entryID: entry.id,
            exitID: affected.id,
            errorExitID: affected.id
        )
        let entryDelta = FlowNodeDelta(
            id: StableID(rawValue: "node:raw"),
            old: entry,
            new: entry,
            state: .retained
        )
        let affectedDelta = FlowNodeDelta(
            id: StableID(rawValue: "node:affected"),
            old: affected,
            new: affected,
            state: .affected,
            causality: [
                CausalityLink(
                    triggerID: entryDelta.id,
                    affectedID: StableID(rawValue: "node:affected"),
                    basis: .control,
                    explanation: "Control context changed."
                ),
                CausalityLink(
                    triggerID: entryDelta.id,
                    affectedID: StableID(rawValue: "node:affected"),
                    basis: .data,
                    explanation: "Reaching definition changed."
                )
            ]
        )
        let dataEdge = DataFlowEdge(symbol: "value", definition: entry.id, use: affected.id)
        let function = FunctionFlowDelta(
            id: StableID(rawValue: "function"),
            entityChange: change,
            editScript: nil,
            oldGraph: graph,
            newGraph: graph,
            nodes: [entryDelta, affectedDelta],
            edges: [FlowEdgeDelta(id: StableID(rawValue: "edge-delta"), old: edge, new: edge, state: .retained)],
            dataFlow: FunctionDataFlowDelta(
                oldGraph: DataFlowGraph(entityID: entity.id, edges: [dataEdge]),
                newGraph: DataFlowGraph(entityID: entity.id, edges: [dataEdge]),
                edges: [DataFlowEdgeDelta(id: dataEdge.id, old: dataEdge, new: dataEdge, state: .retained)]
            )
        )
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        let snapshot = SourceSnapshot(path: "Review.swift", revision: target, language: .swift, text: "if x")
        return RevisionFlowDeltaReport(
            base: base,
            target: target,
            files: [FileFlowDelta(
                comparison: FileComparison(old: snapshot, new: snapshot),
                entityChanges: [change],
                functionDeltas: [function]
            )]
        )
    }
}
