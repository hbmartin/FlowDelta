import AppKit
import FlowDeltaCore
import FlowDeltaLayout
import Foundation
import OSLog

/// Shows the selected triage row in the current review mode and keeps the slice, graphs and source in step.
extension FlowDeltaReviewView {
    func show(row: ReviewRow) {
        currentFile = row.file
        currentFunction = row.function.map { FlowNoiseFilter.apply(noisePolicy, to: $0).function }
        guard let function = currentFunction else {
            functionLabel.stringValue = (row.change.new ?? row.change.old)?.qualifiedName ?? "Entity"
            displayPlaceholder("No callable flow graph")
            currentProjection = nil
            sourceView.display(row.file.comparison.new ?? row.file.comparison.old, title: "Source")
            return
        }
        let classifications = function.classifications.map(\.reviewLabel).joined(separator: ", ")
        functionLabel.stringValue = function.displayName
            + (classifications.isEmpty ? "" : " — \(classifications)")
        renderCurrentMode(animated: currentProjection != nil && !ReviewViewComponents.prefersReducedMotion)
        sourceView.display(row.file.comparison.new ?? row.file.comparison.old, title: "Target source")
        sliceButton.state = .off
        updateSliceFocus()
    }

    @objc func reviewModeChanged(_ sender: NSSegmentedControl) {
        renderCurrentMode(animated: false)
        reportStateChange(.user)
    }

    @objc func toggleSlice(_ sender: NSButton) {
        updateSliceFocus()
        reportStateChange(.user)
    }

    @objc func sliceDirectionChanged(_ sender: NSSegmentedControl) {
        updateSliceFocus()
        reportStateChange(.user)
    }

    func updateSliceFocus() {
        guard modeControl.selectedSegment == 0,
              sliceButton.state == .on,
              let selected = graphView.selectedStableID,
              let currentProjection
        else {
            graphView.emphasizeNodes(withStableIDs: currentWalkthroughEmphasis)
            comparisonGraphView.emphasizeNodes(withStableIDs: nil)
            return
        }
        let id = StableID(rawValue: selected)
        let slice = sliceDirectionControl.selectedSegment == 1
            ? currentProjection.backwardSlice(from: id)
            : currentProjection.forwardSlice(from: id)
        graphView.emphasizeNodes(withStableIDs: Set(slice.map(\.rawValue)))
    }

    func renderCurrentMode(animated: Bool) {
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

    func restoreCurrentFunctionSource() {
        guard let currentFile else { return }
        let snapshot = currentFile.comparison.new ?? currentFile.comparison.old
        let title = currentFile.comparison.new == nil ? "Base source" : "Target source"
        sourceView.display(snapshot, title: title)
    }

    func renderDelta(_ function: FunctionFlowDelta, animated: Bool) {
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

    func renderJuxtaposed(_ function: FunctionFlowDelta) {
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

    func renderCallGraph(for function: FunctionFlowDelta) {
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

    func project(_ callGraph: CallGraph) -> (
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

    func display(
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

    func displayPlaceholder(_ message: String) {
        setComparisonGraphVisible(false)
        displayPlaceholder(message, in: graphView)
        currentLayout = nil
    }

    func displayPlaceholder(_ message: String, in view: FlowGraphView) {
        display(placeholderGraph(message), in: view)
    }

    func placeholderGraph(_ message: String) -> ControlFlowGraph {
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

    func setComparisonGraphVisible(_ visible: Bool) {
        if visible, comparisonGraphScrollView.superview == nil {
            graphHostSplit.addArrangedSubview(comparisonGraphScrollView)
        } else if !visible, comparisonGraphScrollView.superview === graphHostSplit {
            comparisonGraphScrollView.removeFromSuperview()
        }
    }

    func showSource(for callNode: CallGraphNode) {
        guard let path = callNode.path,
              let file = currentReport?.files.first(where: { $0.path == path })
        else { return }
        let snapshot = file.comparison.new ?? file.comparison.old
        sourceView.display(snapshot, title: "Call source")
        sourceView.select(callNode.range)
    }
}
