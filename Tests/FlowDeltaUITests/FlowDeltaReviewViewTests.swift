import AppKit
import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaUI
import SnapshotTesting
import XCTest

@MainActor
final class FlowDeltaReviewViewTests: XCTestCase {
    func testReviewViewMatchesNativeReferenceSnapshot() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        try view.display(makeReport())
        view.layoutSubtreeIfNeeded()

        let shouldRecord = ProcessInfo.processInfo.environment["FLOWDELTA_RECORD_SNAPSHOTS"] == "1"
        let snapshotDirectory = shouldRecord
            ? nil
            : Bundle.module.resourceURL?
            .appendingPathComponent("__Snapshots__/FlowDeltaReviewViewTests", isDirectory: true)
            .path
        let failure = verifySnapshot(
            of: view,
            as: .image(precision: 0.99, perceptualPrecision: 0.98),
            record: shouldRecord ? .all : .never,
            snapshotDirectory: snapshotDirectory
        )
        if let failure {
            XCTFail(failure)
        }

        if let outputPath = ProcessInfo.processInfo.environment["FLOWDELTA_M1_SCREENSHOT_PATH"],
           let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        {
            view.cacheDisplay(in: view.bounds, to: representation)
            if let data = representation.representation(using: .png, properties: [:]) {
                try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            }
        }
    }

    func testSourcePaneHighlightsAndSelectsUTF16Range() {
        let source = "func greet() { print(\"Hello\") }"
        let snapshot = SourceSnapshot(
            path: "Greeting.swift",
            revision: RevisionIdentity("target"),
            language: .swift,
            text: source
        )
        let start = source.utf16.distance(
            from: source.utf16.startIndex,
            to: source.utf16.index(source.utf16.startIndex, offsetBy: 15)
        )
        let range = SourceRange(
            start: SourceLocation(utf8Offset: start, utf16Offset: start, line: 0, utf16Column: start),
            end: SourceLocation(utf8Offset: start + 5, utf16Offset: start + 5, line: 0, utf16Column: start + 5)
        )
        let view = FlowSourceView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        view.display(snapshot, title: "Target source")
        view.select(range)

        XCTAssertEqual(view.textView.string, source)
        XCTAssertEqual(view.textView.selectedRange(), NSRange(location: start, length: 5))
        XCTAssertNotNil(view.textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil))
    }

    func testReviewSelectionSynchronizesSourceAndForwardSlice() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        try view.display(makeReport())
        let sourceNode = try XCTUnwrap(view.sourceBackedNodeStableIDs.first)

        XCTAssertEqual(view.triageRowCount, 4)
        XCTAssertTrue(view.displayedFunctionName.contains("shippingTotal"))
        XCTAssertFalse(view.currentGraphNodeStableIDs.isEmpty)

        view.selectGraphNode(withStableID: sourceNode)
        view.setForwardSliceEnabled(true)

        XCTAssertEqual(view.selectedGraphNodeStableID, sourceNode)
        let emphasized = try XCTUnwrap(view.emphasizedGraphNodeStableIDs)
        XCTAssertTrue(emphasized.contains(sourceNode))
        XCTAssertLessThanOrEqual(emphasized.count, view.currentGraphNodeStableIDs.count)

        view.setForwardSliceEnabled(false)
        XCTAssertNil(view.emphasizedGraphNodeStableIDs)

        try view.selectTriageRow(XCTUnwrap(view.nonCallableTriageRows.first))
        XCTAssertTrue(view.currentGraphNodeStableIDs.isEmpty)
    }

    private func makeReport() throws -> RevisionFlowDeltaReport {
        let old = """
        func shippingTotal(_ items: [Item], priority: Bool) -> Int {
            var total = 0
            for item in items {
                if item.isTaxable {
                    total += item.price + item.tax
                } else {
                    total += item.price
                }
            }
            if priority { total += 10 }
            return total
        }

        func legacyDiscount(_ total: Int) -> Int { total > 100 ? 10 : 0 }

        struct ShippingPolicy { let surcharge = 10 }
        """
        let new = """
        func shippingTotal(_ items: [Item], priority: Bool) -> Int {
            guard !items.isEmpty else { return 0 }
            var total = 0
            for item in items {
                if item.requiresTax {
                    total += item.price + item.tax
                } else {
                    total += item.price
                }
            }
            if priority { total += 15 }
            return total
        }

        func auditOrder(_ items: [Item]) {
            for item in items { audit(item) }
        }

        struct ShippingPolicy { let surcharge = 15 }
        """
        let base = RevisionIdentity("58b966582ddd632593afb6101a147740c244ec89")
        let target = RevisionIdentity("39d18d4b9960adf8bf01026a5471c98d62fa3f64")
        return try FlowDeltaAnalyzer().analyze(RevisionComparison(
            base: base,
            target: target,
            files: [FileComparison(
                old: SourceSnapshot(
                    path: "Sources/Checkout/Shipping.swift",
                    revision: base,
                    language: .swift,
                    text: old
                ),
                new: SourceSnapshot(
                    path: "Sources/Checkout/Shipping.swift",
                    revision: target,
                    language: .swift,
                    text: new
                ),
                unifiedDiff: "@@ reference @@"
            )]
        ))
    }
}
