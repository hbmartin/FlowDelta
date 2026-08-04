import CoreGraphics
import FlowDeltaCore
import Foundation

public struct NodeTransitionState: Sendable, Hashable {
    public let id: StableID
    public let frame: CGRect
    public let opacity: CGFloat

    public init(id: StableID, frame: CGRect, opacity: CGFloat) {
        self.id = id
        self.frame = frame
        self.opacity = opacity
    }
}

public struct StagedLayoutTransition: Sendable {
    public let oldFrames: [StableID: CGRect]
    public let newFrames: [StableID: CGRect]

    public init(oldFrames: [StableID: CGRect], newFrames: [StableID: CGRect]) {
        self.oldFrames = oldFrames
        self.newFrames = newFrames
    }

    public func states(at rawProgress: CGFloat) -> [NodeTransitionState] {
        let progress = min(1, max(0, rawProgress))
        let allIDs = Set(oldFrames.keys).union(newFrames.keys)
        return allIDs.sorted().compactMap { id in
            switch (oldFrames[id], newFrames[id]) {
            case let (old?, new?):
                let movement = min(1, max(0, (progress - 0.25) / 0.50))
                return NodeTransitionState(
                    id: id,
                    frame: interpolate(old, new, progress: smoothstep(movement)),
                    opacity: 1
                )
            case let (old?, nil):
                let opacity = 1 - min(1, progress / 0.25)
                return NodeTransitionState(id: id, frame: old, opacity: opacity)
            case let (nil, new?):
                let opacity = min(1, max(0, (progress - 0.75) / 0.25))
                return NodeTransitionState(id: id, frame: new, opacity: opacity)
            case (nil, nil):
                return nil
            }
        }
    }

    private func interpolate(_ old: CGRect, _ new: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: old.origin.x + (new.origin.x - old.origin.x) * progress,
            y: old.origin.y + (new.origin.y - old.origin.y) * progress,
            width: old.width + (new.width - old.width) * progress,
            height: old.height + (new.height - old.height) * progress
        )
    }

    private func smoothstep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }
}
