import AppKit
import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaUI
import XCTest

@MainActor
final class FlowDeltaReviewM3Tests: XCTestCase {
    func testNoiseDialHidesCosmeticNodesAndOffersToShowThem() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        let recorder = StateRecorder()
        view.delegate = recorder
        try view.display(makeTangledReport())
        view.selectTriageRow(1)
        XCTAssertTrue(view.displayedFunctionName.hasPrefix("total"), view.displayedFunctionName)
        XCTAssertEqual(view.noise, .showAll)
        XCTAssertEqual(view.hiddenNoiseCount, 0)
        let hidden = try XCTUnwrap(view.identified(NSButton.self, "FlowDelta.Review.HiddenNoise"))
        XCTAssertTrue(hidden.isHidden)
        XCTAssertEqual(view.displayedNodeStates.values.count { $0 == .modified }, 1, "\(view.displayedNodeStates)")

        view.setNoise(.hideCosmetic)
        XCTAssertEqual(recorder.states.last?.noise, .hideCosmetic)
        XCTAssertEqual(recorder.causes.last, .host)
        XCTAssertEqual(view.hiddenNoiseCount, 1)
        XCTAssertFalse(hidden.isHidden)
        XCTAssertEqual(hidden.attributedTitle.string, "1 hidden — Show")
        XCTAssertFalse(view.displayedNodeStates.values.contains(.modified), "The parenthesized condition is noise")

        hidden.performClick(nil)
        XCTAssertEqual(view.noise, .showAll)
        XCTAssertEqual(recorder.causes.last, .user)

        let popUp = try XCTUnwrap(view.identified(NSPopUpButton.self, "FlowDelta.Review.Noise"))
        XCTAssertEqual(popUp.itemTitles, FlowNoisePolicy.allCases.map(\.displayName))
        popUp.selectItem(at: 1)
        XCTAssertTrue(popUp.sendAction(popUp.action, to: popUp.target))
        XCTAssertEqual(view.noise, .hideFormatting)
        XCTAssertEqual(recorder.states.last?.noise, .hideFormatting)
        XCTAssertEqual(recorder.causes.last, .user)
        view.setNoise(.hideFormatting)
        XCTAssertEqual(recorder.causes.count, recorder.states.count)
    }

    func testGroupingAddsConcernRowsAndTheTangledBannerOffersIt() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        let recorder = StateRecorder()
        view.delegate = recorder
        try view.display(makeTangledReport())
        XCTAssertTrue(view.isTangledBannerVisible)
        let message = try XCTUnwrap(view.identified(NSTextField.self, "FlowDelta.Review.TangledBanner.Message"))
        XCTAssertEqual(message.stringValue, "This revision mixes 2 separate behavioral concerns.")
        XCTAssertEqual(view.triageGroupRows, [])
        let selected = view.displayedFunctionName

        view.setGroupsByConcern(true)
        XCTAssertTrue(view.groupsByConcern)
        XCTAssertFalse(view.isTangledBannerVisible)
        XCTAssertEqual(recorder.states.last?.groupsByConcern, true)
        XCTAssertEqual(view.triageGroupRows.first, 0)
        XCTAssertEqual(view.triageGroupRows.count, 2, "Two behavioral concerns and no unchanged entities")
        XCTAssertEqual(view.displayedFunctionName, selected, "The selection survives regrouping")
        let table = try XCTUnwrap(view.identified(NSTableView.self, "FlowDelta.Review.Triage"))
        XCTAssertTrue(view.tableView(table, isGroupRow: 0))
        XCTAssertFalse(view.tableView(table, shouldSelectRow: 0))
        XCTAssertTrue(view.tableView(table, shouldSelectRow: 1))
        let heading = try XCTUnwrap(view.tableView(table, viewFor: nil, row: 0) as? NSTableCellView)
        XCTAssertEqual(heading.textField?.stringValue, "AUDIT · BEHAVIORAL")
        XCTAssertEqual(heading.accessibilityIdentifier(), "FlowDelta.Review.TriageGroup.0")
        view.selectTriageRow(0)
        XCTAssertEqual(view.displayedFunctionName, selected, "A group row is not selectable")

        let checkbox = try XCTUnwrap(view.identified(NSButton.self, "FlowDelta.Review.GroupByConcern"))
        XCTAssertEqual(checkbox.state, .on)
        checkbox.performClick(nil)
        XCTAssertFalse(view.groupsByConcern)
        XCTAssertEqual(recorder.causes.last, .user)
        XCTAssertTrue(view.isTangledBannerVisible)
        try XCTUnwrap(view.identified(NSButton.self, "FlowDelta.Review.TangledBanner.Group")).performClick(nil)
        XCTAssertTrue(view.groupsByConcern)
        XCTAssertEqual(recorder.causes.last, .user)

        try view.display(makeTangledReport().with(concerns: nil))
        XCTAssertFalse(checkbox.isEnabled, "A 0.2 report has no concerns to group by")
        XCTAssertEqual(view.triageGroupRows, [])
    }

    func testWalkthroughStepsThroughChangesAcrossFunctions() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        let recorder = StateRecorder()
        view.delegate = recorder
        try view.display(makeTangledReport())
        view.setNoise(.hideCosmetic)
        view.setPresentation(.beforeAfter)
        let bar = try XCTUnwrap(view.identified(NSView.self, "FlowDelta.Review.WalkthroughBar"))
        XCTAssertTrue(bar.isHidden)

        view.startWalkthrough()
        XCTAssertEqual(view.presentation, .delta, "A walkthrough shows the delta graph")
        XCTAssertEqual(recorder.states.last?.walkthroughStep, 0)
        let steps = view.activeWalkthroughSteps
        XCTAssertEqual(steps.count, 2, steps.map(\.narration).description)
        XCTAssertFalse(bar.isHidden)
        let label = try XCTUnwrap(view.identified(NSTextField.self, "FlowDelta.Review.Walkthrough.Step"))
        let narration = try XCTUnwrap(view.identified(NSTextField.self, "FlowDelta.Review.Walkthrough.Narration"))
        XCTAssertEqual(label.stringValue, "Step 1 of 2")
        XCTAssertEqual(narration.stringValue, steps[0].narration)
        XCTAssertTrue(view.displayedFunctionName.hasPrefix(steps[0].functionName), view.displayedFunctionName)
        XCTAssertEqual(view.selectedGraphNodeStableID, steps[0].nodeIDs.first?.rawValue)
        let emphasized = try XCTUnwrap(view.emphasizedGraphNodeStableIDs)
        XCTAssertTrue(emphasized.isSuperset(of: steps[0].nodeIDs.map(\.rawValue)))
        let previous = try XCTUnwrap(view.identified(NSButton.self, "FlowDelta.Review.Walkthrough.Previous"))
        let next = try XCTUnwrap(view.identified(NSButton.self, "FlowDelta.Review.Walkthrough.Next"))
        XCTAssertFalse(previous.isEnabled)
        XCTAssertTrue(next.isEnabled)
        attachScreenshot(of: view, named: "FlowDelta-Walkthrough-Step-1")

        next.performClick(nil)
        XCTAssertEqual(recorder.causes.last, .user)
        XCTAssertEqual(recorder.states.last?.walkthroughStep, 1)
        XCTAssertEqual(label.stringValue, "Step 2 of 2")
        XCTAssertTrue(
            view.displayedFunctionName.hasPrefix(steps[1].functionName),
            "Next continues into the next function"
        )
        XCTAssertFalse(next.isEnabled)
        view.showNextWalkthroughStep()
        XCTAssertEqual(recorder.states.last?.walkthroughStep, 1, "There is no step after the last")
        view.showPreviousWalkthroughStep()
        XCTAssertEqual(recorder.states.last?.walkthroughStep, 0)
        view.showWalkthroughStep(at: 1)
        previous.performClick(nil)
        XCTAssertEqual(recorder.states.last?.walkthroughStep, 0)

        view.setNoise(.showAll)
        XCTAssertTrue(bar.isHidden, "Changing the noise ends the walkthrough")
        XCTAssertNil(recorder.states.last?.walkthroughStep)
        view.startWalkthrough()
        XCTAssertEqual(view.activeWalkthroughSteps.count, 3, "Showing all changes adds the cosmetic step")
        try XCTUnwrap(view.identified(NSButton.self, "FlowDelta.Review.Walkthrough.Done")).performClick(nil)
        XCTAssertTrue(bar.isHidden)
        XCTAssertNil(view.emphasizedGraphNodeStableIDs)
        XCTAssertEqual(recorder.causes.last, .user)
        view.startWalkthrough()
        view.endWalkthrough()
        XCTAssertNil(recorder.states.last?.walkthroughStep)
        XCTAssertEqual(recorder.causes.last, .host)
    }

    func testChoosingAnotherFunctionOrRegroupingEndsTheWalkthrough() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        let recorder = StateRecorder()
        view.delegate = recorder
        try view.display(makeTangledReport())
        view.setNoise(.hideCosmetic)
        let table = try XCTUnwrap(view.identified(NSTableView.self, "FlowDelta.Review.Triage"))
        let bar = try XCTUnwrap(view.identified(NSView.self, "FlowDelta.Review.WalkthroughBar"))
        view.startWalkthrough()
        let steps = view.activeWalkthroughSteps
        XCTAssertEqual(steps.count, 2)
        view.showWalkthroughStep(at: 1)
        XCTAssertEqual(view.state.walkthroughStep, 1, "The walkthrough's own navigation keeps it")
        XCTAssertFalse(bar.isHidden)
        let walkedRow = table.selectedRow

        let otherRow = try XCTUnwrap((0 ..< view.triageRowCount).first { $0 != walkedRow && table.delegate?
                .tableView?(table, shouldSelectRow: $0) == true
        })
        table.selectRowIndexes([otherRow], byExtendingSelection: false)
        XCTAssertTrue(bar.isHidden, "Choosing a function outside the step ends the walkthrough")
        XCTAssertNil(view.state.walkthroughStep)
        XCTAssertNil(view.emphasizedGraphNodeStableIDs)
        XCTAssertEqual(recorder.causes.last, .user)

        view.startWalkthrough()
        view.selectTriageRow(walkedRow)
        XCTAssertTrue(bar.isHidden, "A host selection outside the step ends it too")
        XCTAssertNil(recorder.states.last?.walkthroughStep)

        view.startWalkthrough()
        view.setGroupsByConcern(true)
        XCTAssertTrue(bar.isHidden, "Regrouping changes the order, so it ends the walkthrough")
        XCTAssertNil(view.state.walkthroughStep)
        XCTAssertTrue(view.activeWalkthroughSteps.isEmpty)
    }

    func testADelegateThatEndsTheWalkthroughOnAMoveLeavesItEnded() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        let ender = WalkthroughEnder()
        view.delegate = ender
        try view.display(makeTangledReport())
        view.setNoise(.hideCosmetic)
        view.startWalkthrough()
        ender.armed = true

        try XCTUnwrap(view.identified(NSButton.self, "FlowDelta.Review.Walkthrough.Next")).performClick(nil)
        XCTAssertEqual(ender.stepsSeen, [1], "The move is reported once, after the step is on screen")
        XCTAssertTrue(try XCTUnwrap(view.identified(NSView.self, "FlowDelta.Review.WalkthroughBar")).isHidden)
        XCTAssertNil(view.state.walkthroughStep)
        XCTAssertNotEqual(
            try XCTUnwrap(view.identified(NSTextField.self, "FlowDelta.Review.Walkthrough.Step")).stringValue,
            "Step 2 of 0"
        )
    }

    func testAWalkthroughWithNothingVisibleSaysSo() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        try view.display(makeReport(files: [(
            "Tidy.swift",
            "func tidy(x: Int) -> Int {\n    if (x > 0) { return 1 }\n    return x\n}\n",
            "func tidy(x: Int) -> Int {\n    if x > 0 { return 1 }\n    return x\n}\n"
        )]))
        view.setNoise(.hideCosmetic)
        try XCTUnwrap(view.identified(NSButton.self, "FlowDelta.Review.Walkthrough")).performClick(nil)
        XCTAssertTrue(view.activeWalkthroughSteps.isEmpty)
        XCTAssertNil(view.state.walkthroughStep)
        XCTAssertEqual(
            try XCTUnwrap(view.identified(NSTextField.self, "FlowDelta.Review.Walkthrough.Step")).stringValue,
            "No steps"
        )
        XCTAssertFalse(try XCTUnwrap(view.identified(NSButton.self, "FlowDelta.Review.Walkthrough.Next")).isEnabled)
        XCTAssertFalse(view.isTangledBannerVisible)
    }

    func testReviewControlsHaveIdentifiersAndJoinTheTabOrder() throws {
        let view = FlowDeltaReviewView(frame: CGRect(x: 0, y: 0, width: 1280, height: 820))
        try view.display(makeTangledReport())
        let identifiers = Set(view.allDescendants.map { $0.accessibilityIdentifier() })
        for identifier in [
            "FlowDelta.Review.Noise", "FlowDelta.Review.GroupByConcern", "FlowDelta.Review.HiddenNoise",
            "FlowDelta.Review.Walkthrough", "FlowDelta.Review.TangledBanner", "FlowDelta.Review.TangledBanner.Group",
            "FlowDelta.Review.WalkthroughBar", "FlowDelta.Review.Walkthrough.Previous",
            "FlowDelta.Review.Walkthrough.Next", "FlowDelta.Review.Walkthrough.Done"
        ] {
            XCTAssertTrue(identifiers.contains(identifier), identifier)
        }
        let popUp = try XCTUnwrap(view.identified(NSPopUpButton.self, "FlowDelta.Review.Noise"))
        XCTAssertEqual(popUp.nextKeyView?.accessibilityIdentifier(), "FlowDelta.Review.GroupByConcern")
        XCTAssertEqual(popUp.nextKeyView?.nextKeyView?.accessibilityIdentifier(), "FlowDelta.Review.Walkthrough")
        XCTAssertEqual(
            popUp.nextKeyView?.nextKeyView?.nextKeyView?.accessibilityIdentifier(),
            "FlowDelta.Review.Triage"
        )
    }

    // MARK: Fixtures

    /// `total` gains a guard and drops redundant parentheses; `audit` changes its threshold. Nothing connects them.
    private func makeTangledReport() throws -> RevisionFlowDeltaReport {
        try makeReport(files: [
            (
                "Checkout.swift",
                "func total(items: [Int]) -> Int {\n    var sum = 0\n    for item in items { sum += item }\n"
                    + "    if (sum > 100) { return sum - 5 }\n    return sum\n}\n",
                "func total(items: [Int]) -> Int {\n    guard !items.isEmpty else { return 0 }\n    var sum = 0\n"
                    + "    for item in items { sum += item }\n    if sum > 100 { return sum - 5 }\n    return sum\n}\n"
            ),
            (
                "Audit.swift",
                "func audit(count: Int) -> Bool {\n    return count > 1\n}\n",
                "func audit(count: Int) -> Bool {\n    return count > 2\n}\n"
            )
        ])
    }

    private func makeReport(files: [(path: String, old: String, new: String)]) throws -> RevisionFlowDeltaReport {
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        return try FlowDeltaAnalyzer().analyze(RevisionComparison(base: base, target: target, files: files.map { file in
            FileComparison(
                old: SourceSnapshot(path: file.path, revision: base, language: .swift, text: file.old),
                new: SourceSnapshot(path: file.path, revision: target, language: .swift, text: file.new)
            )
        }))
    }

    private func attachScreenshot(of view: NSView, named name: String) {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(representation)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension NSView {
    var allDescendants: [NSView] {
        subviews + subviews.flatMap(\.allDescendants)
    }

    func identified<View: NSView>(_: View.Type, _ identifier: String) -> View? {
        allDescendants.first { $0.accessibilityIdentifier() == identifier } as? View
    }
}

/// Ends the walkthrough from the first user change it hears once armed, as a host might.
@MainActor
private final class WalkthroughEnder: FlowDeltaReviewViewDelegate {
    var armed = false
    private(set) var stepsSeen: [Int?] = []

    func flowDeltaReviewView(
        _ view: FlowDeltaReviewView,
        didChange state: FlowReviewState,
        cause: FlowReviewChangeCause
    ) {
        guard armed, cause == .user else { return }
        armed = false
        stepsSeen.append(state.walkthroughStep)
        view.endWalkthrough()
    }
}

@MainActor
private final class StateRecorder: FlowDeltaReviewViewDelegate {
    private(set) var states: [FlowReviewState] = []
    private(set) var causes: [FlowReviewChangeCause] = []

    func flowDeltaReviewView(_: FlowDeltaReviewView, didChange state: FlowReviewState, cause: FlowReviewChangeCause) {
        states.append(state)
        causes.append(cause)
    }
}
