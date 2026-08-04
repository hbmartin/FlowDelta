import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaLayout
import FlowDeltaMatch
import Foundation
import XCTest

final class AuditCorpusTests: XCTestCase {
    struct CorpusEntry: Decodable {
        let id: String
        let repository: URL
        let commit: String
        let path: String
        let symbol: String
        let expectation: String
    }

    func testPermanentMatcherCorpusHasTwentyProvenancedAuditEntries() throws {
        let data = Data(try fixture("matcher-corpus", extension: "json").utf8)
        let entries = try JSONDecoder().decode([CorpusEntry].self, from: data)

        XCTAssertEqual(entries.count, 20)
        XCTAssertEqual(Set(entries.map(\.id)).count, 20)
        XCTAssertTrue(entries.allSatisfy { $0.commit.count == 40 })
        XCTAssertTrue(entries.allSatisfy { !$0.path.isEmpty && !$0.symbol.isEmpty && !$0.expectation.isEmpty })
        XCTAssertEqual(Set(entries.map { $0.repository.host }), ["github.com"])
    }

    func testHandPickedCommitExcerptRunsParseMatchFlowAndLayoutEndToEnd() throws {
        let oldSource = try fixture("SwiftLexicalLookup-old")
        let newSource = try fixture("SwiftLexicalLookup-new")
        let analyzer = SwiftSourceAnalyzer()
        let oldAnalysis = try analyzer.analyze(snapshot(
            oldSource,
            path: "Sources/SwiftLexicalLookup/Scopes/ScopeImplementations.swift",
            revision: "58b966582ddd632593afb6101a147740c244ec89"
        ))
        let newAnalysis = try analyzer.analyze(snapshot(
            newSource,
            path: "Sources/SwiftLexicalLookup/Scopes/ScopeImplementations.swift",
            revision: "39d18d4b9960adf8bf01026a5471c98d62fa3f64"
        ))
        let triage = EntityMatcher().triage(old: oldAnalysis.entities, new: newAnalysis.entities)
        let match = try XCTUnwrap(triage.matches.first { $0.old.name == "lookup" })
        let editScript = GumTreeMatcher().match(old: match.old.body, new: match.new.body)
        let oldGraph = try XCTUnwrap(oldAnalysis.graphs[match.old.id])
        let newGraph = try XCTUnwrap(newAnalysis.graphs[match.new.id])
        let layout = DominatorAnchoredLayout()
        let oldLayout = layout.layout(graph: oldGraph)
        let anchors = Dictionary(uniqueKeysWithValues: oldLayout.nodeFrames.map { ($0.key, CGPoint(x: $0.value.midX, y: $0.value.midY)) })
        let newLayout = layout.layout(graph: newGraph, anchors: anchors)

        XCTAssertEqual(match.confidence.tier, .exactName)
        XCTAssertFalse(editScript.operations.isEmpty)
        XCTAssertFalse(oldGraph.edges.isEmpty)
        XCTAssertFalse(newGraph.edges.isEmpty)
        XCTAssertEqual(oldLayout.nodeFrames.count, oldGraph.nodes.count)
        XCTAssertEqual(newLayout.nodeFrames.count, newGraph.nodes.count)
    }
}
