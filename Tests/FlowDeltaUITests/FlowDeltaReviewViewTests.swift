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
        try view.display(makeShippingReport())
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
        try view.display(makeShippingReport())
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
        try view.display(makeShippingReport())
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
        let original = try makeShippingReport()
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

    func testDelegateHearsEachStateChangeOnceWithItsCause() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        let recorder = ReviewStateRecorder()
        view.delegate = recorder
        try view.display(makeShippingReport())
        XCTAssertEqual(recorder.causes, [.host])
        XCTAssertEqual(recorder.states.last?.presentation, .delta)
        XCTAssertNil(recorder.states.last?.slice)
        let functionName = try XCTUnwrap(recorder.states.last?.selectedFunctionName)
        XCTAssertTrue(view.displayedFunctionName.hasPrefix(functionName), view.displayedFunctionName)

        view.setPresentation(.beforeAfter)
        XCTAssertEqual(view.presentation, .beforeAfter)
        XCTAssertEqual(view.reviewMode, 1)
        XCTAssertTrue(view.comparisonGraphIsVisible)
        view.setPresentation(.beforeAfter)
        view.setReviewMode(7)
        XCTAssertEqual(recorder.causes, [.host, .host], "Unchanged and out-of-range requests report nothing")

        let mode = try XCTUnwrap(view.descendants(of: NSSegmentedControl.self).first {
            $0.accessibilityLabel() == "Flow presentation"
        })
        mode.selectedSegment = FlowReviewPresentation.delta.rawValue
        XCTAssertTrue(mode.sendAction(mode.action, to: mode.target))
        XCTAssertEqual(recorder.causes.last, .user)
        XCTAssertEqual(recorder.states.last?.presentation, .delta)

        let node = try XCTUnwrap(view.sourceBackedNodeStableIDs.first)
        view.selectGraphNode(withStableID: node)
        XCTAssertEqual(recorder.states.last?.selectedNodeStableID, node)
        XCTAssertEqual(recorder.causes.last, .host)

        view.setSlice(.backward)
        XCTAssertEqual(view.sliceDirection, .backward)
        XCTAssertNotNil(view.emphasizedGraphNodeStableIDs)
        view.setSlice(nil)
        XCTAssertNil(view.sliceDirection)
        view.setForwardSliceEnabled(true)
        XCTAssertEqual(recorder.states.last?.slice, .forward)
        view.setBackwardSliceEnabled(false)
        XCTAssertNil(recorder.states.last?.slice)
        XCTAssertEqual(recorder.causes.suffix(4), [.host, .host, .host, .host])

        let slice = try XCTUnwrap(view.descendants(of: NSButton.self).first { $0.title == "Slice" })
        slice.performClick(nil)
        XCTAssertEqual(recorder.causes.last, .user)
        XCTAssertEqual(recorder.states.last?.slice, .backward)

        view.selectTriageRow(view.nonCallableTriageRows.first ?? 0)
        XCTAssertEqual(recorder.causes.last, .host)
        XCTAssertEqual(recorder.states.count, recorder.causes.count)

        let plainDelegate = PlainReviewDelegate()
        XCTAssertTrue(plainDelegate.flowDeltaReviewView(view, menuItemsForNodeWithStableID: node).isEmpty)
    }

    func testNodeMenusSliceCopyAndAppendHostItems() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        let recorder = ReviewStateRecorder()
        recorder.extraItems = [NSMenuItem(title: "Host Command", action: nil, keyEquivalent: "")]
        view.delegate = recorder
        view.pasteboard = NSPasteboard(name: NSPasteboard.Name("FlowDeltaReviewViewTests-\(UUID().uuidString)"))
        try view.display(makeShippingReport())
        let node = try XCTUnwrap(view.sourceBackedNodeStableIDs.first)

        let menu = try XCTUnwrap(view.contextMenu(forNodeWithStableID: node))
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "-" : $0.title }, [
            "Show Source", "-", "Forward Slice from Here", "Backward Slice from Here", "-", "Copy Label",
            "Copy Location",
            "-", "Host Command"
        ])
        XCTAssertEqual(menu.items.first?.identifier?.rawValue, "FlowDelta.Review.NodeMenu.showSource")

        try perform("Backward Slice from Here", in: menu)
        XCTAssertEqual(view.sliceDirection, .backward)
        XCTAssertEqual(view.selectedGraphNodeStableID, node)
        XCTAssertNotNil(view.emphasizedGraphNodeStableIDs)
        XCTAssertEqual(recorder.causes.last, .user)

        let sliced = try XCTUnwrap(view.contextMenu(forNodeWithStableID: node))
        try perform("Clear Slice", in: sliced)
        XCTAssertNil(view.sliceDirection)

        try perform("Copy Label", in: sliced)
        let label = try XCTUnwrap(view.pasteboard.string(forType: .string))
        XCTAssertFalse(label.isEmpty)
        try perform("Copy Location", in: sliced)
        let location = try XCTUnwrap(view.pasteboard.string(forType: .string))
        XCTAssertNotNil(location.range(of: #"^Sources/.+\.swift:[1-9][0-9]*$"#, options: .regularExpression), location)

        try perform("Show Source", in: sliced)
        XCTAssertEqual(view.selectedGraphNodeStableID, node)

        view.setPresentation(.beforeAfter)
        let beforeAfter = try XCTUnwrap(view
            .contextMenu(forNodeWithStableID: view.renderedGraphNodeStableIDs.first ?? node))
        XCTAssertFalse(beforeAfter.items.map(\.title).contains("Forward Slice from Here"))
        view.pasteboard.releaseGlobally()
    }

    func testCallNodeMenuReviewsTheCalledFunction() throws {
        let original = try makeShippingReport()
        let callee = try XCTUnwrap(original.functionDeltas.last)
        let callerFunction = try XCTUnwrap(original.functionDeltas.first)
        XCTAssertNotEqual(callee.displayName, callerFunction.displayName)
        let callerNode = CallGraphNode(
            id: CallGraphNode.stableID(for: callerFunction.entityChange),
            name: callerFunction.displayName,
            path: callerFunction.path,
            range: callerFunction.entityChange.new?.range,
            state: .modified
        )
        let calleeNode = CallGraphNode(
            id: CallGraphNode.stableID(for: callee.entityChange),
            name: callee.displayName,
            path: callee.path,
            range: callee.entityChange.new?.range,
            state: .modified
        )
        let report = replacingCallGraph(
            in: original,
            with: CallGraph(
                nodes: [callerNode, calleeNode],
                edges: [CallGraphEdge(caller: callerNode.id, callee: calleeNode.id, state: .added)]
            )
        )
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        view.display(report)
        view.setPresentation(.calls)

        let menu = try XCTUnwrap(view.contextMenu(forNodeWithStableID: calleeNode.id.rawValue))
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "-" : $0.title }, [
            "Review Function", "Show Source", "-", "Copy Label", "Copy Location"
        ])
        try perform("Review Function", in: menu)
        XCTAssertEqual(view.presentation, .delta)
        XCTAssertTrue(view.displayedFunctionName.hasPrefix(callee.displayName), view.displayedFunctionName)
    }

    func testKeyboardMovesBetweenNodesAndDrivesTheSlice() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        let recorder = ReviewStateRecorder()
        view.delegate = recorder
        try view.display(makeShippingReport())
        let graph = try XCTUnwrap(view.descendants(of: FlowGraphView.self).first {
            $0.accessibilityIdentifier() == "FlowDelta.Review.Graph"
        })
        XCTAssertTrue(graph.acceptsFirstResponder)
        XCTAssertTrue(graph.canBecomeKeyView)

        graph.keyDown(with: Self.keyEvent(Self.functionKey(NSHomeFunctionKey), code: 115))
        let first = try XCTUnwrap(view.selectedGraphNodeStableID)
        XCTAssertEqual(recorder.causes.last, .user)
        graph.keyDown(with: Self.keyEvent(Self.functionKey(NSUpArrowFunctionKey), code: 126))
        XCTAssertEqual(view.selectedGraphNodeStableID, first, "Nothing is above the first node")
        graph.keyDown(with: Self.keyEvent(Self.functionKey(NSDownArrowFunctionKey), code: 125))
        let second = try XCTUnwrap(view.selectedGraphNodeStableID)
        XCTAssertNotEqual(second, first)
        graph.keyDown(with: Self.keyEvent(Self.functionKey(NSEndFunctionKey), code: 119))
        XCTAssertNotEqual(view.selectedGraphNodeStableID, first)
        XCTAssertEqual(graph.focusRingMaskBounds.isEmpty, false)

        graph.keyDown(with: Self.keyEvent(" ", code: 49))
        XCTAssertEqual(view.sliceDirection, .forward)
        XCTAssertNotNil(view.emphasizedGraphNodeStableIDs)
        graph.keyDown(with: Self.keyEvent("\u{1b}", code: 53))
        XCTAssertNil(view.sliceDirection)
        XCTAssertFalse(view.flowGraphView(graph, perform: .cancel), "Escape without a slice is not handled")
        XCTAssertTrue(view.flowGraphView(graph, perform: .activate))

        view.setPresentation(.beforeAfter)
        XCTAssertFalse(view.flowGraphView(graph, perform: .toggleSlice), "Before and after draws no slices")
        graph.selectNode(withStableID: nil)
        XCTAssertFalse(view.flowGraphView(graph, perform: .activate))
    }

    func testReviewExposesStableIdentifiersAndATabOrder() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        try view.display(makeShippingReport())
        XCTAssertEqual(view.accessibilityIdentifier(), "FlowDelta.Review")
        let identifiers = Set(view.descendants(of: NSView.self).map { $0.accessibilityIdentifier() })
        for identifier in [
            "FlowDelta.Review.Revisions", "FlowDelta.Review.Summary", "FlowDelta.Review.Triage",
            "FlowDelta.Review.Function",
            "FlowDelta.Review.Presentation", "FlowDelta.Review.Slice", "FlowDelta.Review.SliceDirection",
            "FlowDelta.Review.Graph", "FlowDelta.Review.Source"
        ] {
            XCTAssertTrue(identifiers.contains(identifier), identifier)
        }
        let table = try XCTUnwrap(view.descendants(of: NSTableView.self).first)
        let graph = try XCTUnwrap(table.nextKeyView as? FlowGraphView)
        XCTAssertEqual(graph.accessibilityIdentifier(), "FlowDelta.Review.Graph")
        XCTAssertEqual(graph.nextKeyView?.accessibilityIdentifier(), "FlowDelta.Review.Source")
        view.setPresentation(.beforeAfter)
        XCTAssertEqual(graph.nextKeyView?.accessibilityIdentifier(), "FlowDelta.Review.ComparisonGraph")
        XCTAssertEqual(graph.nextKeyView?.nextKeyView?.accessibilityIdentifier(), "FlowDelta.Review.Source")
    }

    func testWindowKeepsGraphFocusDuringReviewAndTabsThroughVisiblePanes() throws {
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 820)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        let view = FlowDeltaReviewView(frame: frame)
        window.contentView = view
        try view.display(makeShippingReport())
        let graph = try XCTUnwrap(view.descendants(of: FlowGraphView.self).first)
        let source = try XCTUnwrap(view.descendants(of: NSTextView.self).first)

        XCTAssertTrue(window.makeFirstResponder(graph))
        let first = view.selectedGraphNodeStableID
        window.firstResponder?.keyDown(with: Self.keyEvent(Self.functionKey(NSDownArrowFunctionKey), code: 125))
        XCTAssertNotEqual(view.selectedGraphNodeStableID, first)
        XCTAssertTrue(window.firstResponder === graph)
        window.firstResponder?.keyDown(with: Self.keyEvent(" ", code: 49))
        XCTAssertEqual(view.sliceDirection, .forward)
        window.firstResponder?.keyDown(with: Self.keyEvent("\u{1b}", code: 53))
        XCTAssertNil(view.sliceDirection)
        window.firstResponder?.keyDown(with: Self.keyEvent(Self.functionKey(NSHomeFunctionKey), code: 115))
        XCTAssertEqual(view.selectedGraphNodeStableID, first)
        window.firstResponder?.keyDown(with: Self.keyEvent("\r", code: 36))
        XCTAssertTrue(window.firstResponder === source)

        view.setPresentation(.beforeAfter)
        let target = try XCTUnwrap(graph.nextKeyView as? FlowGraphView)
        XCTAssertTrue(window.makeFirstResponder(graph))
        window.selectNextKeyView(nil)
        XCTAssertTrue(window.firstResponder === target)
        window.selectNextKeyView(nil)
        XCTAssertTrue(window.firstResponder === source)
        window.selectPreviousKeyView(nil)
        XCTAssertTrue(window.firstResponder === target)

        view.setPresentation(.delta)
        XCTAssertTrue(window.makeFirstResponder(graph))
        window.selectNextKeyView(nil)
        XCTAssertTrue(window.firstResponder === source)
        window.selectPreviousKeyView(nil)
        XCTAssertTrue(window.firstResponder === graph)
    }

    private func perform(_ title: String, in menu: NSMenu) throws {
        let item = try XCTUnwrap(menu.items.first { $0.title == title }, "No \(title) item")
        let index = menu.index(of: item)
        menu.performActionForItem(at: index)
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
        let original = try makeShippingReport()
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))

        view.display(replacingCallGraph(in: original, with: nil))
        view.setReviewMode(2)
        XCTAssertEqual(view.renderedGraphNodeCount, 1)

        view.display(replacingCallGraph(in: original, with: CallGraph(nodes: [], edges: [])))
        view.setReviewMode(2)
        XCTAssertEqual(view.renderedGraphNodeCount, 1)
    }

    func testReturningFromCrossFileCallRestoresFunctionSourceAndClearsSlice() throws {
        let original = try makeShippingReport()
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
}

/// Relies on the delegate's default of no extra menu items.
@MainActor
private final class PlainReviewDelegate: FlowDeltaReviewViewDelegate {
    func flowDeltaReviewView(_: FlowDeltaReviewView, didChange _: FlowReviewState, cause _: FlowReviewChangeCause) {}
}
