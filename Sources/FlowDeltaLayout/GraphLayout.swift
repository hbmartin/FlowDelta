import CoreGraphics
import FlowDeltaCore
import Foundation
import OSLog

public struct GraphLayoutConfiguration: Sendable, Hashable {
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat
    public var backEdgeLaneSpacing: CGFloat
    public var contentInsets: CGFloat
    public var defaultNodeSize: CGSize

    public init(
        horizontalSpacing: CGFloat = 44,
        verticalSpacing: CGFloat = 72,
        backEdgeLaneSpacing: CGFloat = 24,
        contentInsets: CGFloat = 36,
        defaultNodeSize: CGSize = CGSize(width: 180, height: 64)
    ) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.backEdgeLaneSpacing = backEdgeLaneSpacing
        self.contentInsets = contentInsets
        self.defaultNodeSize = defaultNodeSize
    }
}

public struct EdgeRoute: Sendable, Hashable, Identifiable {
    public let id: StableID
    public let points: [CGPoint]
    public let isBackEdge: Bool

    public init(id: StableID, points: [CGPoint], isBackEdge: Bool) {
        self.id = id
        self.points = points
        self.isBackEdge = isBackEdge
    }
}

public struct GraphLayoutResult: Sendable, Hashable {
    public let nodeFrames: [StableID: CGRect]
    public let edgeRoutes: [StableID: EdgeRoute]
    public let contentSize: CGSize
    public let ranks: [StableID: Int]

    public init(
        nodeFrames: [StableID: CGRect],
        edgeRoutes: [StableID: EdgeRoute],
        contentSize: CGSize,
        ranks: [StableID: Int]
    ) {
        self.nodeFrames = nodeFrames
        self.edgeRoutes = edgeRoutes
        self.contentSize = contentSize
        self.ranks = ranks
    }
}

public struct DominatorAnchoredLayout: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Layout")
    public let configuration: GraphLayoutConfiguration

    public init(configuration: GraphLayoutConfiguration = .init()) {
        self.configuration = configuration
    }

    public func layout(
        graph: ControlFlowGraph,
        nodeSizes: [StableID: CGSize] = [:],
        anchors: [StableID: CGPoint] = [:]
    ) -> GraphLayoutResult {
        let dominators = computeDominators(graph: graph)
        let backEdgeIDs = Set(graph.edges.compactMap { edge in
            dominators[edge.source]?.contains(edge.target) == true ? edge.id : nil
        })
        let leftAllowance = CGFloat(backEdgeIDs.count) * configuration.backEdgeLaneSpacing
        let ranks = computeRanks(graph: graph, excluding: backEdgeIDs)
        let rankedNodes = Dictionary(grouping: graph.nodes, by: { ranks[$0.id, default: 0] })
        var frames: [StableID: CGRect] = [:]
        var maximumX = configuration.contentInsets + leftAllowance
        var maximumY = configuration.contentInsets

        for rank in rankedNodes.keys.sorted() {
            let ordered = rankedNodes[rank, default: []].sorted {
                let leftAnchor = anchors[$0.id]?.x
                let rightAnchor = anchors[$1.id]?.x
                if leftAnchor != nil || rightAnchor != nil {
                    return (leftAnchor ?? .greatestFiniteMagnitude, $0.sourceOrder, $0.id)
                        < (rightAnchor ?? .greatestFiniteMagnitude, $1.sourceOrder, $1.id)
                }
                return ($0.sourceOrder, $0.id) < ($1.sourceOrder, $1.id)
            }
            var x = configuration.contentInsets + leftAllowance
            let height = ordered.map { nodeSizes[$0.id, default: configuration.defaultNodeSize].height }.max() ?? 0
            let y = configuration.contentInsets + CGFloat(rank) * (height + configuration.verticalSpacing)
            for node in ordered {
                let size = nodeSizes[node.id, default: configuration.defaultNodeSize]
                let preferredX = anchors[node.id].map { max(x, $0.x - size.width / 2) } ?? x
                let frame = CGRect(origin: CGPoint(x: preferredX, y: y), size: size)
                frames[node.id] = frame
                x = frame.maxX + configuration.horizontalSpacing
                maximumX = max(maximumX, frame.maxX)
                maximumY = max(maximumY, frame.maxY)
            }
        }

        var routes: [StableID: EdgeRoute] = [:]
        var backLane = 0
        for edge in graph.edges {
            guard let source = frames[edge.source], let target = frames[edge.target] else { continue }
            let isBackEdge = backEdgeIDs.contains(edge.id)
            let points: [CGPoint]
            if isBackEdge {
                let laneX = min(source.minX, target.minX)
                    - configuration.backEdgeLaneSpacing * CGFloat(backLane + 1)
                backLane += 1
                points = [
                    CGPoint(x: source.midX, y: source.maxY),
                    CGPoint(x: laneX, y: source.maxY + configuration.verticalSpacing / 3),
                    CGPoint(x: laneX, y: target.minY - configuration.verticalSpacing / 3),
                    CGPoint(x: target.midX, y: target.minY)
                ]
            } else {
                let middleY = (source.maxY + target.minY) / 2
                points = [
                    CGPoint(x: source.midX, y: source.maxY),
                    CGPoint(x: source.midX, y: middleY),
                    CGPoint(x: target.midX, y: middleY),
                    CGPoint(x: target.midX, y: target.minY)
                ]
            }
            routes[edge.id] = EdgeRoute(id: edge.id, points: points, isBackEdge: isBackEdge)
        }

        let result = GraphLayoutResult(
            nodeFrames: frames,
            edgeRoutes: routes,
            contentSize: CGSize(
                width: maximumX + configuration.contentInsets,
                height: maximumY + configuration.contentInsets
            ),
            ranks: ranks
        )
        Self.logger.debug("Laid out \(graph.nodes.count) nodes in \(rankedNodes.count) ranks")
        return result
    }

    private func computeDominators(graph: ControlFlowGraph) -> [StableID: Set<StableID>] {
        let all = Set(graph.nodes.map(\.id))
        var dominators = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, all) })
        dominators[graph.entryID] = [graph.entryID]
        var changed = true
        while changed {
            changed = false
            for node in graph.nodes where node.id != graph.entryID {
                let predecessors = graph.incoming(to: node.id).map(\.source)
                var next = predecessors.first.map { dominators[$0, default: all] } ?? []
                for predecessor in predecessors.dropFirst() {
                    next.formIntersection(dominators[predecessor, default: all])
                }
                next.insert(node.id)
                if next != dominators[node.id] {
                    dominators[node.id] = next
                    changed = true
                }
            }
        }
        return dominators
    }

    private func computeRanks(
        graph: ControlFlowGraph,
        excluding backEdges: Set<StableID>
    ) -> [StableID: Int] {
        var ranks = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, 0) })
        let forward = graph.edges.filter { !backEdges.contains($0.id) }
        let maximumPasses = max(1, graph.nodes.count)
        for _ in 0 ..< maximumPasses {
            var changed = false
            for edge in forward {
                let candidate = ranks[edge.source, default: 0] + 1
                if candidate > ranks[edge.target, default: 0] {
                    ranks[edge.target] = candidate
                    changed = true
                }
            }
            if !changed {
                break
            }
        }
        return ranks
    }
}
