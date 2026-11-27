import AppKit
import FlowDeltaCore
import FlowDeltaLayout
import FlowDeltaUI
import XCTest

@MainActor
final class FlowGraphViewTests: XCTestCase {
    func testThirtyNodeGraphRendersIntoCALayerScene() throws {
        let graph = makeGraph(nodeCount: 30)
        let result = DominatorAnchoredLayout().layout(graph: graph)
        let view = FlowGraphView(frame: CGRect(origin: .zero, size: result.contentSize))
        view.display(graph: graph, layout: result)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.renderedNodeCount, 30)
        XCTAssertEqual(view.renderedEdgeCount, 31)
        XCTAssertEqual(view.frame.size, result.contentSize)
        XCTAssertEqual(view.subviews.count { $0.isAccessibilityElement() }, 30)

        view.selectNode(withStableID: graph.nodes[4].id.rawValue)
        XCTAssertEqual(view.selectedStableID, graph.nodes[4].id.rawValue)

        let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        XCTAssertNotNil(representation)
        if let representation {
            view.cacheDisplay(in: view.bounds, to: representation)
            XCTAssertGreaterThan(representation.pixelsWide, 0)
            XCTAssertGreaterThan(representation.pixelsHigh, 0)
            if let outputPath = ProcessInfo.processInfo.environment["FLOWDELTA_M0_SCREENSHOT_PATH"],
               let data = representation.representation(using: .png, properties: [:])
            {
                try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            }
        }
    }

    func testChangedGraphInstallsStagedCoreAnimations() {
        let oldGraph = makeGraph(nodeCount: 5)
        let newGraph = makeGraph(nodeCount: 6)
        let layout = DominatorAnchoredLayout()
        let oldResult = layout.layout(graph: oldGraph)
        let newResult = layout.layout(graph: newGraph)
        let view = FlowGraphView(frame: CGRect(origin: .zero, size: oldResult.contentSize))
        view.display(graph: oldGraph, layout: oldResult)
        view.display(graph: newGraph, layout: newResult, animated: true)

        XCTAssertTrue(view.hasActiveNodeAnimations())
    }

    func testFocusSelectsAVisibleNodeWhenTheSelectionLeftTheGraph() throws {
        let engine = DominatorAnchoredLayout()
        let wide = makeGraph(nodeCount: 4)
        let narrow = makeGraph(nodeCount: 3)
        let view = FlowGraphView(frame: CGRect(origin: .zero, size: engine.layout(graph: wide).contentSize))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentView?.addSubview(view)
        view.display(graph: wide, layout: engine.layout(graph: wide))
        view.selectNode(withStableID: "node-3")
        view.display(graph: narrow, layout: engine.layout(graph: narrow))
        XCTAssertFalse(view.renderedStableIDs.contains("node-3"))

        XCTAssertTrue(window.makeFirstResponder(view))
        let selected = try XCTUnwrap(view.selectedStableID)
        XCTAssertTrue(view.renderedStableIDs.contains(selected), selected)
        XCTAssertNotEqual(view.focusRingMaskBounds, view.bounds)

        XCTAssertTrue(window.makeFirstResponder(nil))
        view.selectNode(withStableID: "node-1")
        XCTAssertTrue(window.makeFirstResponder(view))
        XCTAssertEqual(view.selectedStableID, "node-1", "A selection still on screen is kept")
    }

    private func makeGraph(nodeCount: Int) -> ControlFlowGraph {
        let ids = (0 ..< nodeCount).map { StableID(rawValue: "node-\($0)") }
        let nodes = ids.enumerated().map { offset, id in
            FlowNode(
                id: id,
                kind: offset == 0 ? .entry : (offset == nodeCount - 1 ? .exit : .basicBlock),
                label: "Node \(offset)",
                sourceOrder: offset
            )
        }
        var edges = zip(ids, ids.dropFirst()).map {
            FlowEdge(source: $0.0, target: $0.1, kind: .fallthrough)
        }
        if nodeCount == 30 {
            edges.removeAll {
                ($0.source == ids[1] && $0.target == ids[2])
                    || ($0.source == ids[2] && $0.target == ids[3])
            }
            edges.append(FlowEdge(source: ids[1], target: ids[2], kind: .conditionTrue, label: "true"))
            edges.append(FlowEdge(source: ids[1], target: ids[3], kind: .conditionFalse, label: "false"))
            edges.append(FlowEdge(source: ids[2], target: ids[4], kind: .fallthrough))
            edges.append(FlowEdge(source: ids[10], target: ids[4], kind: .loopBack, label: "repeat"))
        }
        return ControlFlowGraph(
            entityID: StableID(rawValue: "entity-\(nodeCount)"),
            nodes: nodes,
            edges: edges,
            entryID: ids[0],
            exitID: ids[nodeCount - 1],
            errorExitID: ids[nodeCount - 1]
        )
    }
}
