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

    public init(
        id: StableID,
        old: FlowNode?,
        new: FlowNode?,
        state: DeltaState,
        confidence: MatchConfidence? = nil,
        causality: [CausalityLink] = []
    ) {
        self.id = id
        self.old = old
        self.new = new
        self.state = state
        self.confidence = confidence
        self.causality = causality
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

    public init(
        id: StableID,
        entityChange: EntityChange,
        editScript: EditScript?,
        oldGraph: ControlFlowGraph?,
        newGraph: ControlFlowGraph?,
        nodes: [FlowNodeDelta],
        edges: [FlowEdgeDelta]
    ) {
        self.id = id
        self.entityChange = entityChange
        self.editScript = editScript
        self.oldGraph = oldGraph
        self.newGraph = newGraph
        self.nodes = nodes.sorted { $0.id < $1.id }
        self.edges = edges.sorted { $0.id < $1.id }
    }

    public func forwardSlice(from nodeID: StableID) -> Set<StableID> {
        let availableEdges = edges.compactMap { $0.new ?? $0.old }
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
}
