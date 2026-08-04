import CoreGraphics
import FlowDeltaCore
import FlowDeltaLayout
import XCTest

final class LayoutTests: XCTestCase {
    func testThirtyNodeLayoutIsDeterministicAndRoutesBackEdgeOutside() throws {
        let graph = makeGraph(nodeCount: 30, backEdgeTo: 10)
        let layout = DominatorAnchoredLayout()
        let first = layout.layout(graph: graph)
        let second = layout.layout(graph: graph)
        let backEdge = try XCTUnwrap(graph.edges.first { $0.kind == .loopBack })
        let route = try XCTUnwrap(first.edgeRoutes[backEdge.id])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.nodeFrames.count, 30)
        XCTAssertEqual(first.edgeRoutes.count, graph.edges.count)
        XCTAssertTrue(route.isBackEdge)
        XCTAssertGreaterThanOrEqual(route.points.count, 4)
    }

    func testAnchorKeepsStableNodeAtPreferredHorizontalPosition() throws {
        let graph = makeGraph(nodeCount: 5)
        let anchoredID = graph.nodes[2].id
        let result = DominatorAnchoredLayout().layout(
            graph: graph,
            anchors: [anchoredID: CGPoint(x: 500, y: 300)]
        )
        let frame = try XCTUnwrap(result.nodeFrames[anchoredID])

        XCTAssertEqual(frame.midX, 500, accuracy: 0.001)
    }

    func testThirtyNodeLayoutMeetsSingleFrameBudgetAtP95() {
        let graph = makeGraph(nodeCount: 30, backEdgeTo: 4)
        let layout = DominatorAnchoredLayout()
        let clock = ContinuousClock()
        var milliseconds: [Double] = []

        for _ in 0 ..< 120 {
            let start = clock.now
            _ = layout.layout(graph: graph)
            milliseconds.append(Self.milliseconds(clock.now - start))
        }
        milliseconds.sort()
        let p95 = milliseconds[Int(Double(milliseconds.count - 1) * 0.95)]

        XCTAssertLessThan(p95, 16.67, "30-node p95 layout was \(p95) ms")
    }

    func testTransitionFadesMovesThenReveals() throws {
        let removed = StableID(rawValue: "removed")
        let retained = StableID(rawValue: "retained")
        let added = StableID(rawValue: "added")
        let oldFrame = CGRect(x: 0, y: 0, width: 100, height: 40)
        let newFrame = CGRect(x: 200, y: 100, width: 120, height: 50)
        let transition = StagedLayoutTransition(
            oldFrames: [removed: oldFrame, retained: oldFrame],
            newFrames: [retained: newFrame, added: newFrame]
        )

        let removalPhase = Dictionary(uniqueKeysWithValues: transition.states(at: 0.125).map { ($0.id, $0) })
        XCTAssertEqual(try XCTUnwrap(removalPhase[removed]).opacity, 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(removalPhase[added]).opacity, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(removalPhase[retained]).frame, oldFrame)

        let movementPhase = Dictionary(uniqueKeysWithValues: transition.states(at: 0.5).map { ($0.id, $0) })
        let movedFrame = try XCTUnwrap(movementPhase[retained]).frame
        XCTAssertGreaterThan(movedFrame.midX, oldFrame.midX)
        XCTAssertLessThan(movedFrame.midX, newFrame.midX)

        let revealPhase = Dictionary(uniqueKeysWithValues: transition.states(at: 0.875).map { ($0.id, $0) })
        XCTAssertEqual(try XCTUnwrap(revealPhase[removed]).opacity, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(revealPhase[added]).opacity, 0.5, accuracy: 0.001)
    }

    private func makeGraph(nodeCount: Int, backEdgeTo: Int? = nil) -> ControlFlowGraph {
        precondition(nodeCount >= 3)
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
        if let backEdgeTo {
            edges.append(FlowEdge(source: ids[nodeCount - 2], target: ids[backEdgeTo], kind: .loopBack))
        }
        return ControlFlowGraph(
            entityID: StableID(rawValue: "entity"),
            nodes: nodes,
            edges: edges,
            entryID: ids[0],
            exitID: ids[nodeCount - 1],
            errorExitID: ids[nodeCount - 1]
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
