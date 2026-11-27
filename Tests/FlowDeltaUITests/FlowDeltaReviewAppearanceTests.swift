import AppKit
import FlowDeltaUI
import XCTest

/// The review view's Snow Leopard chrome is drawn in fixed light colors, so it must stay legible inside a
/// Dark Mode host unless the host chooses an appearance itself.
@MainActor
final class FlowDeltaReviewAppearanceTests: XCTestCase {
    func testReviewViewKeepsItsLightChromeLegibleUnlessTheHostChoosesAnAppearance() {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        XCTAssertEqual(view.appearance?.name, .aqua, "The chrome is drawn in fixed light colors")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        XCTAssertEqual(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        XCTAssertEqual(
            view.layer?.backgroundColor,
            Self.windowBackground(in: .aqua),
            "Layer colors follow the view, not the app"
        )

        view.appearance = NSAppearance(named: .darkAqua)
        XCTAssertEqual(
            view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
            .darkAqua,
            "A host may still choose"
        )
        XCTAssertEqual(view.layer?.backgroundColor, Self.windowBackground(in: .darkAqua))
        window.close()
    }

    private static func windowBackground(in name: NSAppearance.Name) -> CGColor? {
        var color: CGColor?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            color = NSColor.windowBackgroundColor.cgColor
        }
        return color
    }
}
