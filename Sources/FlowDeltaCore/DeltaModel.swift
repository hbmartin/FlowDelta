import Foundation

public enum DeltaState: String, Codable, CaseIterable, Sendable {
    case added
    case removed
    case retained
    case modified
    case affected
}

public enum AffectedBasis: String, Codable, CaseIterable, Sendable {
    case control
    case data
}

public enum FlowChangeClassification: String, Codable, CaseIterable, Sendable {
    case guardInserted
    case conditionChanged
    case earlyReturnAdded
    case branchAdded
    case branchRemoved
    case loopChanged
    case errorPathAdded
}

public struct CausalityLink: Codable, Hashable, Sendable {
    public let triggerID: StableID
    public let affectedID: StableID
    public let basis: AffectedBasis
    public let explanation: String

    public init(triggerID: StableID, affectedID: StableID, basis: AffectedBasis, explanation: String) {
        self.triggerID = triggerID
        self.affectedID = affectedID
        self.basis = basis
        self.explanation = explanation
    }
}

public struct FlowNodeDelta: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let old: FlowNode?
    public let new: FlowNode?
    public let state: DeltaState
    public let confidence: MatchConfidence?
    public let causality: [CausalityLink]
    /// Why a modified node's change may not matter, or nil for a real change. Absent in 0.2 reports.
    public let noise: FlowNoiseLevel?

    public init(
        id: StableID,
        old: FlowNode?,
        new: FlowNode?,
        state: DeltaState,
        confidence: MatchConfidence? = nil,
        causality: [CausalityLink] = [],
        noise: FlowNoiseLevel? = nil
    ) {
        self.id = id
        self.old = old
        self.new = new
        self.state = state
        self.confidence = confidence
        self.causality = causality
        self.noise = noise
    }

    /// The same node with a different state and causality, as a noise filter shows it.
    public func with(state: DeltaState, causality: [CausalityLink]) -> FlowNodeDelta {
        FlowNodeDelta(
            id: id,
            old: old,
            new: new,
            state: state,
            confidence: confidence,
            causality: causality,
            noise: noise
        )
    }
}

public struct FlowEdgeDelta: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let old: FlowEdge?
    public let new: FlowEdge?
    public let state: DeltaState

    public init(id: StableID, old: FlowEdge?, new: FlowEdge?, state: DeltaState) {
        self.id = id
        self.old = old
        self.new = new
        self.state = state
    }
}

public struct FunctionFlowDelta: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let entityChange: EntityChange
    public let editScript: EditScript?
    public let oldGraph: ControlFlowGraph?
    public let newGraph: ControlFlowGraph?
    public let nodes: [FlowNodeDelta]
    public let edges: [FlowEdgeDelta]
    public let dataFlow: FunctionDataFlowDelta?
    public let classifications: [FlowChangeClassification]

    public init(
        id: StableID,
        entityChange: EntityChange,
        editScript: EditScript?,
        oldGraph: ControlFlowGraph?,
        newGraph: ControlFlowGraph?,
        nodes: [FlowNodeDelta],
        edges: [FlowEdgeDelta],
        dataFlow: FunctionDataFlowDelta? = nil,
        classifications: [FlowChangeClassification] = []
    ) {
        self.id = id
        self.entityChange = entityChange
        self.editScript = editScript
        self.oldGraph = oldGraph
        self.newGraph = newGraph
        self.nodes = nodes.sorted { $0.id < $1.id }
        self.edges = edges.sorted { $0.id < $1.id }
        self.dataFlow = dataFlow
        self.classifications = Array(Set(classifications)).sorted { $0.rawValue < $1.rawValue }
    }

    public func forwardSlice(from nodeID: StableID) -> Set<StableID> {
        let availableEdges = projectedDependencies()
        var result: Set<StableID> = [nodeID]
        var pending = [nodeID]
        while let current = pending.popLast() {
            for next in availableEdges where next.source == current {
                if result.insert(next.target).inserted {
                    pending.append(next.target)
                }
            }
        }
        return result
    }

    public func backwardSlice(from nodeID: StableID) -> Set<StableID> {
        let availableEdges = projectedDependencies()
        var result: Set<StableID> = [nodeID]
        var pending = [nodeID]
        while let current = pending.popLast() {
            for previous in availableEdges where previous.target == current {
                if result.insert(previous.source).inserted {
                    pending.append(previous.source)
                }
            }
        }
        return result
    }

    private func projectedDependencies() -> [(source: StableID, target: StableID)] {
        if nodes.isEmpty {
            return edges.compactMap { delta in
                guard let edge = delta.new ?? delta.old else { return nil }
                return (edge.source, edge.target)
            }
        }
        let oldToDelta = Dictionary(uniqueKeysWithValues: nodes.compactMap { node in
            node.old.map { ($0.id, node.id) }
        })
        let newToDelta = Dictionary(uniqueKeysWithValues: nodes.compactMap { node in
            node.new.map { ($0.id, node.id) }
        })
        var dependencies: [(source: StableID, target: StableID)] = edges.compactMap { delta in
            guard let edge = delta.new ?? delta.old else { return nil }
            let mapping = delta.new == nil ? oldToDelta : newToDelta
            guard let source = mapping[edge.source], let target = mapping[edge.target] else { return nil }
            return (source, target)
        }
        dependencies += (dataFlow?.edges ?? []).compactMap { delta in
            guard let edge = delta.new ?? delta.old else { return nil }
            let mapping = delta.new == nil ? oldToDelta : newToDelta
            guard let source = mapping[edge.definition], let target = mapping[edge.use] else { return nil }
            return (source, target)
        }
        return dependencies
    }
}
