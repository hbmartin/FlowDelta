import FlowDeltaCore
import FlowDeltaMatch
import FlowDeltaParse
import XCTest

final class MatcherTests: XCTestCase {
    private let parser = SwiftSyntaxParser()
    private let extractor = SwiftEntityExtractor()

    func testEntityMatcherUsesExactNameForEditedBody() throws {
        let old = try entities("func calculate(_ value: Int) -> Int { value + 1 }")
        let new = try entities("func calculate(_ value: Int) -> Int { value + 2 }")
        let triage = EntityMatcher().triage(old: old, new: new)

        XCTAssertEqual(triage.matches.count, 1)
        XCTAssertEqual(triage.matches[0].confidence.tier, .exactName)
        XCTAssertEqual(triage.changes[0].kind, .modified)
    }

    func testEntityMatcherUsesStructuralHashForRename() throws {
        let old = try entities("func before(_ value: Int) -> Int { value * 2 }")
        let new = try entities("func after(_ value: Int) -> Int { value * 2 }")
        let triage = EntityMatcher().triage(old: old, new: new)

        XCTAssertEqual(triage.matches.count, 1)
        XCTAssertEqual(triage.matches[0].confidence.tier, .structuralHash)
        XCTAssertEqual(triage.changes[0].kind, .renamed)
    }

    func testEntityMatcherUsesFuzzyTokensForRenameAndEdit() throws {
        let old = try entities("func before(_ value: Int) -> Int { let doubled = value * 2; return doubled }")
        let new = try entities("func after(_ value: Int) -> Int { let doubled = value * 2; audit(doubled); return doubled }")
        let triage = EntityMatcher().triage(old: old, new: new)

        XCTAssertEqual(triage.matches.count, 1)
        XCTAssertEqual(triage.matches[0].confidence.tier, .fuzzyTokens)
        XCTAssertEqual(triage.changes[0].kind, .renamed)
    }

    func testGumTreeProducesUpdateAndInsertOperations() throws {
        let old = try XCTUnwrap(try entities("func value() -> Int { return 1 }").first)
        let new = try XCTUnwrap(try entities("func value() -> Int { audit(); return 2 }").first)
        let script = GumTreeMatcher().match(old: old.body, new: new.body)
        let kinds = Set(script.operations.map(\.kind))

        XCTAssertFalse(script.mappings.isEmpty)
        XCTAssertTrue(kinds.contains(.insert))
        XCTAssertTrue(kinds.contains(.update))
        XCTAssertTrue(script.mappings.allSatisfy { $0.confidence.tier == .gumTree })
    }

    private func entities(_ source: String) throws -> [SourceEntity] {
        let tree = try parser.parse(snapshot(source))
        return extractor.entities(in: tree)
    }
}
