import Foundation

public struct DataFlowEdge: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let symbol: String
    public let definition: StableID
    public let use: StableID

    public init(id: StableID? = nil, symbol: String, definition: StableID, use: StableID) {
        self.id = id ?? StableID(
            namespace: "data-edge",
            components: [symbol, definition.rawValue, use.rawValue]
        )
        self.symbol = symbol
        self.definition = definition
        self.use = use
    }
}

public struct DataFlowGraph: Codable, Hashable, Sendable {
    public let entityID: StableID
    public let edges: [DataFlowEdge]

    public init(entityID: StableID, edges: [DataFlowEdge]) {
        self.entityID = entityID
        self.edges = edges.sorted {
            ($0.definition, $0.use, $0.symbol) < ($1.definition, $1.use, $1.symbol)
        }
    }
}

public struct DataFlowEdgeDelta: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let old: DataFlowEdge?
    public let new: DataFlowEdge?
    public let state: DeltaState

    public init(id: StableID, old: DataFlowEdge?, new: DataFlowEdge?, state: DeltaState) {
        self.id = id
        self.old = old
        self.new = new
        self.state = state
    }
}

public struct FunctionDataFlowDelta: Codable, Hashable, Sendable {
    public let oldGraph: DataFlowGraph?
    public let newGraph: DataFlowGraph?
    public let edges: [DataFlowEdgeDelta]

    public init(oldGraph: DataFlowGraph?, newGraph: DataFlowGraph?, edges: [DataFlowEdgeDelta]) {
        self.oldGraph = oldGraph
        self.newGraph = newGraph
        self.edges = edges.sorted { $0.id < $1.id }
    }
}
