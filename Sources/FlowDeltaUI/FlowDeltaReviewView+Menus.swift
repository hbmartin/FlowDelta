import AppKit
import FlowDeltaCore
import OSLog

/// Graph node context menus. FlowDeltaCore's FlowNodeMenu decides the commands; this builds and performs them.
extension FlowDeltaReviewView {
    /// The context menu for a node of the main graph, as a secondary click would show it.
    public func contextMenu(forNodeWithStableID stableID: String) -> NSMenu? {
        graphView.menuForNode(withStableID: stableID)
    }

    public func flowGraphView(_ view: FlowGraphView, menuForNodeWithStableID stableID: String) -> NSMenu? {
        let id = StableID(rawValue: stableID)
        let callNode = callNodesByID[id]
        let target = NodeMenuTarget(stableID: stableID, graph: view)
        let location = callNode.flatMap(callLocation(of:)) ?? flowLocation(of: id, in: view)
        let context = FlowNodeMenuContext(
            presentation: presentation,
            isCallNode: callNode != nil,
            hasSourceLocation: location != nil,
            isSliceActive: sliceDirection != nil,
            hasReviewableFunction: callNode.flatMap { reviewRow(forCallNode: $0.id) } != nil
        )
        let menu = NSMenu(title: "Flow Node")
        menu.autoenablesItems = false
        for command in FlowNodeMenu.commands(for: context) {
            guard let command else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(
                title: Self.title(of: command),
                action: #selector(performNodeCommand(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = FlowNodeCommand.allCases.firstIndex(of: command) ?? 0
            item.representedObject = target
            item.identifier = NSUserInterfaceItemIdentifier("FlowDelta.Review.NodeMenu.\(command.rawValue)")
            menu.addItem(item)
        }
        let extra = delegate?.flowDeltaReviewView(self, menuItemsForNodeWithStableID: stableID) ?? []
        if !extra.isEmpty {
            menu.addItem(.separator())
            for item in extra {
                // A host may hand back the same items for every menu; an item can only be in one menu at a time.
                menu.addItem(item.menu == nil ? item : (item.copy() as? NSMenuItem) ?? NSMenuItem())
            }
        }
        Self.logger
            .debug("Built a context menu with \(menu.numberOfItems) items for node \(stableID, privacy: .public)")
        return menu
    }

    @objc func performNodeCommand(_ sender: NSMenuItem) {
        guard FlowNodeCommand.allCases.indices.contains(sender.tag),
              let target = sender.representedObject as? NodeMenuTarget
        else { return }
        let command = FlowNodeCommand.allCases[sender.tag]
        let id = StableID(rawValue: target.stableID)
        let graph = target.graph ?? graphView
        Self.logger
            .info(
                "Performing node command \(command.rawValue, privacy: .public) on \(target.stableID, privacy: .public)"
            )
        switch command {
        case .reviewFunction:
            guard let row = reviewRow(forCallNode: id) else { return }
            modeControl.selectedSegment = FlowReviewPresentation.delta.rawValue
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            show(row: rows[row])
        case .showSource:
            graph.selectNode(withStableID: target.stableID)
            flowGraphView(graph, didSelectNodeWithStableID: target.stableID)
            window?.makeFirstResponder(sourceView.textView)
        case .forwardSlice, .backwardSlice:
            graph.selectNode(withStableID: target.stableID)
            flowGraphView(graph, didSelectNodeWithStableID: target.stableID)
            sliceDirectionControl.selectedSegment = command == .forwardSlice
                ? FlowSliceDirection.forward.rawValue
                : FlowSliceDirection.backward.rawValue
            sliceButton.state = .on
            updateSliceFocus()
        case .clearSlice:
            sliceButton.state = .off
            updateSliceFocus()
        case .copyLabel:
            copy(callNodesByID[id]?.name ?? flowNode(id, in: graph)?.label)
        case .copyLocation:
            copy(callNodesByID[id].flatMap(callLocation(of:)) ?? flowLocation(of: id, in: graph))
        }
        reportStateChange(.user)
    }

    private static func title(of command: FlowNodeCommand) -> String {
        switch command {
        case .reviewFunction: "Review Function"
        case .showSource: "Show Source"
        case .forwardSlice: "Forward Slice from Here"
        case .backwardSlice: "Backward Slice from Here"
        case .clearSlice: "Clear Slice"
        case .copyLabel: "Copy Label"
        case .copyLocation: "Copy Location"
        }
    }

    private func copy(_ text: String?) {
        guard let text else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// The triage row of the function a call node stands for.
    private func reviewRow(forCallNode id: StableID) -> Int? {
        rows.firstIndex { row in
            row.function.map { CallGraphNode.stableID(for: $0.entityChange) } == id
        }
    }

    private func callLocation(of node: CallGraphNode) -> String? {
        guard let path = node.path, let range = node.range else { return nil }
        return FlowNodeMenu.location(path: path, range: range)
    }

    /// The flow node as the given graph draws it: the base side in the before graph, otherwise the target side.
    private func flowNode(_ id: StableID, in graph: FlowGraphView) -> FlowNode? {
        guard let projection = currentProjection else { return nil }
        let delta = projection.nodeDeltas[id]
            ?? projection.nodeDeltas.values.first { $0.old?.id == id || $0.new?.id == id }
        guard let delta else { return nil }
        let usesBase = graph === graphView && presentation == .beforeAfter
        return usesBase ? (delta.old ?? delta.new) : (delta.new ?? delta.old)
    }

    private func flowLocation(of id: StableID, in graph: FlowGraphView) -> String? {
        guard let file = currentFile, let range = flowNode(id, in: graph)?.sourceRanges.first else { return nil }
        return FlowNodeMenu.location(path: file.path, range: range)
    }
}

/// Which node, in which graph, a menu item acts on.
private final class NodeMenuTarget: NSObject {
    let stableID: String
    weak var graph: FlowGraphView?

    init(stableID: String, graph: FlowGraphView) {
        self.stableID = stableID
        self.graph = graph
    }
}
