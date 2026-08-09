import AppKit
import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaUI
import SnapshotTesting
import XCTest

@MainActor
final class FlowDeltaReviewViewTests: XCTestCase {
    func testReviewViewMatchesNativeReferenceSnapshot() throws {
        if ProcessInfo.processInfo.environment["CI"] == "true",
           ProcessInfo.processInfo.environment["FLOWDELTA_VERIFY_NATIVE_SNAPSHOT"] != "1"
        {
            throw XCTSkip(
                "AppKit image snapshots are verified locally unless CI explicitly opts into this host rendering."
            )
        }
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

    func testReviewSupportsBackwardSliceJuxtapositionAndCallNeighborhood() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        try view.display(makeReport())
        let sourceNode = try XCTUnwrap(view.sourceBackedNodeStableIDs.last)
        view.selectGraphNode(withStableID: sourceNode)

        view.setBackwardSliceEnabled(true)
        XCTAssertNotNil(view.emphasizedGraphNodeStableIDs)
        XCTAssertTrue(view.emphasizedGraphNodeStableIDs?.contains(sourceNode) == true)

        view.setReviewMode(1)
        XCTAssertEqual(view.reviewMode, 1)
        XCTAssertTrue(view.comparisonGraphIsVisible)
        XCTAssertGreaterThan(view.comparisonGraphNodeCount, 0)

        view.setReviewMode(2)
        XCTAssertEqual(view.reviewMode, 2)
        XCTAssertFalse(view.comparisonGraphIsVisible)
        XCTAssertGreaterThan(view.renderedGraphNodeCount, 0)
    }

    func testControlActionsAndCallSelectionExerciseNativeInteractions() throws {
        let original = try makeReport()
        let function = try XCTUnwrap(original.functionDeltas.first { $0.displayName.contains("shippingTotal") })
        let root = CallGraphNode(
            id: StableID(namespace: "test-call", components: ["root"]),
            name: function.displayName,
            path: function.path,
            range: function.nodes.compactMap { ($0.new ?? $0.old)?.sourceRanges.first }.first,
            state: .modified
        )
        let callee = CallGraphNode(
            id: StableID(namespace: "test-call", components: ["callee"]),
            name: "auditOrder",
            path: function.path,
            range: function.nodes.compactMap { ($0.new ?? $0.old)?.sourceRanges.last }.last,
            state: .added
        )
        let report = replacingCallGraph(
            in: original,
            with: CallGraph(
                nodes: [root, callee],
                edges: [CallGraphEdge(caller: root.id, callee: callee.id, state: .added)]
            )
        )
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        view.display(report)

        let mode = try XCTUnwrap(view.descendants(of: NSSegmentedControl.self).first {
            $0.accessibilityLabel() == "Flow presentation"
        })
        mode.selectedSegment = 2
        XCTAssertTrue(mode.sendAction(mode.action, to: mode.target))
        XCTAssertEqual(Set(view.renderedGraphNodeStableIDs), [root.id.rawValue, callee.id.rawValue])
        view.selectGraphNode(withStableID: callee.id.rawValue)
        XCTAssertEqual(view.selectedGraphNodeStableID, callee.id.rawValue)

        mode.selectedSegment = 0
        XCTAssertTrue(mode.sendAction(mode.action, to: mode.target))
        let sourceNode = try XCTUnwrap(view.sourceBackedNodeStableIDs.first)
        view.selectGraphNode(withStableID: sourceNode)
        let slice = try XCTUnwrap(view.descendants(of: NSButton.self).first { $0.title == "Slice" })
        slice.performClick(nil)
        let direction = try XCTUnwrap(view.descendants(of: NSSegmentedControl.self).first {
            $0.accessibilityLabel() == "Slice direction"
        })
        direction.selectedSegment = 1
        XCTAssertTrue(direction.sendAction(direction.action, to: direction.target))
        XCTAssertNotNil(view.emphasizedGraphNodeStableIDs)
    }

    func testBeforeAfterModeHandlesAddedAndRemovedFunctions() throws {
        let added = try makeOneSidedReport(old: nil, new: "func added() { print(1) }")
        let removed = try makeOneSidedReport(old: "func removed() { print(1) }", new: nil)
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))

        view.display(added)
        view.setReviewMode(1)
        XCTAssertTrue(view.comparisonGraphIsVisible)
        XCTAssertGreaterThan(view.renderedGraphNodeCount, 0)

        view.display(removed)
        view.setReviewMode(1)
        XCTAssertTrue(view.comparisonGraphIsVisible)
        XCTAssertGreaterThan(view.comparisonGraphNodeCount, 0)
    }

    func testCallsModeHandlesMissingAndEmptyGraphs() throws {
        let original = try makeReport()
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))

        view.display(replacingCallGraph(in: original, with: nil))
        view.setReviewMode(2)
        XCTAssertEqual(view.renderedGraphNodeCount, 1)

        view.display(replacingCallGraph(in: original, with: CallGraph(nodes: [], edges: [])))
        view.setReviewMode(2)
        XCTAssertEqual(view.renderedGraphNodeCount, 1)
    }

    func testReturningFromCrossFileCallRestoresFunctionSourceAndClearsSlice() throws {
        let original = try makeReport()
        let function = try XCTUnwrap(original.functionDeltas.first { $0.displayName.contains("shippingTotal") })
        let otherSnapshot = SourceSnapshot(
            path: "Sources/Checkout/Audit.swift",
            revision: original.target,
            language: .swift,
            text: "func auditOrder() {}"
        )
        let otherFile = FileFlowDelta(
            comparison: FileComparison(old: nil, new: otherSnapshot),
            entityChanges: [],
            functionDeltas: []
        )
        let root = CallGraphNode(
            id: StableID(namespace: "test-call", components: ["source-root"]),
            name: function.displayName,
            path: function.path,
            state: .modified
        )
        let callee = CallGraphNode(
            id: StableID(namespace: "test-call", components: ["cross-file-callee"]),
            name: "auditOrder()",
            path: otherSnapshot.path,
            state: .added
        )
        let report = RevisionFlowDeltaReport(
            base: original.base,
            target: original.target,
            files: original.files + [otherFile],
            callGraph: CallGraph(
                nodes: [root, callee],
                edges: [CallGraphEdge(caller: root.id, callee: callee.id, state: .added)]
            )
        )
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        view.display(report)
        let sourceView = try XCTUnwrap(view.descendants(of: FlowSourceView.self).first)
        let deltaNode = try XCTUnwrap(view.sourceBackedNodeStableIDs.first)
        view.selectGraphNode(withStableID: deltaNode)
        view.setForwardSliceEnabled(true)
        XCTAssertNotNil(view.emphasizedGraphNodeStableIDs)

        view.setReviewMode(2)
        view.selectGraphNode(withStableID: callee.id.rawValue)
        XCTAssertEqual(sourceView.displayedPath, otherSnapshot.path)

        view.setReviewMode(0)
        XCTAssertEqual(sourceView.displayedPath, function.path)
        XCTAssertNil(view.emphasizedGraphNodeStableIDs)
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

    private func makeOneSidedReport(old: String?, new: String?) throws -> RevisionFlowDeltaReport {
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        return try FlowDeltaAnalyzer().analyze(RevisionComparison(
            base: base,
            target: target,
            files: [FileComparison(
                old: old.map {
                    SourceSnapshot(path: "OneSided.swift", revision: base, language: .swift, text: $0)
                },
                new: new.map {
                    SourceSnapshot(path: "OneSided.swift", revision: target, language: .swift, text: $0)
                }
            )]
        ))
    }

    private func replacingCallGraph(
        in report: RevisionFlowDeltaReport,
        with callGraph: CallGraph?
    ) -> RevisionFlowDeltaReport {
        RevisionFlowDeltaReport(
            base: report.base,
            target: report.target,
            files: report.files,
            callGraph: callGraph,
            diagnostics: report.diagnostics
        )
    }
}

private extension NSView {
    func descendants<View: NSView>(of type: View.Type) -> [View] {
        subviews.compactMap { $0 as? View } + subviews.flatMap { $0.descendants(of: type) }
    }
}
