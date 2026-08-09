import Foundation

public struct CallGraphNode: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let name: String
    public let path: String?
    public let range: SourceRange?
    public let state: DeltaState
    public let external: Bool

    public init(
        id: StableID,
        name: String,
        path: String? = nil,
        range: SourceRange? = nil,
        state: DeltaState,
        external: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.range = range
        self.state = state
        self.external = external
    }
}

public struct CallGraphEdge: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let caller: StableID
    public let callee: StableID
    public let state: DeltaState

    public init(id: StableID? = nil, caller: StableID, callee: StableID, state: DeltaState) {
        self.id = id ?? StableID(
            namespace: "call-edge",
            components: [caller.rawValue, callee.rawValue]
        )
        self.caller = caller
        self.callee = callee
        self.state = state
    }
}

public struct CallGraph: Codable, Hashable, Sendable {
    public let nodes: [CallGraphNode]
    public let edges: [CallGraphEdge]

    public init(nodes: [CallGraphNode], edges: [CallGraphEdge]) {
        self.nodes = nodes.sorted { $0.id < $1.id }
        self.edges = edges.sorted { $0.id < $1.id }
    }

    public func neighborhood(around roots: Set<StableID>, radius: Int = 1) -> CallGraph {
        precondition(radius >= 0)
        var included = roots
        var frontier = roots
        for _ in 0 ..< radius {
            var next: Set<StableID> = []
            for edge in edges where frontier.contains(edge.caller) || frontier.contains(edge.callee) {
                next.insert(edge.caller)
                next.insert(edge.callee)
            }
            next.subtract(included)
            included.formUnion(next)
            frontier = next
            if frontier.isEmpty {
                break
            }
        }
        return CallGraph(
            nodes: nodes.filter { included.contains($0.id) },
            edges: edges.filter { included.contains($0.caller) && included.contains($0.callee) }
        )
    }
}

public protocol CallGraphEnriching: Sendable {
    func enrich(_ graph: CallGraph, sourceFiles: [String]) throws -> CallGraph
}
