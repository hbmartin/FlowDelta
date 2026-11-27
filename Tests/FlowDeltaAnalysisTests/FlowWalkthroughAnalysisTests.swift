import FlowDeltaAnalysis
import FlowDeltaCore
import XCTest

final class FlowWalkthroughAnalysisTests: XCTestCase {
    func testAnInsertedGuardIsOneStepThatNamesWhatItAffects() throws {
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        let file = FileComparison(
            old: SourceSnapshot(path: "Cart.swift", revision: base, language: .swift, text: """
            func total(items: [Int]) -> Int {
                var sum = 0
                for item in items { sum += item }
                return sum
            }
            """),
            new: SourceSnapshot(path: "Cart.swift", revision: target, language: .swift, text: """
            func total(items: [Int]) -> Int {
                guard items.isEmpty == false else { return 0 }
                var sum = 0
                for item in items { sum += item }
                return sum
            }
            """)
        )
        let report = try FlowDeltaAnalyzer().analyze(RevisionComparison(base: base, target: target, files: [file]))
        let steps = FlowWalkthrough.steps(for: report, policy: .hideCosmetic)
        let first = try XCTUnwrap(steps.first)
        XCTAssertTrue(first.narration.hasPrefix("Adds `guard items.isEmpty == false"), first.narration)
        XCTAssertTrue(first.narration.contains("by control"), first.narration)
        XCTAssertFalse(first.affectedNodeIDs.isEmpty)
        XCTAssertTrue(first.functionName.hasPrefix("total"))
    }
}
