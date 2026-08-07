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

    struct RevisionCorpusEntry: Decodable {
        let repository: URL
        let commit: String
        let reviewQuestion: String
    }

    func testPermanentMatcherCorpusHasTwentyProvenancedAuditEntries() throws {
        let data = try Data(fixture("matcher-corpus", extension: "json").utf8)
        let entries = try JSONDecoder().decode([CorpusEntry].self, from: data)

        XCTAssertEqual(entries.count, 20)
        XCTAssertEqual(Set(entries.map(\.id)).count, 20)
        XCTAssertTrue(entries.allSatisfy { $0.commit.count == 40 })
        XCTAssertTrue(entries.allSatisfy { !$0.path.isEmpty && !$0.symbol.isEmpty && !$0.expectation.isEmpty })
        XCTAssertEqual(Set(entries.map(\.repository.host)), ["github.com"])
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
        let anchors = Dictionary(uniqueKeysWithValues: oldLayout.nodeFrames.map { (
            $0.key,
            CGPoint(x: $0.value.midX, y: $0.value.midY)
        ) })
        let newLayout = layout.layout(graph: newGraph, anchors: anchors)

        XCTAssertEqual(match.confidence.tier, .exactName)
        XCTAssertFalse(editScript.operations.isEmpty)
        XCTAssertFalse(oldGraph.edges.isEmpty)
        XCTAssertFalse(newGraph.edges.isEmpty)
        XCTAssertEqual(oldLayout.nodeFrames.count, oldGraph.nodes.count)
        XCTAssertEqual(newLayout.nodeFrames.count, newGraph.nodes.count)
    }

    func testTenCommitReviewCorpusHasQuestionsFromBothRepositories() throws {
        let data = try Data(fixture("revision-corpus", extension: "json").utf8)
        let entries = try JSONDecoder().decode([RevisionCorpusEntry].self, from: data)

        XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(Set(entries.map(\.commit)).count, 10)
        XCTAssertEqual(Set(entries.compactMap(\.repository.pathComponents.last)), ["swift-syntax", "swift-nio"])
        XCTAssertTrue(entries.allSatisfy { !$0.reviewQuestion.isEmpty })
    }

    func testSwiftSyntaxAndSwiftNIOReportSnapshotsAreDeterministic() throws {
        let cases = [
            (
                "SwiftLexicalLookup-old",
                "SwiftLexicalLookup-new",
                "Sources/SwiftLexicalLookup/Scopes/ScopeImplementations.swift",
                "58b966582ddd632593afb6101a147740c244ec89",
                "39d18d4b9960adf8bf01026a5471c98d62fa3f64"
            ),
            (
                "NIOHTTPDecoderLimits-old",
                "NIOHTTPDecoderLimits-new",
                "Sources/NIOHTTP1/HTTPDecoder.swift",
                "404f73261919151cfcd93ee46aa9b1ab0be4ef4a",
                "eeb20e7f958f608064360d16542d16bf3219170c"
            )
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (oldFixture, newFixture, path, base, target) in cases {
            let comparison = try RevisionComparison(
                base: RevisionIdentity(base),
                target: RevisionIdentity(target),
                files: [FileComparison(
                    old: snapshot(fixture(oldFixture), path: path, revision: base),
                    new: snapshot(fixture(newFixture), path: path, revision: target)
                )]
            )
            let first = try FlowDeltaAnalyzer().analyze(comparison)
            let second = try FlowDeltaAnalyzer().analyze(comparison)

            XCTAssertEqual(first, second)
            XCTAssertEqual(try encoder.encode(first), try encoder.encode(second))
            XCTAssertFalse(first.functionDeltas.isEmpty)
        }
    }
}
