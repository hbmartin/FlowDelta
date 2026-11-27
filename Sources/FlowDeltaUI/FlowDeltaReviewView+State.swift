import AppKit
import FlowDeltaCore
import OSLog

/// The typed host API: the review's observable state, its setters and change reporting.
public extension FlowDeltaReviewView {
    var presentation: FlowReviewPresentation {
        FlowReviewPresentation(rawValue: modeControl.selectedSegment) ?? .delta
    }

    var sliceDirection: FlowSliceDirection? {
        guard sliceButton.state == .on else { return nil }
        return FlowSliceDirection(rawValue: sliceDirectionControl.selectedSegment) ?? .forward
    }

    var state: FlowReviewState {
        FlowReviewState(
            presentation: presentation,
            slice: sliceDirection,
            selectedFunctionName: currentFunction?.displayName,
            selectedNodeStableID: graphView.selectedStableID
        )
    }

    func setPresentation(_ presentation: FlowReviewPresentation) {
        performHostChange {
            modeControl.selectedSegment = presentation.rawValue
            renderCurrentMode(animated: false)
        }
    }

    /// Shows a slice in `direction` from the selected node, or hides the slice when `direction` is nil.
    func setSlice(_ direction: FlowSliceDirection?) {
        performHostChange {
            if let direction {
                sliceDirectionControl.selectedSegment = direction.rawValue
            }
            sliceButton.state = direction == nil ? .off : .on
            updateSliceFocus()
        }
    }
}

extension FlowDeltaReviewView {
    /// Runs a host-requested change and reports it once, as `.host`, however many internal updates it causes.
    func performHostChange(_ change: () -> Void) {
        hostChangeDepth += 1
        change()
        hostChangeDepth -= 1
        reportStateChange(.host)
    }

    /// Tells the delegate about a new state. Changes inside a host change are reported when it finishes.
    func reportStateChange(_ cause: FlowReviewChangeCause) {
        guard hostChangeDepth == 0 else { return }
        let state = state
        guard state != lastReportedState else { return }
        lastReportedState = state
        Self.logger.debug(
            "Review state changed by \(cause == .user ? "user" : "host", privacy: .public): presentation \(state.presentation.rawValue), slice \(state.slice?.rawValue ?? -1)"
        )
        delegate?.flowDeltaReviewView(self, didChange: state, cause: cause)
    }
}
