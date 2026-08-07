@testable import FlowDeltaCore
import Foundation
import XCTest

final class CoreModelTests: XCTestCase {
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
