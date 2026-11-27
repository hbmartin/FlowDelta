import CoreGraphics
import FlowDeltaCore

/// A keyboard move between graph nodes.
public enum GraphNavigationMove: CaseIterable, Sendable {
    case up
    case down
    case left
    case right
    case first
    case last
}

/// Moves a keyboard selection between laid-out nodes. Frames use flipped coordinates, so a larger y is lower.
public struct GraphNavigator: Sendable {
    public let nodeFrames: [StableID: CGRect]

    public init(nodeFrames: [StableID: CGRect]) {
        self.nodeFrames = nodeFrames
    }

    public init(layout: GraphLayoutResult) {
        self.init(nodeFrames: layout.nodeFrames)
    }

    /// The nodes top to bottom, then left to right, as First and Last and a missing selection use them.
    public var readingOrder: [StableID] {
        nodeFrames.keys.sorted { lhs, rhs in
            let left = nodeFrames[lhs] ?? .zero
            let right = nodeFrames[rhs] ?? .zero
            return (left.midY, left.midX, lhs.rawValue) < (right.midY, right.midX, rhs.rawValue)
        }
    }

    /// The node a move selects. Without a selection, every move but Last starts at the first node. A move with
    /// nowhere to go keeps the current node.
    public func target(from current: StableID?, move: GraphNavigationMove) -> StableID? {
        let order = readingOrder
        guard let current, let origin = nodeFrames[current] else {
            return move == .last ? order.last : order.first
        }
        switch move {
        case .first:
            return order.first
        case .last:
            return order.last
        case .up, .down, .left, .right:
            return nearest(to: origin, excluding: current, move: move) ?? current
        }
    }

    /// The closest node in the direction of the move, preferring the nearest row (or column) and then the
    /// smallest sideways offset.
    private func nearest(to origin: CGRect, excluding current: StableID, move: GraphNavigationMove) -> StableID? {
        var best: (key: (CGFloat, CGFloat, String), id: StableID)?
        for (id, frame) in nodeFrames where id != current {
            let dx = frame.midX - origin.midX
            let dy = frame.midY - origin.midY
            let forward: CGFloat
            let sideways: CGFloat
            switch move {
            case .down: (forward, sideways) = (dy, abs(dx))
            case .up: (forward, sideways) = (-dy, abs(dx))
            case .right: (forward, sideways) = (dx, abs(dy))
            case .left: (forward, sideways) = (-dx, abs(dy))
            case .first, .last: return nil
            }
            guard forward > 0.5 else { continue }
            let key = move == .left || move == .right ? (sideways, forward, id.rawValue) : (
                forward,
                sideways,
                id.rawValue
            )
            if best.map({ key < $0.key }) ?? true {
                best = (key, id)
            }
        }
        return best?.id
    }
}
