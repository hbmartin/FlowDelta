import AppKit
import FlowDeltaCore
import OSLog

/// The noise dial, concern grouping and walkthrough: the typed host API and the controls that drive them.
public extension FlowDeltaReviewView {
    var noise: FlowNoisePolicy {
        noisePolicy
    }

    var groupsByConcern: Bool {
        groupsByConcernEnabled
    }

    /// The walkthrough's steps for the displayed report, or empty when no walkthrough is running.
    var activeWalkthroughSteps: [FlowWalkthroughStep] {
        walkthroughIndex == nil ? [] : walkthroughSteps
    }

    /// How many node changes the noise policy shows as unchanged in the displayed report.
    var hiddenNoiseCount: Int {
        currentReport.map { FlowNoiseFilter.hiddenNodeCount(noisePolicy, in: $0) } ?? 0
    }

    var isTangledBannerVisible: Bool {
        !tangledBanner.isHidden
    }

    func setNoise(_ policy: FlowNoisePolicy) {
        performHostChange { applyNoise(policy) }
    }

    func setGroupsByConcern(_ grouped: Bool) {
        performHostChange { applyGrouping(grouped) }
    }

    /// Starts a walkthrough at its first step. A report with no visible changes has no steps.
    func startWalkthrough() {
        performHostChange { beginWalkthrough() }
    }

    func showWalkthroughStep(at index: Int) {
        performHostChange { moveWalkthrough(to: index) }
    }

    func showNextWalkthroughStep() {
        performHostChange { moveWalkthrough(to: (walkthroughIndex ?? -1) + 1) }
    }

    func showPreviousWalkthroughStep() {
        performHostChange { moveWalkthrough(to: (walkthroughIndex ?? 1) - 1) }
    }

    func endWalkthrough() {
        performHostChange { endWalkthroughSilently() }
    }
}

extension FlowDeltaReviewView {
    // MARK: Controls

    @objc func noisePopUpChanged(_ sender: NSPopUpButton) {
        guard FlowNoisePolicy.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        applyNoise(FlowNoisePolicy.allCases[sender.indexOfSelectedItem])
        reportStateChange(.user)
    }

    @objc func showHiddenNoise(_: NSButton) {
        applyNoise(.showAll)
        reportStateChange(.user)
    }

    @objc func groupCheckboxChanged(_ sender: NSButton) {
        applyGrouping(sender.state == .on)
        reportStateChange(.user)
    }

    @objc func groupFromBanner(_: NSButton) {
        applyGrouping(true)
        reportStateChange(.user)
    }

    @objc func walkthroughButtonPressed(_: NSButton) {
        beginWalkthrough()
        reportStateChange(.user)
    }

    @objc func walkthroughPrevious(_: NSButton) {
        moveWalkthrough(to: (walkthroughIndex ?? 1) - 1)
        reportStateChange(.user)
    }

    @objc func walkthroughNext(_: NSButton) {
        moveWalkthrough(to: (walkthroughIndex ?? -1) + 1)
        reportStateChange(.user)
    }

    @objc func walkthroughDone(_: NSButton) {
        endWalkthroughSilently()
        reportStateChange(.user)
    }

    // MARK: Noise and grouping

    func applyNoise(_ policy: FlowNoisePolicy) {
        guard policy != noisePolicy else { return }
        Self.logger.info("Review noise policy is now \(policy.rawValue, privacy: .public)")
        noisePolicy = policy
        endWalkthroughSilently()
        reshowSelectedRow()
        updateReviewControls()
    }

    func applyGrouping(_ grouped: Bool) {
        guard grouped != groupsByConcernEnabled else { return }
        Self.logger.info("Review triage grouping by concern is now \(grouped ? "on" : "off", privacy: .public)")
        groupsByConcernEnabled = grouped
        let selectedID = rows.indices.contains(tableView.selectedRow) ? rows[tableView.selectedRow].entity?.change
            .entityID : nil
        rebuildTriageRows()
        if let row = rows.firstIndex(where: { $0.entity?.change.entityID == selectedID && selectedID != nil }) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
        updateReviewControls()
    }

    /// Rebuilds the triage list from the displayed report, with group rows when grouping is on.
    func rebuildTriageRows() {
        guard let currentReport else {
            rows = []
            tableView.reloadData()
            return
        }
        let sections = FlowTriage.sections(for: currentReport, groupsByConcern: groupsByConcernEnabled)
        rows = sections.flatMap { section -> [TriageRow] in
            let heading = section.title.map { [TriageRow.group(title: $0, kind: section.kind)] } ?? []
            return heading + section.entries.map(TriageRow.entity)
        }
        tableView.reloadData()
    }

    private func reshowSelectedRow() {
        let row = tableView.selectedRow
        guard rows.indices.contains(row), let entry = rows[row].entity else { return }
        show(row: entry)
    }

    /// Brings the header controls, the hidden-noise link and the tangled banner up to date.
    func updateReviewControls() {
        noisePopUp.selectItem(at: FlowNoisePolicy.allCases.firstIndex(of: noisePolicy) ?? 0)
        groupCheckbox.state = groupsByConcernEnabled ? .on : .off
        groupCheckbox.isEnabled = currentReport?.concerns != nil
        let hidden = hiddenNoiseCount
        hiddenNoiseButton.isHidden = hidden == 0
        hiddenNoiseButton.attributedTitle = NSAttributedString(
            string: "\(hidden) hidden — Show",
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        hiddenNoiseButton.setAccessibilityLabel("\(hidden) noise changes hidden. Show all changes.")
        let behavioral = (currentReport?.concerns ?? []).count { $0.kind == .behavioral }
        tangledBanner.isHidden = groupsByConcernEnabled || currentReport?.isTangled != true
        tangledBanner.messageLabel.stringValue = "This revision mixes \(behavioral) separate behavioral concerns."
        walkthroughButton.isEnabled = currentReport != nil
    }

    // MARK: Walkthrough

    /// The nodes the walkthrough step on screen emphasizes, or nil when none is.
    var currentWalkthroughEmphasis: Set<String>? {
        guard let walkthroughIndex, walkthroughSteps.indices.contains(walkthroughIndex) else { return nil }
        let step = walkthroughSteps[walkthroughIndex]
        guard step.functionID == currentFunction?.id else { return nil }
        return Set((step.nodeIDs + step.affectedNodeIDs).map(\.rawValue))
    }

    func beginWalkthrough() {
        guard let currentReport else { return }
        let order = FlowTriage.functionOrder(of: FlowTriage.sections(
            for: currentReport,
            groupsByConcern: groupsByConcernEnabled
        ))
        walkthroughSteps = FlowWalkthrough.steps(for: currentReport, policy: noisePolicy, functionOrder: order)
        let stepCount = walkthroughSteps.count
        Self.logger.info("Starting a walkthrough of \(stepCount) steps")
        guard !walkthroughSteps.isEmpty else {
            walkthroughIndex = nil
            walkthroughBar.isHidden = false
            walkthroughStepLabel.stringValue = "No steps"
            walkthroughBar.messageLabel.stringValue = "No changes are visible with the current noise setting."
            updateWalkthroughButtons()
            return
        }
        moveWalkthrough(to: 0)
    }

    func moveWalkthrough(to index: Int) {
        guard walkthroughSteps.indices.contains(index) else { return }
        walkthroughIndex = index
        let step = walkthroughSteps[index]
        if presentation != .delta {
            modeControl.selectedSegment = FlowReviewPresentation.delta.rawValue
        }
        sliceButton.state = .off
        if currentFunction?.id != step.functionID,
           let row = rows.firstIndex(where: { $0.entity?.function?.id == step.functionID })
        {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            rows[row].entity.map(show(row:))
        } else {
            renderCurrentMode(animated: false)
        }
        if let first = step.nodeIDs.first?.rawValue {
            graphView.selectNode(withStableID: first)
            flowGraphView(graphView, didSelectNodeWithStableID: first)
            graphView.scrollNode(withStableIDToVisible: first)
        }
        graphView.emphasizeNodes(withStableIDs: currentWalkthroughEmphasis)
        walkthroughBar.isHidden = false
        let position = "Step \(index + 1) of \(walkthroughSteps.count)"
        walkthroughStepLabel.stringValue = position
        walkthroughBar.messageLabel.stringValue = step.narration
        walkthroughBar.messageLabel.toolTip = step.narration
        updateWalkthroughButtons()
        let stepCount = walkthroughSteps.count
        Self.logger.info("Showing walkthrough step \(index + 1) of \(stepCount)")
        NSAccessibility.post(
            element: walkthroughBar,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(position). \(step.functionName). \(step.narration)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    /// Ends any walkthrough without reporting a state change.
    func endWalkthroughSilently() {
        let wasRunning = walkthroughIndex != nil || !walkthroughBar.isHidden
        walkthroughIndex = nil
        walkthroughSteps = []
        walkthroughBar.isHidden = true
        if wasRunning {
            Self.logger.info("Ended the walkthrough")
            graphView.emphasizeNodes(withStableIDs: nil)
            updateSliceFocus()
        }
    }

    private func updateWalkthroughButtons() {
        walkthroughPreviousButton.isEnabled = (walkthroughIndex ?? 0) > 0
        walkthroughNextButton.isEnabled = walkthroughIndex.map { $0 + 1 < walkthroughSteps.count } ?? false
    }
}
