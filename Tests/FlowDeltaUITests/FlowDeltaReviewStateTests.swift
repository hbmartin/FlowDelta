import AppKit
import FlowDeltaCore
import FlowDeltaUI
import XCTest

/// The review's reported state names what is on screen: the source of a call, the slice and the selection.
@MainActor
final class FlowDeltaReviewStateTests: XCTestCase {
    func testRemovedCallNodesShowTheBaseSource() throws {
        let original = try makeShippingReport()
        let function = try XCTUnwrap(original.functionDeltas.first { $0.displayName.contains("shippingTotal") })
        let comparison = try XCTUnwrap(original.files.first { $0.path == function.path }?.comparison)
        let old = try XCTUnwrap(comparison.old)
        let new = try XCTUnwrap(comparison.new)
        XCTAssertNotEqual(old.text, new.text)
        let root = CallGraphNode(
            id: StableID(namespace: "test-call", components: ["root"]),
            name: function.displayName,
            path: function.path,
            range: function.nodes.compactMap { $0.new?.sourceRanges.first }.first,
            state: .modified
        )
        let removed = CallGraphNode(
            id: StableID(namespace: "test-call", components: ["removed"]),
            name: "legacyDiscount",
            path: function.path,
            range: function.nodes.compactMap { $0.old?.sourceRanges.last }.last,
            state: .removed
        )
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        view.display(replacingCallGraph(in: original, with: CallGraph(
            nodes: [root, removed],
            edges: [CallGraphEdge(caller: root.id, callee: removed.id, state: .removed)]
        )))
        view.setPresentation(.calls)
        let source = try XCTUnwrap(view.descendants(of: FlowSourceView.self).first)

        view.selectGraphNode(withStableID: removed.id.rawValue)
        XCTAssertEqual(source.textView.string, old.text, "A removed function's range belongs to the base")
        XCTAssertEqual(source.displayedTitle, "Base call source")
        view.selectGraphNode(withStableID: root.id.rawValue)
        XCTAssertEqual(source.textView.string, new.text)
        XCTAssertEqual(source.displayedTitle, "Call source")
    }

    func testTheReportedSliceIsTheSliceOnScreen() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        let recorder = ReviewStateRecorder()
        view.delegate = recorder
        try view.display(makeShippingReport())

        view.setSlice(.forward)
        XCTAssertNil(view.emphasizedGraphNodeStableIDs)
        XCTAssertNil(view.state.slice, "Without a selected node no slice is drawn")
        let node = try XCTUnwrap(view.sourceBackedNodeStableIDs.first)
        view.selectGraphNode(withStableID: node)
        XCTAssertNotNil(view.emphasizedGraphNodeStableIDs)
        XCTAssertEqual(view.state.slice, .forward)
        XCTAssertEqual(recorder.states.last?.slice, .forward)

        view.setPresentation(.calls)
        view.setSlice(.backward)
        XCTAssertNil(view.state.slice, "Calls draw no slice")
        XCTAssertNil(recorder.states.last?.slice)
        let slice = try XCTUnwrap(view.descendants(of: NSButton.self).first { $0.title == "Slice" })
        XCTAssertEqual(slice.state, .off)
        view.setPresentation(.delta)
        view.setSlice(nil)
        XCTAssertNil(view.state.slice)
    }

    func testBeforeAfterSelectionsInEitherGraphAreTheReviewSelection() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        let recorder = ReviewStateRecorder()
        view.delegate = recorder
        try view.display(makeShippingReport())
        view.setPresentation(.beforeAfter)
        let graphs = view.descendants(of: FlowGraphView.self)
        let base = try XCTUnwrap(graphs.first { $0.accessibilityIdentifier() == "FlowDelta.Review.Graph" })
        let target = try XCTUnwrap(graphs.first { $0.accessibilityIdentifier() == "FlowDelta.Review.ComparisonGraph" })

        base.keyDown(with: Self.keyEvent(Self.functionKey(NSEndFunctionKey), code: 119))
        let baseNode = try XCTUnwrap(base.selectedStableID)
        XCTAssertEqual(view.state.selectedNodeStableID, baseNode)
        target.keyDown(with: Self.keyEvent(Self.functionKey(NSHomeFunctionKey), code: 115))
        let targetNode = try XCTUnwrap(target.selectedStableID)
        XCTAssertNotEqual(targetNode, baseNode)
        XCTAssertEqual(view.state.selectedNodeStableID, targetNode)
        XCTAssertEqual(recorder.states.last?.selectedNodeStableID, targetNode)
        XCTAssertEqual(recorder.causes.last, .user)
        XCTAssertNil(base.selectedStableID, "One node is selected across the pair")

        view.setPresentation(.delta)
        XCTAssertNil(target.selectedStableID, "Hiding the target graph clears its selection")
        XCTAssertNil(view.state.selectedNodeStableID)
    }

    func testTriageNamesARemovedEntityByItsBaseDeclaration() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        try view.display(makeShippingReport())
        let table = try XCTUnwrap(view.descendants(of: NSTableView.self).first {
            $0.accessibilityIdentifier() == "FlowDelta.Review.Triage"
        })
        let change = try XCTUnwrap(table.tableColumns.first { $0.identifier.rawValue == "change" })
        let name = try XCTUnwrap(table.tableColumns.first { $0.identifier.rawValue != "change" })
        let rows = (0 ..< view.numberOfRows(in: table)).map { row in
            [change, name].map { column in
                (view.tableView(table, viewFor: column, row: row) as? NSTableCellView)?.textField?.stringValue ?? ""
            }
        }
        let removed = try XCTUnwrap(rows.first { $0.first == "Removed" }, "\(rows)")
        XCTAssertTrue(
            removed[1].contains("legacyDiscount"),
            "A removed entity has no new side, so it is named by its base: \(removed)"
        )
    }
}
