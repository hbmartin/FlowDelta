import FlowDeltaCore
import Foundation

struct FunctionDeltaProjection {
    let graph: ControlFlowGraph
    let states: [StableID: DeltaState]
    let edgeStates: [StableID: DeltaState]
    let nodeDeltas: [StableID: FlowNodeDelta]

    init(_ delta: FunctionFlowDelta) {
        var oldToDelta: [StableID: StableID] = [:]
        var newToDelta: [StableID: StableID] = [:]
        var projectedNodes: [FlowNode] = []
        var states: [StableID: DeltaState] = [:]
        var nodeDeltas: [StableID: FlowNodeDelta] = [:]
        for nodeDelta in delta.nodes {
            if let old = nodeDelta.old {
                oldToDelta[old.id] = nodeDelta.id
            }
            if let new = nodeDelta.new {
                newToDelta[new.id] = nodeDelta.id
            }
            guard let node = nodeDelta.new ?? nodeDelta.old else { continue }
            let suffix = nodeDelta.state == .affected ? "\nAffected • control context" : ""
            projectedNodes.append(FlowNode(
                id: nodeDelta.id,
                kind: node.kind,
                label: node.label + suffix,
                sourceRanges: node.sourceRanges,
                syntaxIDs: node.syntaxIDs,
                sourceOrder: node.sourceOrder
            ))
            states[nodeDelta.id] = nodeDelta.state
            nodeDeltas[nodeDelta.id] = nodeDelta
        }

        var projectedEdges: [FlowEdge] = []
        var edgeStates: [StableID: DeltaState] = [:]
        for edgeDelta in delta.edges {
            guard let edge = edgeDelta.new ?? edgeDelta.old else { continue }
            let mapping = edgeDelta.new == nil ? oldToDelta : newToDelta
            guard let source = mapping[edge.source], let target = mapping[edge.target] else { continue }
            projectedEdges.append(FlowEdge(
                id: edgeDelta.id,
                source: source,
                target: target,
                kind: edge.kind,
                label: edge.label
            ))
            edgeStates[edgeDelta.id] = edgeDelta.state
        }

        let entry = Self.projectedSpecialID(
            new: delta.newGraph?.entryID,
            old: delta.oldGraph?.entryID,
            newMapping: newToDelta,
            oldMapping: oldToDelta,
            nodes: projectedNodes
        )
        let exit = Self.projectedSpecialID(
            new: delta.newGraph?.exitID,
            old: delta.oldGraph?.exitID,
            newMapping: newToDelta,
            oldMapping: oldToDelta,
            nodes: projectedNodes
        )
        let errorExit = Self.projectedSpecialID(
            new: delta.newGraph?.errorExitID,
            old: delta.oldGraph?.errorExitID,
            newMapping: newToDelta,
            oldMapping: oldToDelta,
            nodes: projectedNodes
        )
        graph = ControlFlowGraph(
            entityID: delta.id,
            nodes: projectedNodes,
            edges: projectedEdges,
            entryID: entry,
            exitID: exit,
            errorExitID: errorExit
        )
        self.states = states
        self.edgeStates = edgeStates
        self.nodeDeltas = nodeDeltas
    }

    func forwardSlice(from id: StableID) -> Set<StableID> {
        var result: Set<StableID> = [id]
        var pending = [id]
        while let current = pending.popLast() {
            for edge in graph.outgoing(from: current) where result.insert(edge.target).inserted {
                pending.append(edge.target)
            }
        }
        return result
    }

    private static func projectedSpecialID(
        new: StableID?,
        old: StableID?,
        newMapping: [StableID: StableID],
        oldMapping: [StableID: StableID],
        nodes: [FlowNode]
    ) -> StableID {
        if let new, let id = newMapping[new] {
            return id
        }
        if let old, let id = oldMapping[old] {
            return id
        }
        return nodes.first?.id ?? StableID(namespace: "empty-flow", components: ["node"])
    }
}
