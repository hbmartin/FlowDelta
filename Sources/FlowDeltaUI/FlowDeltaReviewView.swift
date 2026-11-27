import AppKit
import FlowDeltaCore
import FlowDeltaLayout
import Foundation
import OSLog

@MainActor
@objc(FDFlowDeltaReviewView)
public final class FlowDeltaReviewView: NSView, NSTableViewDataSource, NSTableViewDelegate, FlowGraphViewDelegate {
    static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "ReviewView")
    let header = SnowLeopardHeaderView()
    let revisionLabel = NSTextField(labelWithString: "FlowDelta")
    let summaryLabel = NSTextField(labelWithString: "No comparison loaded")
    let mainSplit = NSSplitView()
    let detailSplit = NSSplitView()
    let graphHostSplit = NSSplitView()
    let tableView = NSTableView()
    let graphScrollView = NSScrollView()
    let comparisonGraphScrollView = NSScrollView()
    let graphView = FlowGraphView()
    let comparisonGraphView = FlowGraphView()
    let sourceView = FlowSourceView()
    let functionLabel = NSTextField(labelWithString: "Select a function")
    let modeControl = NSSegmentedControl(
        labels: ["Delta", "Before / After", "Calls"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    let sliceButton = NSButton(checkboxWithTitle: "Slice", target: nil, action: nil)
    let sliceDirectionControl = NSSegmentedControl(
        labels: ["Forward", "Backward"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    let layoutEngine = DominatorAnchoredLayout()
    var rows: [ReviewRow] = []
    var currentReport: RevisionFlowDeltaReport?
    var currentFunction: FunctionFlowDelta?
    var currentProjection: FunctionDeltaProjection?
    var currentLayout: GraphLayoutResult?
    var currentFile: FileFlowDelta?
    var callNodesByID: [StableID: CallGraphNode] = [:]
    /// Follows review state changes and supplies extra graph node menu items.
    public weak var delegate: (any FlowDeltaReviewViewDelegate)?
    var hostChangeDepth = 0
    var lastReportedState: FlowReviewState?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    public func display(_ report: RevisionFlowDeltaReport) {
        performHostChange { show(report) }
    }

    private func show(_ report: RevisionFlowDeltaReport) {
        currentReport = report
        revisionLabel.stringValue = "\(ReviewViewComponents.short(report.base.value)) → \(ReviewViewComponents.short(report.target.value))"
        summaryLabel.stringValue = FlowReviewSummary.text(for: report)
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
        performHostChange {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            show(row: rows[row])
        }
    }

    public func selectGraphNode(withStableID stableID: String) {
        performHostChange {
            graphView.selectNode(withStableID: stableID)
            flowGraphView(graphView, didSelectNodeWithStableID: stableID)
        }
    }

    /// Selects the forward direction and shows or hides the slice. Prefer `setSlice(_:)`.
    public func setForwardSliceEnabled(_ enabled: Bool) {
        setSliceDirection(.forward, enabled: enabled)
    }

    /// Selects the backward direction and shows or hides the slice. Prefer `setSlice(_:)`.
    public func setBackwardSliceEnabled(_ enabled: Bool) {
        setSliceDirection(.backward, enabled: enabled)
    }

    /// The presentation as an integer. Prefer `setPresentation(_:)`; out-of-range values are ignored.
    public func setReviewMode(_ mode: Int) {
        guard let presentation = FlowReviewPresentation(rawValue: mode) else { return }
        setPresentation(presentation)
    }

    private func setSliceDirection(_ direction: FlowSliceDirection, enabled: Bool) {
        performHostChange {
            sliceDirectionControl.selectedSegment = direction.rawValue
            sliceButton.state = enabled ? .on : .off
            updateSliceFocus()
        }
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
        reportStateChange(.user)
    }

    public func flowGraphView(_ view: FlowGraphView, didSelectNodeWithStableID stableID: String) {
        defer { reportStateChange(.user) }
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
