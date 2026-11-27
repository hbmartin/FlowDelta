import FlowDeltaCore
import XCTest

final class FlowTriageTests: XCTestCase {
    private func report(concerns: [FlowConcern]?) -> RevisionFlowDeltaReport {
        let location = SourceLocation(utf8Offset: 0, utf16Offset: 0, line: 0, utf16Column: 0)
        let range = SourceRange(start: location, end: location)
        func change(_ name: String, _ kind: EntityChangeKind) -> EntityChange {
            let entity = SourceEntity(
                id: StableID(rawValue: name),
                kind: .function,
                name: name,
                qualifiedName: name,
                path: "A.swift",
                range: range,
                body: SyntaxNode(id: StableID(rawValue: "b.\(name)"), kind: "block", range: range, text: "")
            )
            return EntityChange(kind: kind, old: entity, new: entity, confidence: nil)
        }
        let changes = [change("a", .modified), change("b", .modified), change("c", .unchanged)]
        let function = FunctionFlowDelta(
            id: StableID(rawValue: "f.b"),
            entityChange: changes[1],
            editScript: nil,
            oldGraph: nil,
            newGraph: nil,
            nodes: [],
            edges: []
        )
        let snapshot = SourceSnapshot(path: "A.swift", revision: RevisionIdentity("r"), language: .swift, text: "")
        return RevisionFlowDeltaReport(
            base: RevisionIdentity("a"),
            target: RevisionIdentity("b"),
            files: [FileFlowDelta(
                comparison: FileComparison(old: snapshot, new: snapshot),
                entityChanges: changes,
                functionDeltas: [function]
            )],
            concerns: concerns
        )
    }

    func testUngroupedTriageIsOneSectionInFileOrder() {
        let sections = FlowTriage.sections(for: report(concerns: nil), groupsByConcern: true)
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].title)
        XCTAssertEqual(sections[0].entries.map(\.change.entityID?.rawValue), ["a", "b", "c"])
        XCTAssertEqual(sections[0].entries.map { $0.function != nil }, [false, true, false])
    }

    func testGroupedTriageFollowsConcernsAndEndsWithUnchangedEntities() {
        let concerns = [
            FlowConcern(
                id: StableID(rawValue: "1"),
                kind: .behavioral,
                title: "`b`",
                memberIDs: [StableID(rawValue: "b")],
                links: []
            ),
            FlowConcern(
                id: StableID(rawValue: "2"),
                kind: .cosmetic,
                title: "Cosmetic",
                memberIDs: [StableID(rawValue: "a")],
                links: []
            )
        ]
        let grouped = report(concerns: concerns)
        let sections = FlowTriage.sections(for: grouped, groupsByConcern: true)
        XCTAssertEqual(sections.map(\.title), ["`b`", "Cosmetic", "Unchanged"])
        XCTAssertEqual(sections.map(\.kind), [.behavioral, .cosmetic, nil])
        XCTAssertEqual(sections.map { $0.entries.map(\.change.entityID?.rawValue) }, [["b"], ["a"], ["c"]])
        XCTAssertEqual(FlowTriage.functionOrder(of: sections), [StableID(rawValue: "f.b")])
        XCTAssertEqual(FlowTriage.sections(for: grouped, groupsByConcern: false).count, 1)
    }
}
