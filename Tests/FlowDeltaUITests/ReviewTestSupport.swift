import AppKit
import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaUI
import XCTest

/// Fixtures and key events the review view tests share.
@MainActor
extension XCTestCase {
    static func functionKey(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key)) ?? " "))
    }

    static func keyEvent(_ characters: String, code: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: code
        ) ?? NSEvent()
    }

    func makeShippingReport() throws -> RevisionFlowDeltaReport {
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
            if priority { total += 10 }
            return total
        }

        func legacyDiscount(_ total: Int) -> Int { total > 100 ? 10 : 0 }

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
            if priority { total += 15 }
            return total
        }

        func auditOrder(_ items: [Item]) {
            for item in items { audit(item) }
        }

        struct ShippingPolicy { let surcharge = 15 }
        """
        let base = RevisionIdentity("58b966582ddd632593afb6101a147740c244ec89")
        let target = RevisionIdentity("39d18d4b9960adf8bf01026a5471c98d62fa3f64")
        return try FlowDeltaAnalyzer().analyze(RevisionComparison(
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
                unifiedDiff: "@@ reference @@"
            )]
        ))
    }

    func replacingCallGraph(
        in report: RevisionFlowDeltaReport,
        with callGraph: CallGraph?
    ) -> RevisionFlowDeltaReport {
        RevisionFlowDeltaReport(
            base: report.base,
            target: report.target,
            files: report.files,
            callGraph: callGraph,
            diagnostics: report.diagnostics
        )
    }
}

extension NSView {
    func descendants<View: NSView>(of type: View.Type) -> [View] {
        subviews.compactMap { $0 as? View } + subviews.flatMap { $0.descendants(of: type) }
    }
}

@MainActor
final class ReviewStateRecorder: FlowDeltaReviewViewDelegate {
    private(set) var states: [FlowReviewState] = []
    private(set) var causes: [FlowReviewChangeCause] = []
    var extraItems: [NSMenuItem] = []

    func flowDeltaReviewView(_: FlowDeltaReviewView, menuItemsForNodeWithStableID _: String) -> [NSMenuItem] {
        extraItems
    }

    func flowDeltaReviewView(_: FlowDeltaReviewView, didChange state: FlowReviewState, cause: FlowReviewChangeCause) {
        states.append(state)
        causes.append(cause)
    }
}
