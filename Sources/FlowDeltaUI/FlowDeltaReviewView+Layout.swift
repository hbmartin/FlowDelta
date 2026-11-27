import AppKit

/// Builds the review view's header, triage sidebar, graph panes and source pane.
extension FlowDeltaReviewView {
    func configureView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        revisionLabel.translatesAutoresizingMaskIntoConstraints = false
        revisionLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        revisionLabel.textColor = .labelColor
        header.addSubview(revisionLabel)
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = NSFont.systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        header.addSubview(summaryLabel)

        mainSplit.translatesAutoresizingMaskIntoConstraints = false
        mainSplit.isVertical = true
        mainSplit.dividerStyle = .thin
        addSubview(mainSplit)

        let sidebar = configureSidebar()
        let detail = configureDetail()
        mainSplit.addArrangedSubview(sidebar)
        mainSplit.addArrangedSubview(detail)
        let sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 300)
        sidebarWidth.priority = .defaultHigh
        sidebarWidth.isActive = true

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),
            revisionLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            revisionLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 7),
            summaryLabel.leadingAnchor.constraint(equalTo: revisionLabel.leadingAnchor),
            summaryLabel.topAnchor.constraint(equalTo: revisionLabel.bottomAnchor, constant: 2),
            mainSplit.topAnchor.constraint(equalTo: header.bottomAnchor),
            mainSplit.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainSplit.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainSplit.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
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
        functionWidth.priority = .defaultHigh
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
        for constraint in [
            graphHostSplit.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            sourceView.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ] {
            constraint.priority = .defaultHigh
            constraint.isActive = true
        }
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
}
