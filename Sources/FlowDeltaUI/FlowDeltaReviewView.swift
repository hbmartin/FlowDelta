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
    private let tableView = NSTableView()
    private let graphScrollView = NSScrollView()
    private let graphView = FlowGraphView()
    private let sourceView = FlowSourceView()
    private let functionLabel = NSTextField(labelWithString: "Select a function")
    private let sliceButton = NSButton(checkboxWithTitle: "Forward Slice", target: nil, action: nil)
    private let layoutEngine = DominatorAnchoredLayout()
    private var rows: [ReviewRow] = []
    private var currentProjection: FunctionDeltaProjection?
    private var currentLayout: GraphLayoutResult?
    private var currentFile: FileFlowDelta?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    public func display(_ report: RevisionFlowDeltaReport) {
        revisionLabel.stringValue = "\(Self.short(report.base.value)) → \(Self.short(report.target.value))"
        summaryLabel.stringValue = "\(report.files.count) Swift files • \(report.functionDeltas.count) function flow deltas • affected = control context"
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
        sliceButton.state = enabled ? .on : .off
        updateSliceFocus()
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
            ?? makeCell(identifier: identifier)
        let value: String
        if identifier.rawValue == "change" {
            value = rows[row].change.kind.rawValue.capitalized
            cell.textField?.textColor = Self.color(for: rows[row].change.kind)
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
        guard let currentProjection,
              let nodeDelta = currentProjection.nodeDeltas[StableID(rawValue: stableID)],
              let currentFile
        else { return }
        let usesTarget = nodeDelta.new != nil
        let snapshot = usesTarget ? currentFile.comparison.new : currentFile.comparison.old
        sourceView.display(snapshot, title: usesTarget ? "Target source" : "Base source")
        sourceView.select((nodeDelta.new ?? nodeDelta.old)?.sourceRanges.first)
        Self.logger.debug("Selected flow node \(stableID, privacy: .public) for source synchronization")
        updateSliceFocus()
    }

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

        let legend = makeLegend()
        legend.translatesAutoresizingMaskIntoConstraints = false
        detailHeader.addSubview(legend)

        sliceButton.translatesAutoresizingMaskIntoConstraints = false
        sliceButton.bezelStyle = .roundRect
        sliceButton.target = self
        sliceButton.action = #selector(toggleForwardSlice(_:))
        detailHeader.addSubview(sliceButton)

        detailSplit.translatesAutoresizingMaskIntoConstraints = false
        detailSplit.isVertical = true
        detailSplit.dividerStyle = .thin
        container.addSubview(detailSplit)

        graphScrollView.hasVerticalScroller = true
        graphScrollView.hasHorizontalScroller = true
        graphScrollView.autohidesScrollers = true
        graphScrollView.borderType = .noBorder
        graphScrollView.documentView = graphView
        graphView.delegate = self
        detailSplit.addArrangedSubview(graphScrollView)
        detailSplit.addArrangedSubview(sourceView)
        for constraint in [
            graphScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            sourceView.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ] {
            constraint.priority = .defaultHigh
            constraint.isActive = true
        }

        NSLayoutConstraint.activate([
            detailHeader.topAnchor.constraint(equalTo: container.topAnchor),
            detailHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            detailHeader.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            detailHeader.heightAnchor.constraint(equalToConstant: 42),
            functionLabel.leadingAnchor.constraint(equalTo: detailHeader.leadingAnchor, constant: 10),
            functionLabel.centerYAnchor.constraint(equalTo: detailHeader.centerYAnchor),
            functionLabel.trailingAnchor.constraint(lessThanOrEqualTo: legend.leadingAnchor, constant: -10),
            legend.centerXAnchor.constraint(equalTo: detailHeader.centerXAnchor),
            legend.centerYAnchor.constraint(equalTo: detailHeader.centerYAnchor),
            legend.trailingAnchor.constraint(lessThanOrEqualTo: sliceButton.leadingAnchor, constant: -10),
            sliceButton.trailingAnchor.constraint(equalTo: detailHeader.trailingAnchor, constant: -10),
            sliceButton.centerYAnchor.constraint(equalTo: detailHeader.centerYAnchor),
            detailSplit.topAnchor.constraint(equalTo: detailHeader.bottomAnchor),
            detailSplit.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            detailSplit.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            detailSplit.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func show(row: ReviewRow) {
        currentFile = row.file
        guard let function = row.function else {
            functionLabel.stringValue = (row.change.new ?? row.change.old)?.qualifiedName ?? "Entity"
            let placeholderID = StableID(namespace: "review-placeholder", components: [functionLabel.stringValue])
            let placeholder = FlowNode(
                id: placeholderID,
                kind: .basicBlock,
                label: "No callable flow graph",
                sourceOrder: 0
            )
            let graph = ControlFlowGraph(
                entityID: placeholderID,
                nodes: [placeholder],
                edges: [],
                entryID: placeholderID,
                exitID: placeholderID,
                errorExitID: placeholderID
            )
            let layout = layoutEngine.layout(graph: graph)
            graphView.display(graph: graph, layout: layout)
            currentProjection = nil
            currentLayout = layout
            sourceView.display(row.file.comparison.new ?? row.file.comparison.old, title: "Source")
            return
        }
        let classifications = function.classifications.map(\.reviewLabel).joined(separator: ", ")
        functionLabel.stringValue = function.displayName
            + (classifications.isEmpty ? "" : " — \(classifications)")
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
            animated: currentProjection != nil
        )
        currentProjection = projection
        currentLayout = layout
        Self.logger.debug(
            "Rendered \(function.displayName, privacy: .public) with \(projection.graph.nodes.count) projected nodes"
        )
        sourceView.display(row.file.comparison.new ?? row.file.comparison.old, title: "Target source")
        sliceButton.state = .off
        updateSliceFocus()
    }

    @objc private func toggleForwardSlice(_ sender: NSButton) {
        updateSliceFocus()
    }

    private func updateSliceFocus() {
        guard sliceButton.state == .on,
              let selected = graphView.selectedStableID,
              let currentProjection
        else {
            graphView.emphasizeNodes(withStableIDs: nil)
            return
        }
        let slice = currentProjection.forwardSlice(from: StableID(rawValue: selected))
        graphView.emphasizeNodes(withStableIDs: Set(slice.map(\.rawValue)))
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingTail
        cell.textField = field
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func makeLegend() -> NSStackView {
        let stack = NSStackView(views: [
            LegendItem(title: "Added", color: NSColor(calibratedRed: 0.42, green: 0.68, blue: 0.35, alpha: 1)),
            LegendItem(title: "Removed", color: NSColor(calibratedRed: 0.76, green: 0.32, blue: 0.27, alpha: 1)),
            LegendItem(title: "Modified", color: NSColor(calibratedRed: 0.80, green: 0.62, blue: 0.17, alpha: 1)),
            LegendItem(title: "Affected", color: NSColor(calibratedRed: 0.46, green: 0.33, blue: 0.63, alpha: 1))
        ])
        stack.orientation = .horizontal
        stack.spacing = 10
        return stack
    }

    private static func short(_ revision: String) -> String {
        String(revision.prefix(8))
    }

    private static func color(for kind: EntityChangeKind) -> NSColor {
        switch kind {
        case .added: .systemGreen
        case .removed: .systemRed
        case .modified: .systemOrange
        case .moved, .renamed: .systemPurple
        case .unchanged: .secondaryLabelColor
        }
    }
}

private struct ReviewRow {
    let file: FileFlowDelta
    let change: EntityChange
    let function: FunctionFlowDelta?
}

private extension FlowChangeClassification {
    var reviewLabel: String {
        switch self {
        case .guardInserted: "guard inserted"
        case .conditionChanged: "condition changed"
        case .earlyReturnAdded: "early return added"
        case .branchAdded: "branch added"
        case .branchRemoved: "branch removed"
        case .loopChanged: "loop changed"
        case .errorPathAdded: "error path added"
        }
    }
}

@MainActor
private final class SnowLeopardHeaderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let colors = [
            NSColor(calibratedWhite: 0.96, alpha: 1),
            NSColor(calibratedWhite: 0.79, alpha: 1)
        ]
        NSGradient(colors: colors)?.draw(in: bounds, angle: -90)
        NSColor(calibratedWhite: 0.62, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1)).fill()
    }
}

@MainActor
private final class LegendItem: NSView {
    init(title: String, color: NSColor) {
        super.init(frame: .zero)
        let swatch = NSView()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = color.cgColor
        swatch.layer?.cornerRadius = 4
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        addSubview(swatch)
        addSubview(label)
        NSLayoutConstraint.activate([
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor),
            swatch.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 8),
            swatch.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}
