import AppKit
import FlowDeltaCore
import FlowDeltaLayout
import Foundation
import OSLog

@MainActor
@objc(FDFlowDeltaReviewView)
public final class FlowDeltaReviewView: NSView, NSTableViewDataSource, NSTableViewDelegate, FlowGraphViewDelegate {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "ReviewView")
    private let header = SnowLeopardHeaderView()
    private let revisionLabel = NSTextField(labelWithString: "FlowDelta")
    private let summaryLabel = NSTextField(labelWithString: "No comparison loaded")
    private let mainSplit = NSSplitView()
    private let detailSplit = NSSplitView()
    private let graphHostSplit = NSSplitView()
    private let tableView = NSTableView()
    private let graphScrollView = NSScrollView()
    private let comparisonGraphScrollView = NSScrollView()
    private let graphView = FlowGraphView()
    private let comparisonGraphView = FlowGraphView()
    private let sourceView = FlowSourceView()
    private let functionLabel = NSTextField(labelWithString: "Select a function")
    private let modeControl = NSSegmentedControl(
        labels: ["Delta", "Before / After", "Calls"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let sliceButton = NSButton(checkboxWithTitle: "Slice", target: nil, action: nil)
    private let sliceDirectionControl = NSSegmentedControl(
        labels: ["Forward", "Backward"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let layoutEngine = DominatorAnchoredLayout()
    private var rows: [ReviewRow] = []
    private var currentReport: RevisionFlowDeltaReport?
    private var currentFunction: FunctionFlowDelta?
    private var currentProjection: FunctionDeltaProjection?
    private var currentLayout: GraphLayoutResult?
    private var currentFile: FileFlowDelta?
    private var callNodesByID: [StableID: CallGraphNode] = [:]

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    public func display(_ report: RevisionFlowDeltaReport) {
        currentReport = report
        revisionLabel.stringValue = "\(ReviewViewComponents.short(report.base.value)) → \(ReviewViewComponents.short(report.target.value))"
        let languages = Set(report.files.map(\.comparison.language.displayName)).sorted().joined(separator: ", ")
        summaryLabel.stringValue = "\(report.files.count) files (\(languages)) • \(report.functionDeltas.count) function deltas • affected = control + data context"
        rows = report.files.flatMap { file in
            file.entityChanges.map { change in
                ReviewRow(
                    file: file,
                    change: change,
                    function: file.functionDeltas.first { $0.entityChange == change }
                )
            }
        }
        let rowCount = rows.count
        Self.logger.notice(
            "Displaying revision review with \(rowCount) triage rows and \(report.functionDeltas.count) function deltas"
        )
        tableView.reloadData()
        if let row = rows.firstIndex(where: { $0.function != nil }) ?? rows.indices.first {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            show(row: rows[row])
        }
    }

    public var triageRowCount: Int {
        rows.count
    }

    public var displayedFunctionName: String {
        functionLabel.stringValue
    }

    public var currentGraphNodeStableIDs: [String] {
        currentProjection?.graph.nodes.map(\.id.rawValue) ?? []
    }

    public var sourceBackedNodeStableIDs: [String] {
        currentProjection?.nodeDeltas.values
            .filter { ($0.new ?? $0.old)?.sourceRanges.isEmpty == false }
            .map(\.id.rawValue)
            .sorted() ?? []
    }

    public var selectedGraphNodeStableID: String? {
        graphView.selectedStableID
    }

    public var emphasizedGraphNodeStableIDs: Set<String>? {
        graphView.emphasizedStableIDs
    }

    public var reviewMode: Int {
        modeControl.selectedSegment
    }

    public var comparisonGraphNodeCount: Int {
        comparisonGraphView.renderedNodeCount
    }

    public var renderedGraphNodeCount: Int {
        graphView.renderedNodeCount
    }

    public var renderedGraphNodeStableIDs: [String] {
        graphView.renderedStableIDs
    }

    public var comparisonGraphIsVisible: Bool {
        comparisonGraphScrollView.superview === graphHostSplit
    }

    public var nonCallableTriageRows: [Int] {
        rows.indices.filter { rows[$0].function == nil }
    }

    public func selectTriageRow(_ row: Int) {
        guard rows.indices.contains(row) else { return }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        show(row: rows[row])
    }

    public func selectGraphNode(withStableID stableID: String) {
        graphView.selectNode(withStableID: stableID)
        flowGraphView(graphView, didSelectNodeWithStableID: stableID)
    }

    public func setForwardSliceEnabled(_ enabled: Bool) {
        sliceDirectionControl.selectedSegment = 0
        sliceButton.state = enabled ? .on : .off
        updateSliceFocus()
    }

    public func setBackwardSliceEnabled(_ enabled: Bool) {
        sliceDirectionControl.selectedSegment = 1
        sliceButton.state = enabled ? .on : .off
        updateSliceFocus()
    }

    public func setReviewMode(_ mode: Int) {
        guard (0 ... 2).contains(mode) else { return }
        modeControl.selectedSegment = mode
        renderCurrentMode(animated: false)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    public func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard rows.indices.contains(row), let tableColumn else { return nil }
        let identifier = tableColumn.identifier
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? ReviewViewComponents.makeCell(identifier: identifier)
        let value: String
        if identifier.rawValue == "change" {
            value = rows[row].change.kind.rawValue.capitalized
            cell.textField?.textColor = ReviewViewComponents.color(for: rows[row].change.kind)
            cell.textField?.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        } else {
            let entity = rows[row].change.new ?? rows[row].change.old
            value = entity?.qualifiedName ?? "<unknown>"
            cell.textField?.textColor = .labelColor
            cell.textField?.font = NSFont.systemFont(ofSize: 11)
        }
        cell.textField?.stringValue = value
        cell.textField?.toolTip = value
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard rows.indices.contains(row) else { return }
        show(row: rows[row])
    }

    public func flowGraphView(_ view: FlowGraphView, didSelectNodeWithStableID stableID: String) {
        let id = StableID(rawValue: stableID)
        if let callNode = callNodesByID[id] {
            showSource(for: callNode)
            return
        }
        guard let currentProjection, let currentFile else { return }
        let nodeDelta = currentProjection.nodeDeltas[id]
            ?? currentProjection.nodeDeltas.values.first { $0.old?.id == id || $0.new?.id == id }
        guard let nodeDelta else { return }
        let usesTarget = view === comparisonGraphView ||
            (view === graphView && modeControl.selectedSegment != 1 && nodeDelta.new != nil)
        let snapshot = usesTarget ? currentFile.comparison.new : currentFile.comparison.old
        sourceView.display(snapshot, title: usesTarget ? "Target source" : "Base source")
        sourceView.select((usesTarget ? nodeDelta.new : nodeDelta.old)?.sourceRanges.first
            ?? (nodeDelta.new ?? nodeDelta.old)?.sourceRanges.first)
        Self.logger.debug("Selected flow node \(stableID, privacy: .public) for source synchronization")
        updateSliceFocus()
    }
}

private extension FlowDeltaReviewView {
    private func configureView() {
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

    private func configureSidebar() -> NSView {
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

    private func configureDetail() -> NSView {
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

    private func show(row: ReviewRow) {
        currentFile = row.file
        currentFunction = row.function
        guard let function = row.function else {
            functionLabel.stringValue = (row.change.new ?? row.change.old)?.qualifiedName ?? "Entity"
            displayPlaceholder("No callable flow graph")
            currentProjection = nil
            sourceView.display(row.file.comparison.new ?? row.file.comparison.old, title: "Source")
            return
        }
        let classifications = function.classifications.map(\.reviewLabel).joined(separator: ", ")
        functionLabel.stringValue = function.displayName
            + (classifications.isEmpty ? "" : " — \(classifications)")
        renderCurrentMode(animated: currentProjection != nil)
        sourceView.display(row.file.comparison.new ?? row.file.comparison.old, title: "Target source")
        sliceButton.state = .off
        updateSliceFocus()
    }

    @objc private func reviewModeChanged(_ sender: NSSegmentedControl) {
        renderCurrentMode(animated: false)
    }

    @objc private func toggleSlice(_ sender: NSButton) {
        updateSliceFocus()
    }

    @objc private func sliceDirectionChanged(_ sender: NSSegmentedControl) {
        updateSliceFocus()
    }

    private func updateSliceFocus() {
        guard modeControl.selectedSegment == 0,
              sliceButton.state == .on,
              let selected = graphView.selectedStableID,
              let currentProjection
        else {
            graphView.emphasizeNodes(withStableIDs: nil)
            comparisonGraphView.emphasizeNodes(withStableIDs: nil)
            return
        }
        let id = StableID(rawValue: selected)
        let slice = sliceDirectionControl.selectedSegment == 1
            ? currentProjection.backwardSlice(from: id)
            : currentProjection.forwardSlice(from: id)
        graphView.emphasizeNodes(withStableIDs: Set(slice.map(\.rawValue)))
    }

    private func renderCurrentMode(animated: Bool) {
        guard let function = currentFunction else { return }
        callNodesByID = [:]
        sliceButton.isEnabled = modeControl.selectedSegment == 0
        sliceDirectionControl.isEnabled = modeControl.selectedSegment == 0
        if modeControl.selectedSegment != 0 {
            sliceButton.state = .off
        }
        graphView.emphasizeNodes(withStableIDs: nil)
        comparisonGraphView.emphasizeNodes(withStableIDs: nil)
        switch modeControl.selectedSegment {
        case 1:
            renderJuxtaposed(function)
        case 2:
            renderCallGraph(for: function)
        default:
            renderDelta(function, animated: animated)
        }
        restoreCurrentFunctionSource()
        updateSliceFocus()
    }

    private func restoreCurrentFunctionSource() {
        guard let currentFile else { return }
        let snapshot = currentFile.comparison.new ?? currentFile.comparison.old
        let title = currentFile.comparison.new == nil ? "Base source" : "Target source"
        sourceView.display(snapshot, title: title)
    }

    private func renderDelta(_ function: FunctionFlowDelta, animated: Bool) {
        setComparisonGraphVisible(false)
        let projection = FunctionDeltaProjection(function)
        let anchors = currentLayout.map { layout in
            Dictionary(uniqueKeysWithValues: layout.nodeFrames.map { (
                $0.key,
                CGPoint(x: $0.value.midX, y: $0.value.midY)
            ) })
        } ?? [:]
        let layout = layoutEngine.layout(graph: projection.graph, anchors: anchors)
        graphView.selectNode(withStableID: nil)
        graphView.display(
            graph: projection.graph,
            layout: layout,
            nodeStates: projection.states,
            edgeStates: projection.edgeStates,
            animated: animated
        )
        currentProjection = projection
        currentLayout = layout
        Self.logger.debug(
            "Rendered \(function.displayName, privacy: .public) delta with \(projection.graph.nodes.count) projected nodes"
        )
    }

    private func renderJuxtaposed(_ function: FunctionFlowDelta) {
        setComparisonGraphVisible(true)
        currentProjection = FunctionDeltaProjection(function)
        let oldStates = Dictionary(uniqueKeysWithValues: function.nodes.compactMap { delta in
            delta.old.map { ($0.id, delta.state) }
        })
        let newStates = Dictionary(uniqueKeysWithValues: function.nodes.compactMap { delta in
            delta.new.map { ($0.id, delta.state) }
        })
        if let old = function.oldGraph {
            display(old, in: graphView, states: oldStates)
        } else {
            displayPlaceholder("Added function", in: graphView)
        }
        if let new = function.newGraph {
            display(new, in: comparisonGraphView, states: newStates)
        } else {
            displayPlaceholder("Removed function", in: comparisonGraphView)
        }
        currentLayout = nil
        Self.logger.debug("Rendered juxtaposed graphs for \(function.displayName, privacy: .public)")
    }

    private func renderCallGraph(for function: FunctionFlowDelta) {
        setComparisonGraphVisible(false)
        currentProjection = FunctionDeltaProjection(function)
        guard let callGraph = currentReport?.callGraph else {
            displayPlaceholder("No call graph available")
            return
        }
        let roots = Set(callGraph.nodes.compactMap { node in
            node.path == function.path && node.name == function.displayName ? node.id : nil
        })
        let neighborhood = callGraph.neighborhood(around: roots, radius: 1)
        let projection = project(neighborhood)
        callNodesByID = Dictionary(uniqueKeysWithValues: neighborhood.nodes.map { ($0.id, $0) })
        display(projection.graph, in: graphView, states: projection.states, edgeStates: projection.edgeStates)
        currentLayout = nil
        Self.logger.debug(
            "Rendered call neighborhood for \(function.displayName, privacy: .public): \(neighborhood.nodes.count) nodes"
        )
    }

    private func project(_ callGraph: CallGraph) -> (
        graph: ControlFlowGraph,
        states: [StableID: DeltaState],
        edgeStates: [StableID: DeltaState]
    ) {
        guard !callGraph.nodes.isEmpty else {
            let graph = placeholderGraph("No calls in the selected neighborhood")
            return (graph, [:], [:])
        }
        let nodes = callGraph.nodes.enumerated().map { index, node in
            FlowNode(
                id: node.id,
                kind: .basicBlock,
                label: node.external ? "External • \(node.name)" : node.name,
                sourceRanges: node.range.map { [$0] } ?? [],
                sourceOrder: index
            )
        }
        let edges = callGraph.edges.map { edge in
            FlowEdge(id: edge.id, source: edge.caller, target: edge.callee, kind: .fallthrough, label: "calls")
        }
        let first = nodes[0].id
        return (
            ControlFlowGraph(
                entityID: StableID(namespace: "call-neighborhood", components: nodes.map(\.id.rawValue)),
                nodes: nodes,
                edges: edges,
                entryID: first,
                exitID: first,
                errorExitID: first
            ),
            Dictionary(uniqueKeysWithValues: callGraph.nodes.map { ($0.id, $0.state) }),
            Dictionary(uniqueKeysWithValues: callGraph.edges.map { ($0.id, $0.state) })
        )
    }

    private func display(
        _ graph: ControlFlowGraph,
        in view: FlowGraphView,
        states: [StableID: DeltaState] = [:],
        edgeStates: [StableID: DeltaState] = [:]
    ) {
        view.selectNode(withStableID: nil)
        view.display(
            graph: graph,
            layout: layoutEngine.layout(graph: graph),
            nodeStates: states,
            edgeStates: edgeStates
        )
    }

    private func displayPlaceholder(_ message: String) {
        setComparisonGraphVisible(false)
        displayPlaceholder(message, in: graphView)
        currentLayout = nil
    }

    private func displayPlaceholder(_ message: String, in view: FlowGraphView) {
        display(placeholderGraph(message), in: view)
    }

    private func placeholderGraph(_ message: String) -> ControlFlowGraph {
        let id = StableID(namespace: "review-placeholder", components: [message])
        let node = FlowNode(id: id, kind: .basicBlock, label: message, sourceOrder: 0)
        return ControlFlowGraph(
            entityID: id,
            nodes: [node],
            edges: [],
            entryID: id,
            exitID: id,
            errorExitID: id
        )
    }

    private func configureGraphScrollView(_ scrollView: NSScrollView, graph: FlowGraphView) {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = graph
    }

    private func setComparisonGraphVisible(_ visible: Bool) {
        if visible, comparisonGraphScrollView.superview == nil {
            graphHostSplit.addArrangedSubview(comparisonGraphScrollView)
        } else if !visible, comparisonGraphScrollView.superview === graphHostSplit {
            comparisonGraphScrollView.removeFromSuperview()
        }
    }

    private func showSource(for callNode: CallGraphNode) {
        guard let path = callNode.path,
              let file = currentReport?.files.first(where: { $0.path == path })
        else { return }
        let snapshot = file.comparison.new ?? file.comparison.old
        sourceView.display(snapshot, title: "Call source")
        sourceView.select(callNode.range)
    }
}
