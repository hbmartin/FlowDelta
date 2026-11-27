import AppKit
import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaUI
import XCTest

@MainActor
final class FlowDeltaReviewSelectionTests: XCTestCase {
    func testRevisionWithoutFunctionChangesSelectsItsFirstEntityAndShowsNoGraph() throws {
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        let report = try FlowDeltaAnalyzer().analyze(RevisionComparison(
            base: base,
            target: target,
            files: [FileComparison(
                old: SourceSnapshot(
                    path: "Policy.swift",
                    revision: base,
                    language: .swift,
                    text: "struct Policy { let surcharge = 10 }\n"
                ),
                new: SourceSnapshot(
                    path: "Policy.swift",
                    revision: target,
                    language: .swift,
                    text: "struct Policy { let surcharge = 15 }\n"
                )
            )]
        ))
        XCTAssertTrue(report.functionDeltas.isEmpty)

        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        view.display(report)

        XCTAssertGreaterThan(view.triageRowCount, 0)
        XCTAssertEqual(view.displayedFunctionName, "Policy", "No function changed, so the first entity is selected")
        XCTAssertEqual(view.currentGraphNodeStableIDs, [])
        XCTAssertEqual(view.sourceBackedNodeStableIDs, [])
        XCTAssertEqual(view.displayedNodeStates, [:])
    }
}
