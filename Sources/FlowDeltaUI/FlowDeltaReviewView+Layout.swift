import AppKit
import FlowDeltaCore

/// Builds the review view's header, triage sidebar, graph panes and source pane.
extension FlowDeltaReviewView {
    func configureView() {
        // The Snow Leopard chrome (gradients, pastel nodes, the source header) is drawn in fixed light
        // colors, so its system text colors must resolve for Aqua even inside a Dark Mode window. A host
        // that supplies its own appearance replaces this.
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        updateBackgroundColor()

        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        revisionLabel.translatesAutoresizingMaskIntoConstraints = false
        revisionLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        revisionLabel.textColor = .labelColor
        header.addSubview(revisionLabel)
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = NSFont.systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        header.addSubview(summaryLabel)
        let reviewControls = configureReviewControls()
        header.addSubview(reviewControls)
        let bars = configureInfoBars()
        addSubview(bars)

        mainSplit.translatesAutoresizingMaskIntoConstraints = false
        mainSplit.isVertical = true
        mainSplit.dividerStyle = .thin
        addSubview(mainSplit)

        let sidebar = configureSidebar()
        let detail = configureDetail()
        mainSplit.addArrangedSubview(sidebar)
        mainSplit.addArrangedSubview(detail)
        let sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 300)
        sidebarWidth.priority = PaneWidthPriority.triagePreferred
        let sidebarMinimum = sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        sidebarMinimum.priority = PaneWidthPriority.triageMinimum
        NSLayoutConstraint.activate([sidebarWidth, sidebarMinimum])

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),
            revisionLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            revisionLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 7),
            summaryLabel.leadingAnchor.constraint(equalTo: revisionLabel.leadingAnchor),
            summaryLabel.topAnchor.constraint(equalTo: revisionLabel.bottomAnchor, constant: 2),
            summaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: reviewControls.leadingAnchor, constant: -12),
            reviewControls.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            reviewControls.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            bars.topAnchor.constraint(equalTo: header.bottomAnchor),
            bars.leadingAnchor.constraint(equalTo: leadingAnchor),
            bars.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainSplit.topAnchor.constraint(equalTo: bars.bottomAnchor),
            mainSplit.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainSplit.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainSplit.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        assignAccessibilityIdentifiers()
        configureKeyViewLoop()
    }

    /// The noise pop-up, Group by Concern, the hidden-noise link and Walkthrough, trailing in the header.
    func configureReviewControls() -> NSView {
        noisePopUp.controlSize = .small
        noisePopUp.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        noisePopUp.addItems(withTitles: FlowNoisePolicy.allCases.map(\.displayName))
        noisePopUp.target = self
        noisePopUp.action = #selector(noisePopUpChanged(_:))
        noisePopUp.toolTip = "Choose which node changes count as noise. Equivalent rewrites are always shown."
        groupCheckbox.controlSize = .small
        groupCheckbox.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        groupCheckbox.target = self
        groupCheckbox.action = #selector(groupCheckboxChanged(_:))
        hiddenNoiseButton.isBordered = false
        hiddenNoiseButton.controlSize = .small
        hiddenNoiseButton.target = self
        hiddenNoiseButton.action = #selector(showHiddenNoise(_:))
        hiddenNoiseButton.isHidden = true
        ReviewViewComponents.configureBarButton(
            walkthroughButton,
            target: self,
            action: #selector(walkthroughButtonPressed(_:))
        )
        walkthroughButton.toolTip = "Step through this revision's changes one at a time"
        let stack = NSStackView(views: [hiddenNoiseButton, noisePopUp, groupCheckbox, walkthroughButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// The tangled-revision banner and the walkthrough bar; each collapses when hidden.
    func configureInfoBars() -> NSView {
        ReviewViewComponents.configureBarButton(
            tangledGroupButton,
            target: self,
            action: #selector(groupFromBanner(_:))
        )
        tangledBanner.setViews(leading: [], trailing: [tangledGroupButton])
        tangledBanner.isHidden = true
        for (button, action) in [
            (walkthroughPreviousButton, #selector(walkthroughPrevious(_:))),
            (walkthroughNextButton, #selector(walkthroughNext(_:))),
            (walkthroughDoneButton, #selector(walkthroughDone(_:)))
        ] {
            ReviewViewComponents.configureBarButton(button, target: self, action: action)
        }
        walkthroughPreviousButton.setAccessibilityLabel("Previous Step")
        walkthroughNextButton.setAccessibilityLabel("Next Step")
        walkthroughStepLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        walkthroughBar.setViews(
            leading: [walkthroughPreviousButton, walkthroughNextButton, walkthroughStepLabel],
            trailing: [walkthroughDoneButton]
        )
        walkthroughBar.isHidden = true
        let bars = NSStackView(views: [tangledBanner, walkthroughBar])
        bars.orientation = .vertical
        bars.spacing = 0
        bars.detachesHiddenViews = true
        bars.translatesAutoresizingMaskIntoConstraints = false
        for bar in [tangledBanner, walkthroughBar] {
            bar.widthAnchor.constraint(equalTo: bars.widthAnchor).isActive = true
        }
        let collapsed = bars.heightAnchor.constraint(equalToConstant: 0)
        collapsed.priority = .defaultLow
        collapsed.isActive = true
        return bars
    }

    func configureSidebar() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "ENTITY TRIAGE")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        title.textColor = .secondaryLabelColor
        container.addSubview(title)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        container.addSubview(scroll)

        let change = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("change"))
        change.title = "Change"
        change.width = 78
        let entity = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entity"))
        entity.title = "Entity"
        entity.width = 205
        tableView.addTableColumn(change)
        tableView.addTableColumn(entity)
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 23
        tableView.delegate = self
        tableView.dataSource = self
        tableView.style = .sourceList
        scroll.documentView = tableView

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func configureDetail() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let detailHeader = NSView()
        detailHeader.translatesAutoresizingMaskIntoConstraints = false
        detailHeader.wantsLayer = true
        detailHeader.layer?.backgroundColor = NSColor(calibratedWhite: 0.93, alpha: 1).cgColor
        container.addSubview(detailHeader)

        functionLabel.translatesAutoresizingMaskIntoConstraints = false
        functionLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        functionLabel.lineBreakMode = .byTruncatingTail
        functionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let functionWidth = functionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        functionWidth.priority = PaneWidthPriority.functionLabelMinimum
        functionWidth.isActive = true
        detailHeader.addSubview(functionLabel)

        let legend = ReviewViewComponents.makeLegend()
        legend.translatesAutoresizingMaskIntoConstraints = false
        detailHeader.addSubview(legend)

        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.selectedSegment = 0
        modeControl.segmentStyle = .texturedSquare
        modeControl.target = self
        modeControl.action = #selector(reviewModeChanged(_:))
        modeControl.setAccessibilityLabel("Flow presentation")
        detailHeader.addSubview(modeControl)

        sliceButton.translatesAutoresizingMaskIntoConstraints = false
        sliceButton.bezelStyle = .roundRect
        sliceButton.target = self
        sliceButton.action = #selector(toggleSlice(_:))
        detailHeader.addSubview(sliceButton)

        sliceDirectionControl.translatesAutoresizingMaskIntoConstraints = false
        sliceDirectionControl.selectedSegment = 0
        sliceDirectionControl.segmentStyle = .texturedSquare
        sliceDirectionControl.target = self
        sliceDirectionControl.action = #selector(sliceDirectionChanged(_:))
        sliceDirectionControl.setAccessibilityLabel("Slice direction")
        detailHeader.addSubview(sliceDirectionControl)

        detailSplit.translatesAutoresizingMaskIntoConstraints = false
        detailSplit.isVertical = true
        detailSplit.dividerStyle = .thin
        container.addSubview(detailSplit)

        configureGraphScrollView(graphScrollView, graph: graphView)
        configureGraphScrollView(comparisonGraphScrollView, graph: comparisonGraphView)
        graphView.delegate = self
        comparisonGraphView.delegate = self
        graphHostSplit.isVertical = true
        graphHostSplit.dividerStyle = .thin
        graphHostSplit.addArrangedSubview(graphScrollView)
        detailSplit.addArrangedSubview(graphHostSplit)
        detailSplit.addArrangedSubview(sourceView)
        let graphMinimum = graphHostSplit.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)
        graphMinimum.priority = PaneWidthPriority.graphMinimum
        let sourceMinimum = sourceView.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)
        sourceMinimum.priority = PaneWidthPriority.sourceMinimum
        NSLayoutConstraint.activate([graphMinimum, sourceMinimum])
        let functionLegendGap = functionLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: legend.leadingAnchor,
            constant: -10
        )
        functionLegendGap.priority = .defaultHigh
        functionLegendGap.isActive = true
        let modeSliceGap = modeControl.trailingAnchor.constraint(
            lessThanOrEqualTo: sliceButton.leadingAnchor,
            constant: -8
        )
        modeSliceGap.priority = .defaultHigh
        modeSliceGap.isActive = true

        NSLayoutConstraint.activate([
            detailHeader.topAnchor.constraint(equalTo: container.topAnchor),
            detailHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            detailHeader.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            detailHeader.heightAnchor.constraint(equalToConstant: 66),
            functionLabel.leadingAnchor.constraint(equalTo: detailHeader.leadingAnchor, constant: 10),
            functionLabel.topAnchor.constraint(equalTo: detailHeader.topAnchor, constant: 7),
            legend.trailingAnchor.constraint(equalTo: detailHeader.trailingAnchor, constant: -10),
            legend.centerYAnchor.constraint(equalTo: functionLabel.centerYAnchor),
            modeControl.leadingAnchor.constraint(equalTo: detailHeader.leadingAnchor, constant: 10),
            modeControl.bottomAnchor.constraint(equalTo: detailHeader.bottomAnchor, constant: -7),
            sliceButton.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),
            sliceButton.trailingAnchor.constraint(equalTo: sliceDirectionControl.leadingAnchor, constant: -5),
            sliceDirectionControl.trailingAnchor.constraint(equalTo: detailHeader.trailingAnchor, constant: -10),
            sliceDirectionControl.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),
            detailSplit.topAnchor.constraint(equalTo: detailHeader.bottomAnchor),
            detailSplit.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            detailSplit.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            detailSplit.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func configureGraphScrollView(_ scrollView: NSScrollView, graph: FlowGraphView) {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = graph
    }

    /// Layer colors are resolved once, so they are resolved for this view's appearance rather than the app's.
    func updateBackgroundColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}

/// The panes' widths yield to the host window. Each ranks below `windowSizeStayPut`, so a window narrower than the
/// preferred widths keeps its size instead of growing past the screen, and above `dragThatCannotResizeWindow`, so a
/// divider drag cannot squeeze a pane past them. When the window is too narrow for every preferred width, the triage
/// sidebar gives way first, down to its minimum, then the source pane, then the function name.
enum PaneWidthPriority {
    static let triageMinimum = NSLayoutConstraint.Priority(499)
    static let graphMinimum = NSLayoutConstraint.Priority(498)
    static let sourceMinimum = NSLayoutConstraint.Priority(497)
    static let triagePreferred = NSLayoutConstraint.Priority(496)
    static let functionLabelMinimum = NSLayoutConstraint.Priority(495)
}
