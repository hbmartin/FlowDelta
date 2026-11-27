/// One stop in a walkthrough: a connected group of changed nodes in one function.
public struct FlowWalkthroughStep: Codable, Hashable, Sendable, Identifiable {
    /// The function delta's ID and the step's first node, so a step keeps its identity across reloads.
    public let id: String
    public let functionID: StableID
    public let functionName: String
    /// The changed nodes in the step, in reading order.
    public let nodeIDs: [StableID]
    /// The nodes whose context the step changes, in ID order.
    public let affectedNodeIDs: [StableID]
    public let narration: String
}

/// Orders a revision's visible changes into steps a reviewer can follow one at a time.
public enum FlowWalkthrough {
    /// The steps for every function in `order` (triage order by default), using the nodes `policy` shows.
    public static func steps(
        for report: RevisionFlowDeltaReport,
        policy: FlowNoisePolicy,
        functionOrder order: [StableID]? = nil
    ) -> [FlowWalkthroughStep] {
        let functions = report.files.flatMap { file in
            file.entityChanges.compactMap { change in file.functionDeltas.first { $0.entityChange == change } }
        }
        let byID = Dictionary(functions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = order.map { $0.compactMap { byID[$0] } } ?? functions
        return ordered.flatMap { steps(for: FlowNoiseFilter.apply(policy, to: $0).function) }
    }

    /// The steps for one function as it is displayed: connected changed nodes, ordered by where control reaches
    /// them first.
    public static func steps(for function: FunctionFlowDelta) -> [FlowWalkthroughStep] {
        let changed = function.nodes.filter { $0.state == .added || $0.state == .removed || $0.state == .modified }
        guard !changed.isEmpty else { return [] }
        let order = readingOrder(of: function)
        let key = { (node: FlowNodeDelta) in
            (order[node.id] ?? Int.max, node.new?.sourceOrder ?? node.old?.sourceOrder ?? Int.max, node.id)
        }
        let chunks = components(of: Set(changed.map(\.id)), in: function)
            .map { chunk in changed.filter { chunk.contains($0.id) }.sorted { key($0) < key($1) } }
            .sorted { key($0[0]) < key($1[0]) }
        return chunks.map { chunk in
            let ids = Set(chunk.map(\.id))
            let affected = function.nodes.filter { node in node.causality.contains { ids.contains($0.triggerID) } }
            return FlowWalkthroughStep(
                id: "\(function.id.rawValue)#\(chunk[0].id.rawValue)",
                functionID: function.id,
                functionName: function.displayName,
                nodeIDs: chunk.map(\.id),
                affectedNodeIDs: affected.map(\.id).sorted(),
                narration: narration(for: chunk, affected: affected, triggers: ids)
            )
        }
    }

    // MARK: Narration

    static func narration(for chunk: [FlowNodeDelta], affected: [FlowNodeDelta], triggers: Set<StableID>) -> String {
        let first = chunk[0]
        let others = chunk.count - 1
        let more = others == 0 ? "" : others == 1 ? " and 1 more statement" : " and \(others) more statements"
        let rewrite = chunk.allSatisfy { $0.noise == .rewrite } ? " (equivalent rewrite)" : ""
        let action = if chunk.allSatisfy({ $0.state == .added }) {
            "Adds \(code(first.new?.label))\(more)"
        } else if chunk.allSatisfy({ $0.state == .removed }) {
            "Removes \(code(first.old?.label))\(more)"
        } else if others == 0, let old = first.old?.label, let new = first.new?.label {
            "Changes \(code(old)) to \(code(new))"
        } else {
            "Changes \(code(first.new?.label ?? first.old?.label))\(more)"
        }
        guard !affected.isEmpty else { return action + rewrite }
        let bases = Set(affected.flatMap { $0.causality.filter { triggers.contains($0.triggerID) }.map(\.basis) })
        let basis = bases.count > 1 ? "control and data" : bases.contains(.data) ? "data" : "control"
        let nodes = affected.count == 1 ? "1 node" : "\(affected.count) nodes"
        return "\(action)\(rewrite) — affects \(nodes) by \(basis)."
    }

    private static func code(_ label: String?) -> String {
        "`\((label ?? "").replacingOccurrences(of: "\n", with: " "))`"
    }

    // MARK: Graph

    /// Each delta node's position in a reverse postorder of the target graph, then of the base graph for nodes the
    /// target no longer has.
    static func readingOrder(of function: FunctionFlowDelta) -> [StableID: Int] {
        var deltaIDByNew: [StableID: StableID] = [:]
        var deltaIDByOld: [StableID: StableID] = [:]
        for node in function.nodes {
            if let new = node.new {
                deltaIDByNew[new.id] = node.id
            }
            if let old = node.old {
                deltaIDByOld[old.id] = node.id
            }
        }
        var order: [StableID: Int] = [:]
        for (graph, deltaIDs) in [(function.newGraph, deltaIDByNew), (function.oldGraph, deltaIDByOld)] {
            guard let graph else { continue }
            for graphID in reversePostorder(of: graph) {
                if let id = deltaIDs[graphID], order[id] == nil {
                    order[id] = order.count
                }
            }
        }
        return order
    }

    private static func reversePostorder(of graph: ControlFlowGraph) -> [StableID] {
        var visited: Set<StableID> = []
        var postorder: [StableID] = []
        var stack: [(id: StableID, successors: [StableID])] = []
        let successors = { (id: StableID) in graph.outgoing(from: id).map(\.target).sorted() }
        visited.insert(graph.entryID)
        stack.append((graph.entryID, successors(graph.entryID)))
        while !stack.isEmpty {
            if let next = stack[stack.count - 1].successors.first {
                stack[stack.count - 1].successors.removeFirst()
                if visited.insert(next).inserted {
                    stack.append((next, successors(next)))
                }
            } else {
                postorder.append(stack.removeLast().id)
            }
        }
        return postorder.reversed()
    }

    /// Connected components of `members` over the function's control edges, in either graph.
    private static func components(of members: Set<StableID>, in function: FunctionFlowDelta) -> [Set<StableID>] {
        var deltaIDByNew: [StableID: StableID] = [:]
        var deltaIDByOld: [StableID: StableID] = [:]
        for node in function.nodes {
            if let new = node.new {
                deltaIDByNew[new.id] = node.id
            }
            if let old = node.old {
                deltaIDByOld[old.id] = node.id
            }
        }
        var neighbors: [StableID: Set<StableID>] = [:]
        func connect(_ source: StableID?, _ target: StableID?) {
            guard let source, let target, source != target, members.contains(source),
                  members.contains(target) else { return }
            neighbors[source, default: []].insert(target)
            neighbors[target, default: []].insert(source)
        }
        for edge in function.newGraph?.edges ?? [] {
            connect(deltaIDByNew[edge.source], deltaIDByNew[edge.target])
        }
        for edge in function.oldGraph?.edges ?? [] {
            connect(deltaIDByOld[edge.source], deltaIDByOld[edge.target])
        }
        var remaining = members
        var result: [Set<StableID>] = []
        while let start = remaining.min() {
            var component: Set<StableID> = [start]
            var pending = [start]
            remaining.remove(start)
            while let next = pending.popLast() {
                for neighbor in neighbors[next, default: []] where remaining.remove(neighbor) != nil {
                    component.insert(neighbor)
                    pending.append(neighbor)
                }
            }
            result.append(component)
        }
        return result
    }
}
