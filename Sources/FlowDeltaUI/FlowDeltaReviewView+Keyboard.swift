import AppKit
import FlowDeltaCore
import OSLog

/// Keyboard review: Return shows the selected node's source, Space toggles its slice, Escape clears the slice.
/// Arrows, Home and End move between nodes inside FlowGraphView.
extension FlowDeltaReviewView {
    public func flowGraphView(_ view: FlowGraphView, perform command: FlowGraphKeyCommand) -> Bool {
        Self.logger.debug("Graph key command \(command.rawValue)")
        switch command {
        case .activate:
            guard let stableID = view.selectedStableID else { return false }
            flowGraphView(view, didSelectNodeWithStableID: stableID)
            window?.makeFirstResponder(sourceView.textView)
        case .toggleSlice:
            guard view === graphView, presentation == .delta, view.selectedStableID != nil else { return false }
            sliceButton.state = sliceButton.state == .on ? .off : .on
            updateSliceFocus()
        case .cancel:
            guard sliceDirection != nil else { return false }
            sliceButton.state = .off
            updateSliceFocus()
        }
        reportStateChange(.user)
        return true
    }

    /// Stable identifiers hosts and UI tests can query; see README "Embedding".
    func assignAccessibilityIdentifiers() {
        let identified: [(NSView, String)] = [
            (self, "FlowDelta.Review"),
            (revisionLabel, "FlowDelta.Review.Revisions"),
            (summaryLabel, "FlowDelta.Review.Summary"),
            (tableView, "FlowDelta.Review.Triage"),
            (functionLabel, "FlowDelta.Review.Function"),
            (modeControl, "FlowDelta.Review.Presentation"),
            (sliceButton, "FlowDelta.Review.Slice"),
            (sliceDirectionControl, "FlowDelta.Review.SliceDirection"),
            (graphView, "FlowDelta.Review.Graph"),
            (comparisonGraphView, "FlowDelta.Review.ComparisonGraph"),
            (sourceView.textView, "FlowDelta.Review.Source")
        ]
        for (view, identifier) in identified {
            view.setAccessibilityIdentifier(identifier)
        }
        graphView.setAccessibilityLabel("Flow graph")
        comparisonGraphView.setAccessibilityLabel("Target flow graph")
    }

    /// Tab moves from the triage list to the graph, the target graph when it is shown, and the source.
    func configureKeyViewLoop() {
        tableView.nextKeyView = graphView
        graphView.nextKeyView = comparisonGraphView
        comparisonGraphView.nextKeyView = sourceView.textView
    }
}
