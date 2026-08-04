import AppKit
import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaGit
import FlowDeltaUI
import Foundation

@main
enum FlowDeltaReferenceMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = ReferenceAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

@MainActor
private final class ReferenceAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let reviewView = FlowDeltaReviewView()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FlowDelta — Swift Control-Flow Review"
        window.minSize = NSSize(width: 980, height: 640)
        window.center()
        reviewView.frame = window.contentView?.bounds ?? .zero
        reviewView.autoresizingMask = [.width, .height]
        window.contentView = reviewView
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window

        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count >= 3 {
            loadRepository(path: arguments[0], base: arguments[1], target: arguments[2])
        } else {
            displayDemo()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func displayDemo() {
        do {
            try reviewView.display(Self.demoReport())
        } catch {
            present(error)
        }
    }

    private func loadRepository(path: String, base: String, target: String) {
        Task { @MainActor in
            do {
                let comparison = try await GitCLIRevisionProvider().comparison(
                    repositoryURL: URL(fileURLWithPath: path, isDirectory: true),
                    base: base,
                    target: target
                )
                try reviewView.display(FlowDeltaAnalyzer().analyze(comparison))
            } catch {
                present(error)
            }
        }
    }

    private func present(_ error: any Error) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    static func demoReport() throws -> RevisionFlowDeltaReport {
        let old = """
        func shippingTotal(_ items: [Item], priority: Bool) -> Int {
            var total = 0
            for item in items {
                if item.isTaxable {
                    total += item.price + item.tax
                } else {
                    total += item.price
                }
            }
            if priority {
                total += 10
            }
            return total
        }

        func legacyDiscount(_ total: Int) -> Int {
            return total > 100 ? 10 : 0
        }

        struct ShippingPolicy { let surcharge = 10 }
        """
        let new = """
        func shippingTotal(_ items: [Item], priority: Bool) -> Int {
            guard !items.isEmpty else { return 0 }
            var total = 0
            for item in items {
                if item.requiresTax {
                    total += item.price + item.tax
                } else {
                    total += item.price
                }
            }
            if priority {
                total += 15
            }
            return total
        }

        func auditOrder(_ items: [Item]) {
            for item in items {
                audit(item)
            }
        }

        struct ShippingPolicy { let surcharge = 15 }
        """
        let base = RevisionIdentity("58b966582ddd632593afb6101a147740c244ec89")
        let target = RevisionIdentity("39d18d4b9960adf8bf01026a5471c98d62fa3f64")
        let comparison = RevisionComparison(
            base: base,
            target: target,
            files: [FileComparison(
                old: SourceSnapshot(
                    path: "Sources/Checkout/Shipping.swift",
                    revision: base,
                    language: .swift,
                    text: old
                ),
                new: SourceSnapshot(
                    path: "Sources/Checkout/Shipping.swift",
                    revision: target,
                    language: .swift,
                    text: new
                ),
                unifiedDiff: "@@ demo @@"
            )]
        )
        return try FlowDeltaAnalyzer().analyze(comparison)
    }
}
