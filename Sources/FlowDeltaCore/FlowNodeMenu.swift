/// A command in a graph node's context menu.
public enum FlowNodeCommand: String, CaseIterable, Sendable {
    /// Calls mode: switch to the delta of the function this call node stands for.
    case reviewFunction
    case showSource
    case forwardSlice
    case backwardSlice
    case clearSlice
    case copyLabel
    case copyLocation
}

/// What the context menu of one graph node depends on.
public struct FlowNodeMenuContext: Hashable, Sendable {
    public var presentation: FlowReviewPresentation
    /// The node is a call-graph node rather than a control-flow node.
    public var isCallNode: Bool
    public var hasSourceLocation: Bool
    public var isSliceActive: Bool
    /// A call node whose function has a delta in this report.
    public var hasReviewableFunction: Bool

    public init(
        presentation: FlowReviewPresentation,
        isCallNode: Bool,
        hasSourceLocation: Bool,
        isSliceActive: Bool,
        hasReviewableFunction: Bool = false
    ) {
        self.presentation = presentation
        self.isCallNode = isCallNode
        self.hasSourceLocation = hasSourceLocation
        self.isSliceActive = isSliceActive
        self.hasReviewableFunction = hasReviewableFunction
    }
}

/// Decides which commands a graph node's context menu offers, in order.
public enum FlowNodeMenu {
    /// The commands in menu order; `nil` marks a separator between groups. Empty groups are left out.
    public static func commands(for context: FlowNodeMenuContext) -> [FlowNodeCommand?] {
        var groups: [[FlowNodeCommand]] = []
        if context.isCallNode {
            groups.append((context.hasReviewableFunction ? [.reviewFunction] : [])
                + (context.hasSourceLocation ? [.showSource] : []))
        } else {
            groups.append(context.hasSourceLocation ? [.showSource] : [])
            // Slices follow control and data causality, which only the delta presentation draws.
            if context.presentation == .delta {
                groups.append([.forwardSlice, .backwardSlice] + (context.isSliceActive ? [.clearSlice] : []))
            }
        }
        groups.append([.copyLabel] + (context.hasSourceLocation ? [.copyLocation] : []))
        return groups.filter { !$0.isEmpty }.enumerated().flatMap { index, group in
            (index == 0 ? [] : [nil]) + group.map(Optional.some)
        }
    }

    /// "path:line", one-based, as Copy Location puts it on the pasteboard.
    public static func location(path: String, range: SourceRange) -> String {
        "\(path):\(range.start.line + 1)"
    }
}

public extension CallGraphNode {
    /// The stable ID of the call-graph node for an entity change, shared by the analyzer and the review view.
    static func stableID(for change: EntityChange) -> StableID {
        StableID(
            namespace: "call-node",
            components: [
                change.old?.path ?? "",
                change.new?.path ?? "",
                change.old?.qualifiedName ?? "",
                change.new?.qualifiedName ?? ""
            ]
        )
    }
}
