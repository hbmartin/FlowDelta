import AppKit
import FlowDeltaCore

/// Lets a host follow a review and add its own commands to graph node menus.
@MainActor
public protocol FlowDeltaReviewViewDelegate: AnyObject {
    /// Called once per change to `FlowDeltaReviewView.state`, after the view has rendered it.
    func flowDeltaReviewView(
        _ view: FlowDeltaReviewView,
        didChange state: FlowReviewState,
        cause: FlowReviewChangeCause
    )

    /// Items appended, after a separator, to the context menu of the graph node with `stableID`.
    func flowDeltaReviewView(_ view: FlowDeltaReviewView, menuItemsForNodeWithStableID stableID: String) -> [NSMenuItem]
}

public extension FlowDeltaReviewViewDelegate {
    func flowDeltaReviewView(_: FlowDeltaReviewView, menuItemsForNodeWithStableID _: String) -> [NSMenuItem] {
        []
    }
}
