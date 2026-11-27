@testable import FlowDeltaCore
import Foundation
import XCTest

final class CoreModelTests: XCTestCase {
    func testSummarySaysEveryAnalyzedLanguageHasDataContext() {
        XCTAssertEqual(FlowReviewSummary.affectedBasis(for: []), "affected = control context")
        XCTAssertEqual(FlowReviewSummary.affectedBasis(for: [.python, .go]), "affected = control + data context")
        XCTAssertEqual(
            FlowReviewSummary.affectedBasis(for: Set(SourceLanguage.allCases)),
            "affected = control + data context"
        )
    }

    func testSummaryCountsFilesAndFunctionDeltasInTheSingularAndThePlural() {
        func report(files: Int, functionDeltas: Int) -> RevisionFlowDeltaReport {
            let location = SourceLocation(utf8Offset: 0, utf16Offset: 0, line: 0, utf16Column: 0)
            let range = SourceRange(start: location, end: location)
            let entity = SourceEntity(
                id: StableID(rawValue: "f"),
                kind: .function,
                name: "f",
                qualifiedName: "f",
                path: "A.swift",
                range: range,
                body: SyntaxNode(id: StableID(rawValue: "b.f"), kind: "block", range: range, text: "")
            )
            let change = EntityChange(kind: .modified, old: entity, new: entity, confidence: nil)
            let delta = FunctionFlowDelta(
                id: StableID(rawValue: "f.f"),
                entityChange: change,
                editScript: nil,
                oldGraph: nil,
                newGraph: nil,
                nodes: [],
                edges: []
            )
            let snapshot = SourceSnapshot(path: "A.swift", revision: RevisionIdentity("r"), language: .swift, text: "")
            let file = FileFlowDelta(
                comparison: FileComparison(old: snapshot, new: snapshot),
                entityChanges: [change],
                functionDeltas: Array(repeating: delta, count: functionDeltas)
            )
            return RevisionFlowDeltaReport(
                base: RevisionIdentity("a"),
                target: RevisionIdentity("b"),
                files: Array(repeating: file, count: files)
            )
        }

        XCTAssertEqual(
            FlowReviewSummary.text(for: report(files: 1, functionDeltas: 1)),
            "1 file (Swift) • 1 function delta • affected = control + data context"
        )
        XCTAssertEqual(
            FlowReviewSummary.text(for: report(files: 2, functionDeltas: 0)),
            "2 files (Swift) • 0 function deltas • affected = control + data context"
        )
    }

    func testASourceRangeIsHalfOpenInBothEncodings() {
        // In "éaéb" the range covers "aéb". "é" is two UTF-8 bytes but one UTF-16 unit, so the offsets differ.
        let range = SourceRange(
            start: SourceLocation(utf8Offset: 2, utf16Offset: 1, line: 0, utf16Column: 1),
            end: SourceLocation(utf8Offset: 6, utf16Offset: 4, line: 0, utf16Column: 4)
        )
        XCTAssertEqual(range.utf8Range, 2 ..< 6)
        XCTAssertEqual(range.utf16Range, 1 ..< 4)
        XCTAssertFalse(range.isEmpty)
        XCTAssertFalse(range.contains(utf16Offset: 0))
        XCTAssertTrue(range.contains(utf16Offset: 1))
        XCTAssertTrue(range.contains(utf16Offset: 3))
        XCTAssertFalse(range.contains(utf16Offset: 4), "The end is exclusive")

        let empty = sourceRange(3, 3)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(empty.utf8Range.isEmpty)
        XCTAssertFalse(empty.contains(utf16Offset: 3))
    }

    func testSourceLanguageRecognizesM2Extensions() {
        XCTAssertEqual(SourceLanguage(path: "Sources/App.swift"), .swift)
        XCTAssertEqual(SourceLanguage(path: "web/component.tsx"), .typescript)
        XCTAssertEqual(SourceLanguage(path: "web/worker.mjs"), .javascript)
        XCTAssertEqual(SourceLanguage(path: "tools/check.pyi"), .python)
        XCTAssertEqual(SourceLanguage(path: "cmd/server.go"), .go)
        XCTAssertNil(SourceLanguage(path: "README.md"))
    }

    func testCallGraphNeighborhoodIsRadiusLimitedInBothDirections() {
        let caller = StableID(rawValue: "caller")
        let root = StableID(rawValue: "root")
        let callee = StableID(rawValue: "callee")
        let distant = StableID(rawValue: "distant")
        let graph = CallGraph(
            nodes: [caller, root, callee, distant].map {
                CallGraphNode(id: $0, name: $0.rawValue, state: .retained)
            },
            edges: [
                CallGraphEdge(caller: caller, callee: root, state: .retained),
                CallGraphEdge(caller: root, callee: callee, state: .added),
                CallGraphEdge(caller: callee, callee: distant, state: .retained)
            ]
        )

        let neighborhood = graph.neighborhood(around: [root], radius: 1)

        XCTAssertEqual(Set(neighborhood.nodes.map(\.id)), [caller, root, callee])
        XCTAssertEqual(neighborhood.edges.count, 2)
        XCTAssertFalse(neighborhood.nodes.contains { $0.id == distant })
    }

    func testStableIDIsDeterministicAndNamespaced() {
        let first = StableID(namespace: "entity", components: ["a.swift", "f(_:)"])
        let second = StableID(namespace: "entity", components: ["a.swift", "f(_:)"])
        let reordered = StableID(namespace: "entity", components: ["f(_:)", "a.swift"])
        let differentNamespace = StableID(namespace: "syntax", components: ["a.swift", "f(_:)"])

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, reordered)
        XCTAssertNotEqual(first, differentNamespace)
        XCTAssertTrue(first.rawValue.hasPrefix("entity:"))
    }

    func testStructuralDigestRetainsLeafMeaningButIgnoresCommentContents() {
        let range = sourceRange(0, 4)
        let one = SyntaxNode(
            id: StableID(rawValue: "one"),
            kind: "statements",
            range: range,
            text: "x 1",
            children: [
                leaf(id: "identifier-one", kind: "simple_identifier", text: "x"),
                leaf(id: "comment-one", kind: "comment", text: "// first"),
                leaf(id: "integer-one", kind: "integer_literal", text: "1")
            ]
        )
        let commentOnlyChange = SyntaxNode(
            id: StableID(rawValue: "two"),
            kind: "statements",
            range: range,
            text: "x 1",
            children: [
                leaf(id: "identifier-two", kind: "simple_identifier", text: "x"),
                leaf(id: "comment-two", kind: "comment", text: "// second"),
                leaf(id: "integer-two", kind: "integer_literal", text: "1")
            ]
        )
        let semanticChange = SyntaxNode(
            id: StableID(rawValue: "three"),
            kind: "statements",
            range: range,
            text: "x 2",
            children: [
                leaf(id: "identifier-three", kind: "simple_identifier", text: "x"),
                leaf(id: "comment-three", kind: "comment", text: "// second"),
                leaf(id: "integer-three", kind: "integer_literal", text: "2")
            ]
        )

        XCTAssertEqual(one.structuralDigest, commentOnlyChange.structuralDigest)
        XCTAssertNotEqual(one.structuralDigest, semanticChange.structuralDigest)
        XCTAssertEqual(one.normalizedTokens, ["x", "1"])
    }

    func testStructuralDigestKeepsWhitespaceInsideNamedLeavesSuchAsStringContents() {
        func literal(_ content: String, quote: String = "\"") -> SyntaxNode {
            SyntaxNode(
                id: StableID(rawValue: "literal"),
                kind: "string",
                range: sourceRange(0, content.utf16.count + 2),
                text: "\"\(content)\"",
                children: [
                    SyntaxNode(
                        id: StableID(rawValue: "open"),
                        kind: "\"",
                        range: sourceRange(0, 1),
                        text: quote,
                        isNamed: false
                    ),
                    leaf(id: "content", kind: "string_fragment", text: content),
                    SyntaxNode(
                        id: StableID(rawValue: "close"),
                        kind: "\"",
                        range: sourceRange(0, 1),
                        text: "\" ",
                        isNamed: false
                    )
                ]
            )
        }
        XCTAssertNotEqual(literal(" a ").structuralDigest, literal("a").structuralDigest, "\" a \" is not \"a\"")
        XCTAssertEqual(
            literal("a").structuralDigest,
            literal("a", quote: " \"").structuralDigest,
            "Anonymous tokens are trimmed"
        )
    }

    func testCoreModelsRoundTripThroughJSON() throws {
        let snapshot = SourceSnapshot(
            path: "Sources/Emoji.swift",
            revision: RevisionIdentity("abc123"),
            language: .swift,
            text: "let emoji = \"🙂\""
        )
        let comparison = RevisionComparison(
            base: RevisionIdentity("base"),
            target: RevisionIdentity("target"),
            files: [FileComparison(old: snapshot, new: snapshot)]
        )

        let data = try JSONEncoder().encode(comparison)
        XCTAssertEqual(try JSONDecoder().decode(RevisionComparison.self, from: data), comparison)
    }

    func testForwardSliceIncludesReachableControlFlowOnly() {
        let entry = StableID(rawValue: "entry")
        let branch = StableID(rawValue: "branch")
        let end = StableID(rawValue: "end")
        let isolated = StableID(rawValue: "isolated")
        let entity = entityChange()
        let edges = [
            FlowEdge(source: entry, target: branch, kind: .fallthrough),
            FlowEdge(source: branch, target: end, kind: .conditionTrue)
        ].map { FlowEdgeDelta(id: $0.id, old: nil, new: $0, state: .added) }
        let delta = FunctionFlowDelta(
            id: StableID(rawValue: "delta"),
            entityChange: entity,
            editScript: nil,
            oldGraph: nil,
            newGraph: nil,
            nodes: [],
            edges: edges
        )

        XCTAssertEqual(delta.forwardSlice(from: entry), [entry, branch, end])
        XCTAssertEqual(delta.forwardSlice(from: isolated), [isolated])
    }

    private func leaf(id: String, kind: String, text: String) -> SyntaxNode {
        SyntaxNode(id: StableID(rawValue: id), kind: kind, range: sourceRange(0, text.utf16.count), text: text)
    }

    private func sourceRange(_ start: Int, _ end: Int) -> SourceRange {
        SourceRange(
            start: SourceLocation(utf8Offset: start, utf16Offset: start, line: 0, utf16Column: start),
            end: SourceLocation(utf8Offset: end, utf16Offset: end, line: 0, utf16Column: end)
        )
    }

    private func entityChange() -> EntityChange {
        let body = leaf(id: "body", kind: "statements", text: "return")
        let entity = SourceEntity(
            id: StableID(rawValue: "entity"),
            kind: .function,
            name: "f",
            qualifiedName: "f()",
            path: "f.swift",
            range: body.range,
            body: body
        )
        return EntityChange(kind: .added, old: nil, new: entity, confidence: nil)
    }
}
