import AppKit
import FlowDeltaCore
import OSLog

/// The typed host API: the review's observable state, its setters and change reporting.
public extension FlowDeltaReviewView {
    var presentation: FlowReviewPresentation {
        FlowReviewPresentation(rawValue: modeControl.selectedSegment) ?? .delta
    }

    /// The direction of the slice on screen, or nil when the review draws none.
    var sliceDirection: FlowSliceDirection? {
        guard sliceOrigin != nil else { return nil }
        return FlowSliceDirection(rawValue: sliceDirectionControl.selectedSegment) ?? .forward
    }

    var state: FlowReviewState {
        FlowReviewState(
            presentation: presentation,
            slice: sliceDirection,
            selectedFunctionName: currentFunction?.displayName,
            selectedNodeStableID: graphView.selectedStableID
                ?? (comparisonGraphIsVisible ? comparisonGraphView.selectedStableID : nil),
            noise: noisePolicy,
            groupsByConcern: groupsByConcernEnabled,
            walkthroughStep: walkthroughIndex
        )
    }

    func setPresentation(_ presentation: FlowReviewPresentation) {
        performHostChange {
            modeControl.selectedSegment = presentation.rawValue
            renderCurrentMode(animated: false)
        }
    }

    /// Shows a slice in `direction` from the selected node, or hides the slice when `direction` is nil. Only the
    /// delta graph draws slices, so other presentations keep Slice off.
    func setSlice(_ direction: FlowSliceDirection?) {
        performHostChange {
            if let direction {
                sliceDirectionControl.selectedSegment = direction.rawValue
            }
            sliceButton.state = direction != nil && presentation == .delta ? .on : .off
            updateSliceFocus()
        }
    }
}

extension FlowDeltaReviewView {
    /// Runs a host-requested change and reports it once, as `.host`, however many internal updates it causes.
    func performHostChange(_ change: () -> Void) {
        withoutReportingChanges(change)
        reportStateChange(.host)
    }

    /// Runs internal updates without reporting them, so the caller reports the finished change once.
    func withoutReportingChanges(_ change: () -> Void) {
        reportingSuspensionDepth += 1
        defer { reportingSuspensionDepth -= 1 }
        change()
    }

    /// Tells the delegate about a new state. Changes made while reporting is suspended are reported by the caller.
    func reportStateChange(_ cause: FlowReviewChangeCause) {
        guard reportingSuspensionDepth == 0 else { return }
        let state = state
        guard state != lastReportedState else { return }
        lastReportedState = state
        Self.logger.debug(
            "Review state changed by \(cause == .user ? "user" : "host", privacy: .public): presentation \(state.presentation.rawValue), slice \(state.slice?.rawValue ?? -1), noise \(state.noise.rawValue, privacy: .public), grouped \(state.groupsByConcern), step \(state.walkthroughStep ?? -1)"
        )
        delegate?.flowDeltaReviewView(self, didChange: state, cause: cause)
    }
}
