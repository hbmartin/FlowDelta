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
            (sourceView.textView, "FlowDelta.Review.Source"),
            (noisePopUp, "FlowDelta.Review.Noise"),
            (groupCheckbox, "FlowDelta.Review.GroupByConcern"),
            (hiddenNoiseButton, "FlowDelta.Review.HiddenNoise"),
            (walkthroughButton, "FlowDelta.Review.Walkthrough"),
            (tangledBanner, "FlowDelta.Review.TangledBanner"),
            (tangledBanner.messageLabel, "FlowDelta.Review.TangledBanner.Message"),
            (tangledGroupButton, "FlowDelta.Review.TangledBanner.Group"),
            (walkthroughBar, "FlowDelta.Review.WalkthroughBar"),
            (walkthroughPreviousButton, "FlowDelta.Review.Walkthrough.Previous"),
            (walkthroughNextButton, "FlowDelta.Review.Walkthrough.Next"),
            (walkthroughStepLabel, "FlowDelta.Review.Walkthrough.Step"),
            (walkthroughBar.messageLabel, "FlowDelta.Review.Walkthrough.Narration"),
            (walkthroughDoneButton, "FlowDelta.Review.Walkthrough.Done")
        ]
        for (view, identifier) in identified {
            view.setAccessibilityIdentifier(identifier)
        }
        noisePopUp.setAccessibilityLabel("Noise")
        tangledBanner.setAccessibilityRole(.group)
        walkthroughBar.setAccessibilityRole(.group)
        walkthroughBar.setAccessibilityLabel("Walkthrough")
        graphView.setAccessibilityLabel("Flow graph")
        comparisonGraphView.setAccessibilityLabel("Target flow graph")
    }

    /// Tab moves from the header controls to the triage list, the graph, the target graph when it is shown, and
    /// the source.
    func configureKeyViewLoop() {
        noisePopUp.nextKeyView = groupCheckbox
        groupCheckbox.nextKeyView = walkthroughButton
        walkthroughButton.nextKeyView = tableView
        tableView.nextKeyView = graphView
        graphView.nextKeyView = comparisonGraphIsVisible ? comparisonGraphView : sourceView.textView
        comparisonGraphView.nextKeyView = comparisonGraphIsVisible ? sourceView.textView : nil
    }
}
