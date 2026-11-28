import AppKit
import FlowDeltaCore
import FlowDeltaUI
import XCTest

/// The review lays out inside the width its host gives it. Its panes' preferred widths add up to more than a small
/// display leaves a host's content, and a width constraint that outranks the window's size would widen the window past
/// the screen's edge, taking the walkthrough's Done button and the source pane out of reach.
@MainActor
final class FlowDeltaReviewLayoutTests: XCTestCase {
    /// A 1024-point display, less a host's sidebar.
    private static let narrowWidth: CGFloat = 860

    func testANarrowHostWindowKeepsItsWidthAndEveryControlStaysInside() throws {
        let (window, host, view) = makeHostedReview(width: Self.narrowWidth)
        try view.display(makeShippingReport())
        view.startWalkthrough()
        window.layoutIfNeeded()

        XCTAssertEqual(window.contentLayoutRect.width, Self.narrowWidth, "The review never widens its window")
        XCTAssertEqual(view.frame.width, Self.narrowWidth)
        let visible = NSRect(x: 0, y: 0, width: Self.narrowWidth, height: host.bounds.height)
        for identifier in [
            "FlowDelta.Review.Noise",
            "FlowDelta.Review.GroupByConcern",
            "FlowDelta.Review.Walkthrough",
            "FlowDelta.Review.Walkthrough.Next",
            "FlowDelta.Review.Walkthrough.Done",
            "FlowDelta.Review.Presentation",
            "FlowDelta.Review.SliceDirection"
        ] {
            let control = try XCTUnwrap(view.descendant(identifiedAs: identifier), identifier)
            let frame = control.convert(control.bounds, to: host)
            XCTAssertFalse(frame.isEmpty, "\(identifier) has no size")
            XCTAssertTrue(visible.contains(frame), "\(identifier) at \(frame) is outside \(visible)")
        }
        let triage = try XCTUnwrap(view.descendant(identifiedAs: "FlowDelta.Review.Triage")?.enclosingScrollView)
        let source = try XCTUnwrap(view.descendant(identifiedAs: "FlowDelta.Review.Source")?.enclosingScrollView)
        XCTAssertGreaterThanOrEqual(triage.frame.width, 180, "Triage keeps room for its rows")
        XCTAssertGreaterThanOrEqual(source.frame.width, 240, "The source pane shares the width instead of vanishing")
    }

    func testAWideHostKeepsThePanesPreferredWidths() throws {
        let (window, _, view) = makeHostedReview(width: 1280)
        try view.display(makeShippingReport())
        window.layoutIfNeeded()

        let triage = try XCTUnwrap(view.descendant(identifiedAs: "FlowDelta.Review.Triage")?.enclosingScrollView)
        let source = try XCTUnwrap(view.descendant(identifiedAs: "FlowDelta.Review.Source")?.enclosingScrollView)
        XCTAssertEqual(triage.frame.width, 300, accuracy: 1)
        XCTAssertGreaterThanOrEqual(source.frame.width, 360)
    }

    /// Hosts the review the way an app does: pinned by constraints inside a window's content view.
    private func makeHostedReview(width: CGFloat) -> (NSWindow, NSView, FlowDeltaReviewView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        window.contentView = host
        let view = FlowDeltaReviewView(frame: host.bounds)
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        addTeardownBlock { window.close() }
        return (window, host, view)
    }
}

private extension NSView {
    func descendant(identifiedAs identifier: String) -> NSView? {
        for subview in subviews {
            if subview.accessibilityIdentifier() == identifier {
                return subview
            }
            if let match = subview.descendant(identifiedAs: identifier) {
                return match
            }
        }
        return nil
    }
}
