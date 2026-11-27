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

    func testARevisionWithNoChangesClearsThePreviousFunction() throws {
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        let report = try FlowDeltaAnalyzer().analyze(RevisionComparison(
            base: base,
            target: target,
            files: [FileComparison(
                old: SourceSnapshot(
                    path: "A.swift",
                    revision: base,
                    language: .swift,
                    text: "func a() -> Int {\n    1\n}\n"
                ),
                new: SourceSnapshot(
                    path: "A.swift",
                    revision: target,
                    language: .swift,
                    text: "func a() -> Int {\n    2\n}\n"
                )
            )]
        ))
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        view.display(report)
        XCTAssertNotNil(view.state.selectedFunctionName)
        XCTAssertFalse(view.displayedNodeStates.isEmpty)
        try view.selectGraphNode(withStableID: XCTUnwrap(view.sourceBackedNodeStableIDs.first))

        view.display(RevisionFlowDeltaReport(base: RevisionIdentity("c"), target: RevisionIdentity("d"), files: []))
        XCTAssertEqual(view.triageRowCount, 0)
        XCTAssertEqual(view.displayedFunctionName, "")
        XCTAssertNil(view.state.selectedFunctionName)
        XCTAssertNil(view.state.selectedNodeStableID)
        XCTAssertEqual(view.currentGraphNodeStableIDs, [])
        XCTAssertEqual(view.sourceBackedNodeStableIDs, [])
        XCTAssertEqual(view.displayedNodeStates, [:])
        XCTAssertEqual(view.renderedGraphNodeCount, 1, "A placeholder replaces the previous graph")
        let source = try XCTUnwrap(view.sourceViews.first)
        XCTAssertNil(source.displayedPath)
    }
}

private extension NSView {
    var sourceViews: [FlowSourceView] {
        subviews.compactMap { $0 as? FlowSourceView } + subviews.flatMap(\.sourceViews)
    }
}
