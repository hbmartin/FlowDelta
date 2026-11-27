@testable import FlowDeltaAnalysis
import FlowDeltaCore
import XCTest

final class HeuristicConcernGrouperTests: XCTestCase {
    func testUnrelatedChangesInSeparateFilesAreATangledRevision() throws {
        let report = try analyze([
            ("A.swift", "func alpha() -> Int {\n    return 1\n}\n", "func alpha() -> Int {\n    return 2\n}\n"),
            ("B.swift", "func beta() -> Int {\n    return 1\n}\n", "func beta() -> Int {\n    return 3\n}\n")
        ])
        let concerns = try XCTUnwrap(report.concerns)
        XCTAssertEqual(concerns.map(\.kind), [.behavioral, .behavioral])
        XCTAssertEqual(concerns.map(\.title), ["`alpha`", "`beta`"])
        XCTAssertTrue(report.isTangled)
        let beta = try XCTUnwrap(report.entityChanges.first { $0.new?.name == "beta" })
        XCTAssertEqual(report.concern(containing: beta)?.title, "`beta`")
    }

    func testCallsAndReferencesJoinChangedEntities() throws {
        let report = try analyze([
            (
                "A.swift",
                "func caller() -> Int {\n    return 1\n}\n",
                "func caller() -> Int {\n    return callee() + 1\n}\n"
            ),
            ("B.swift", "", "func callee() -> Int {\n    return 2\n}\n"),
            ("C.swift", "", "struct Price {\n    let cents: Int\n}\n"),
            (
                "D.swift",
                "func charge() -> Int {\n    return 0\n}\n",
                "func charge() -> Int {\n    let price = Price(cents: 3)\n    return price.cents\n}\n"
            )
        ])
        let concerns = try XCTUnwrap(report.concerns)
        XCTAssertEqual(concerns.count, 2, concerns.map(\.title).description)
        XCTAssertEqual(concerns.map(\.title), ["`caller` and 1 related change", "`Price` and 1 related change"])
        XCTAssertEqual(concerns[0].links.map(\.reason), [.call])
        XCTAssertEqual(concerns[1].links.map(\.reason), [.reference])
        XCTAssertTrue(report.isTangled)
    }

    func testMembersOfOneTypeJoinAndAnUnchangedTypeBodyComesWithThem() throws {
        let report = try analyze([(
            "Cart.swift",
            "struct Cart {\n    func total() -> Int {\n        return 1\n    }\n"
                + "    func count() -> Int {\n        return 2\n    }\n}\n",
            "struct Cart {\n    func total() -> Int {\n        return 10\n    }\n"
                + "    func count() -> Int {\n        return 20\n    }\n}\n"
        )])
        let concerns = try XCTUnwrap(report.concerns)
        XCTAssertEqual(concerns.count, 1)
        XCTAssertEqual(concerns[0].title, "`Cart` and 2 related changes")
        XCTAssertEqual(Set(concerns[0].links.map(\.reason)), [.sameType, .container])
        XCTAssertFalse(report.isTangled)
    }

    func testATypeWithItsOwnChangeIsBehavioralAndJoinsItsMembers() throws {
        let report = try analyze([(
            "Cart.swift",
            "struct Cart {\n    func total() -> Int {\n        return 1\n    }\n}\n",
            "struct Cart {\n    var discount = 0\n    func total() -> Int {\n        return 1 - 2\n    }\n}\n"
        )])
        let concerns = try XCTUnwrap(report.concerns)
        XCTAssertEqual(concerns.map(\.kind), [.behavioral])
        XCTAssertEqual(concerns[0].memberIDs.count, 2)
        XCTAssertEqual(concerns[0].links.map(\.reason), [.sameType])
    }

    func testCosmeticAndRefactoringChangesFormTheirOwnGroups() throws {
        let report = try analyze([
            (
                "A.swift",
                "func tidy(x: Int) -> Int {\n    if (x > 0) { return 1 }\n    return x\n}\n",
                "func tidy(x: Int) -> Int {\n    if x > 0 { return 1 }\n    return x\n}\n"
            ),
            (
                "B.swift",
                "func bump(x: Int) -> Int {\n    var y = x\n    y = y + 1\n    return y\n}\n",
                "func bump(x: Int) -> Int {\n    var y = x\n    y += 1\n    return y\n}\n"
            ),
            ("C.swift", "func before() -> Int {\n    return 42\n}\n", "func after() -> Int {\n    return 42\n}\n"),
            (
                "D.swift",
                "struct Box {\n    func open() -> Int {\n        return self.value;\n    }\n}\n",
                "struct Box {\n    func open() -> Int {\n        return value\n    }\n}\n"
            )
        ])
        let concerns = try XCTUnwrap(report.concerns)
        XCTAssertEqual(concerns.map(\.kind), [.refactoring, .cosmetic], concerns.map(\.title).description)
        XCTAssertEqual(concerns.map(\.title), ["Renames, moves and rewrites", "Formatting and cosmetic changes"])
        let names = { (concern: FlowConcern) in
            Set(concern.memberIDs.compactMap { id in report.entityChanges.first { $0.entityID == id }?.new?.name })
        }
        XCTAssertEqual(names(concerns[0]), ["bump", "after"])
        XCTAssertEqual(names(concerns[1]), ["tidy", "open", "Box"], "A container goes with its cosmetic member")
        XCTAssertFalse(report.isTangled)
    }

    func testARenameWithABodyChangeIsBehavioral() {
        let change = EntityChange(kind: .renamed, old: nil, new: nil, confidence: nil)
        XCTAssertEqual(HeuristicConcernGrouper.classify(change, function: nil, in: []), .behavioral)
        XCTAssertNil(HeuristicConcernGrouper().concerns(for: RevisionFlowDeltaReport(
            base: RevisionIdentity("a"), target: RevisionIdentity("b"), files: []
        )).first)
    }

    func testReportsWithoutConcernsStillDecode() throws {
        let json = #"{"base":{"value":"a"},"target":{"value":"b"},"files":[],"diagnostics":[]}"#
        let report = try JSONDecoder().decode(RevisionFlowDeltaReport.self, from: Data(json.utf8))
        XCTAssertNil(report.concerns)
        XCTAssertFalse(report.isTangled)
    }

    func testReferencesAreBareIdentifiersOnly() {
        let tokens = [
            "let",
            "x",
            ":",
            "Price",
            "=",
            "make",
            "(",
            "package",
            ":",
            "1",
            ",",
            "other",
            ".",
            "total",
            ")",
            "_y2"
        ]
        XCTAssertEqual(HeuristicConcernGrouper.references(in: tokens), ["let", "Price", "make", "other", "_y2"])
        XCTAssertEqual(HeuristicConcernGrouper.references(in: ["f", "(", "key", "=", "1", ")", "\"text\""]), ["f"])
    }

    func testUnionFindJoinsOnceAndTracksSizes() {
        var sets = UnionFind(count: 4)
        XCTAssertTrue(sets.union(0, 1))
        XCTAssertFalse(sets.union(1, 0))
        XCTAssertTrue(sets.union(2, 1))
        XCTAssertEqual(sets.size(of: 2), 3)
        XCTAssertEqual(sets.size(of: 3), 1)
        XCTAssertEqual(sets.find(0), sets.find(2))
    }

    private func analyze(_ files: [(path: String, old: String, new: String)]) throws -> RevisionFlowDeltaReport {
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        return try FlowDeltaAnalyzer().analyze(RevisionComparison(base: base, target: target, files: files.map { file in
            FileComparison(
                old: file.old.isEmpty ? nil : SourceSnapshot(
                    path: file.path,
                    revision: base,
                    language: .swift,
                    text: file.old
                ),
                new: SourceSnapshot(path: file.path, revision: target, language: .swift, text: file.new)
            )
        }))
    }
}
