import Foundation

public enum FlowNodeKind: String, Codable, CaseIterable, Sendable {
    case entry
    case exit
    case errorExit
    case basicBlock
    case condition
    case switchCase
    case deferBlock
    case catchBlock
}

public struct FlowNode: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let kind: FlowNodeKind
    public let label: String
    public let sourceRanges: [SourceRange]
    public let syntaxIDs: [StableID]
    public let sourceOrder: Int

    public init(
        id: StableID,
        kind: FlowNodeKind,
        label: String,
        sourceRanges: [SourceRange] = [],
        syntaxIDs: [StableID] = [],
        sourceOrder: Int
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.sourceRanges = sourceRanges
        self.syntaxIDs = syntaxIDs
        self.sourceOrder = sourceOrder
    }

    public var isSynthetic: Bool {
        kind == .entry || kind == .exit || kind == .errorExit
    }
}

public enum FlowEdgeKind: String, Codable, CaseIterable, Sendable {
    case `fallthrough`
    case conditionTrue
    case conditionFalse
    case switchCase
    case loopBack
    case breakFlow
    case continueFlow
    case returnFlow
    case throwFlow
    case deferredFlow
    case catchFlow
}

public struct FlowEdge: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let source: StableID
    public let target: StableID
    public let kind: FlowEdgeKind
    public let label: String?

    public init(
        id: StableID? = nil,
        source: StableID,
        target: StableID,
        kind: FlowEdgeKind,
        label: String? = nil
    ) {
        self.id = id ?? StableID(
            namespace: "edge",
            components: [source.rawValue, target.rawValue, kind.rawValue, label ?? ""]
        )
        self.source = source
        self.target = target
        self.kind = kind
        self.label = label
    }
}

public struct ControlFlowGraph: Codable, Hashable, Sendable {
    public let entityID: StableID
    public let nodes: [FlowNode]
    public let edges: [FlowEdge]
    public let entryID: StableID
    public let exitID: StableID
    public let errorExitID: StableID

    public init(
        entityID: StableID,
        nodes: [FlowNode],
        edges: [FlowEdge],
        entryID: StableID,
        exitID: StableID,
        errorExitID: StableID
    ) {
        self.entityID = entityID
        self.nodes = nodes.sorted { ($0.sourceOrder, $0.id) < ($1.sourceOrder, $1.id) }
        self.edges = edges.sorted { ($0.source, $0.target, $0.kind.rawValue) < ($1.source, $1.target, $1.kind.rawValue) }
        self.entryID = entryID
        self.exitID = exitID
        self.errorExitID = errorExitID
    }

    public func node(id: StableID) -> FlowNode? {
        nodes.first { $0.id == id }
    }

    public func outgoing(from id: StableID) -> [FlowEdge] {
        edges.filter { $0.source == id }
    }

    public func incoming(to id: StableID) -> [FlowEdge] {
        edges.filter { $0.target == id }
    }
}
