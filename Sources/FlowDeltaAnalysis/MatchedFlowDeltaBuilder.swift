import FlowDeltaCore
import Foundation
import OSLog

public struct MatchedFlowDeltaBuilder: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "GraphDelta")

    public init() {}

    public func build(
        entityChange: EntityChange,
        editScript: EditScript?,
        oldGraph: ControlFlowGraph?,
        newGraph: ControlFlowGraph?
    ) -> FunctionFlowDelta {
        let pairs = nodePairs(oldGraph: oldGraph, newGraph: newGraph, editScript: editScript)
        let nodeDeltas = buildNodeDeltas(
            pairs: pairs,
            oldGraph: oldGraph,
            newGraph: newGraph
        )
        let edgeDeltas = buildEdgeDeltas(
            pairs: pairs,
            oldGraph: oldGraph,
            newGraph: newGraph
        )
        let delta = FunctionFlowDelta(
            id: StableID(
                namespace: "function-delta",
                components: [
                    entityChange.old?.path ?? "",
                    entityChange.new?.path ?? "",
                    entityChange.old?.qualifiedName ?? "",
                    entityChange.new?.qualifiedName ?? ""
                ]
            ),
            entityChange: entityChange,
            editScript: editScript,
            oldGraph: oldGraph,
            newGraph: newGraph,
            nodes: nodeDeltas,
            edges: edgeDeltas,
            classifications: classifications(nodes: nodeDeltas, edges: edgeDeltas)
        )
        Self.logger.debug(
            "Built delta for \(delta.displayName, privacy: .public): \(delta.nodes.count) nodes, \(delta.edges.count) edges"
        )
        return delta
    }

    private func nodePairs(
        oldGraph: ControlFlowGraph?,
        newGraph: ControlFlowGraph?,
        editScript: EditScript?
    ) -> [NodePair] {
        guard let oldGraph, let newGraph else { return [] }
        let oldByID = Dictionary(uniqueKeysWithValues: oldGraph.nodes.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: newGraph.nodes.map { ($0.id, $0) })
        var oldToNew: [StableID: StableID] = [:]
        var usedNew: Set<StableID> = []

        func install(_ oldID: StableID, _ newID: StableID) {
            guard oldToNew[oldID] == nil, usedNew.insert(newID).inserted else { return }
            oldToNew[oldID] = newID
        }

        for (oldID, newID) in [
            (oldGraph.entryID, newGraph.entryID),
            (oldGraph.exitID, newGraph.exitID),
            (oldGraph.errorExitID, newGraph.errorExitID)
        ] {
            install(oldID, newID)
        }
        for old in oldGraph.nodes where newByID[old.id] != nil {
            install(old.id, old.id)
        }

        let syntaxMap = Dictionary(uniqueKeysWithValues: (editScript?.mappings ?? []).map { ($0.oldID, $0) })
        var candidates: [(FlowNode, FlowNode, Int, Double)] = []
        for old in oldGraph.nodes where oldToNew[old.id] == nil {
            let projected = old.syntaxIDs.compactMap { syntaxMap[$0] }
            let projectedIDs = Set(projected.map(\.newID))
            for new in newGraph.nodes where !usedNew.contains(new.id) && old.kind == new.kind {
                let overlap = new.syntaxIDs.count { projectedIDs.contains($0) }
                guard overlap > 0 else { continue }
                let score = projected
                    .filter { new.syntaxIDs.contains($0.newID) }
                    .map(\.confidence.score)
                    .max() ?? 0.5
                candidates.append((old, new, overlap, score))
            }
        }
        candidates.sort {
            if $0.2 != $1.2 {
                return $0.2 > $1.2
            }
            if $0.3 != $1.3 {
                return $0.3 > $1.3
            }
            return ($0.0.sourceOrder, $0.1.sourceOrder, $0.0.id, $0.1.id)
                < ($1.0.sourceOrder, $1.1.sourceOrder, $1.0.id, $1.1.id)
        }
        var pairConfidence: [StableID: MatchConfidence] = [:]
        for (old, new, _, score) in candidates where oldToNew[old.id] == nil && !usedNew.contains(new.id) {
            install(old.id, new.id)
            pairConfidence[old.id] = MatchConfidence(tier: .gumTree, score: score)
        }

        let unmatchedOld = oldGraph.nodes.filter { oldToNew[$0.id] == nil }
        let unmatchedNew = newGraph.nodes.filter { !usedNew.contains($0.id) }
        for old in unmatchedOld {
            let matches = unmatchedNew.filter {
                !usedNew.contains($0.id) && $0.kind == old.kind && $0.label == old.label
            }
            guard matches.count == 1, let new = matches.first else { continue }
            install(old.id, new.id)
            pairConfidence[old.id] = MatchConfidence(tier: .fuzzyTokens, score: 0.8)
        }

        return oldToNew.compactMap { oldID, newID in
            guard let old = oldByID[oldID], let new = newByID[newID] else { return nil }
            let confidence = pairConfidence[oldID]
                ?? MatchConfidence(tier: .exactName, score: oldID == newID ? 1 : 0.95)
            return NodePair(old: old, new: new, confidence: confidence)
        }.sorted { ($0.old.sourceOrder, $0.new.sourceOrder) < ($1.old.sourceOrder, $1.new.sourceOrder) }
    }

    private func buildNodeDeltas(
        pairs: [NodePair],
        oldGraph: ControlFlowGraph?,
        newGraph: ControlFlowGraph?
    ) -> [FlowNodeDelta] {
        let oldPaired = Set(pairs.map(\.old.id))
        let newPaired = Set(pairs.map(\.new.id))
        var drafts: [NodeDraft] = pairs.map { pair in
            NodeDraft(
                id: deltaNodeID(old: pair.old.id, new: pair.new.id),
                old: pair.old,
                new: pair.new,
                state: pair.old.kind == pair.new.kind && pair.old.label == pair.new.label ? .retained : .modified,
                confidence: pair.confidence
            )
        }
        drafts.append(contentsOf: (oldGraph?.nodes ?? []).filter { !oldPaired.contains($0.id) }.map {
            NodeDraft(id: deltaNodeID(old: $0.id, new: nil), old: $0, new: nil, state: .removed, confidence: nil)
        })
        drafts.append(contentsOf: (newGraph?.nodes ?? []).filter { !newPaired.contains($0.id) }.map {
            NodeDraft(id: deltaNodeID(old: nil, new: $0.id), old: nil, new: $0, state: .added, confidence: nil)
        })

        let pairedByOld = Dictionary(uniqueKeysWithValues: pairs.map { ($0.old.id, $0.new.id) })
        let draftIndexByOld = Dictionary(uniqueKeysWithValues: drafts.enumerated().compactMap { index, draft in
            draft.old.map { ($0.id, index) }
        })
        let draftIndexByNew = Dictionary(uniqueKeysWithValues: drafts.enumerated().compactMap { index, draft in
            draft.new.map { ($0.id, index) }
        })

        var linksByIndex: [Int: [CausalityLink]] = [:]
        for (triggerIndex, trigger) in drafts.enumerated() {
            guard trigger.old?.kind == .condition || trigger.new?.kind == .condition,
                  trigger.state == .added || trigger.state == .removed || trigger.state == .modified
            else { continue }
            var affectedIndices: Set<Int> = []
            if let newID = trigger.new?.id, let newGraph {
                for reachable in reachableNodes(from: newID, graph: newGraph) {
                    if let index = draftIndexByNew[reachable] {
                        affectedIndices.insert(index)
                    }
                }
            }
            if let oldID = trigger.old?.id, let oldGraph {
                for reachable in reachableNodes(from: oldID, graph: oldGraph) {
                    if let mapped = pairedByOld[reachable], let index = draftIndexByNew[mapped] {
                        affectedIndices.insert(index)
                    } else if let index = draftIndexByOld[reachable] {
                        affectedIndices.insert(index)
                    }
                }
            }
            affectedIndices.remove(triggerIndex)
            for index in affectedIndices where drafts[index].state == .retained {
                guard drafts[index].new?.isSynthetic != true, drafts[index].old?.isSynthetic != true else { continue }
                let link = CausalityLink(
                    triggerID: trigger.id,
                    affectedID: drafts[index].id,
                    basis: .control,
                    explanation: "Control context changed downstream of \(trigger.new?.label ?? trigger.old?.label ?? "condition")."
                )
                linksByIndex[index, default: []].append(link)
            }
        }

        for index in drafts.indices where linksByIndex[index]?.isEmpty == false {
            drafts[index].state = .affected
            drafts[index].causality = linksByIndex[index, default: []]
        }
        return drafts.map { draft in
            FlowNodeDelta(
                id: draft.id,
                old: draft.old,
                new: draft.new,
                state: draft.state,
                confidence: draft.confidence,
                causality: draft.causality
            )
        }
    }

    private func buildEdgeDeltas(
        pairs: [NodePair],
        oldGraph: ControlFlowGraph?,
        newGraph: ControlFlowGraph?
    ) -> [FlowEdgeDelta] {
        let oldToNew = Dictionary(uniqueKeysWithValues: pairs.map { ($0.old.id, $0.new.id) })
        var unmatchedNew = Dictionary(uniqueKeysWithValues: (newGraph?.edges ?? []).map { ($0.id, $0) })
        var result: [FlowEdgeDelta] = []

        for old in oldGraph?.edges ?? [] {
            guard let newSource = oldToNew[old.source], let newTarget = oldToNew[old.target] else {
                result.append(FlowEdgeDelta(
                    id: deltaEdgeID(old: old.id, new: nil),
                    old: old,
                    new: nil,
                    state: .removed
                ))
                continue
            }
            let exact = unmatchedNew.values.first {
                $0.source == newSource && $0.target == newTarget && $0.kind == old.kind && $0.label == old.label
            }
            let compatible = exact ?? unmatchedNew.values.first {
                $0.source == newSource && $0.target == newTarget && $0.kind == old.kind
            }
            guard let new = compatible else {
                result.append(FlowEdgeDelta(
                    id: deltaEdgeID(old: old.id, new: nil),
                    old: old,
                    new: nil,
                    state: .removed
                ))
                continue
            }
            unmatchedNew.removeValue(forKey: new.id)
            result.append(FlowEdgeDelta(
                id: deltaEdgeID(old: old.id, new: new.id),
                old: old,
                new: new,
                state: old.label == new.label ? .retained : .modified
            ))
        }
        result.append(contentsOf: unmatchedNew.values.map { new in
            FlowEdgeDelta(
                id: deltaEdgeID(old: nil, new: new.id),
                old: nil,
                new: new,
                state: .added
            )
        })
        return result.sorted { $0.id < $1.id }
    }

    private func reachableNodes(from start: StableID, graph: ControlFlowGraph) -> Set<StableID> {
        var result: Set<StableID> = [start]
        var pending = [start]
        while let current = pending.popLast() {
            for edge in graph.outgoing(from: current) where result.insert(edge.target).inserted {
                pending.append(edge.target)
            }
        }
        return result
    }

    private func classifications(
        nodes: [FlowNodeDelta],
        edges: [FlowEdgeDelta]
    ) -> [FlowChangeClassification] {
        var result: Set<FlowChangeClassification> = []
        var addedCondition = false
        var removedCondition = false
        for node in nodes {
            let value = node.new ?? node.old
            if node.state == .added, value?.kind == .condition, value?.label.hasPrefix("guard ") == true {
                result.insert(.guardInserted)
            }
            if node.state == .modified, value?.kind == .condition {
                result.insert(.conditionChanged)
            }
            if node.state == .added, value?.kind == .condition {
                addedCondition = true
            }
            if node.state == .removed, value?.kind == .condition {
                removedCondition = true
            }
            if node.state == .added, value?.label.hasPrefix("return") == true {
                result.insert(.earlyReturnAdded)
            }
            if node.state == .added, value?.kind == .condition || value?.kind == .switchCase {
                result.insert(.branchAdded)
            }
            if node.state == .removed, value?.kind == .condition || value?.kind == .switchCase {
                result.insert(.branchRemoved)
            }
        }
        if addedCondition, removedCondition {
            result.insert(.conditionChanged)
        }
        if edges.contains(where: { $0.state != .retained && ($0.new ?? $0.old)?.kind == .loopBack }) {
            result.insert(.loopChanged)
        }
        if edges.contains(where: { $0.state == .added && $0.new?.kind == .throwFlow }) {
            result.insert(.errorPathAdded)
        }
        return Array(result)
    }

    private func deltaNodeID(old: StableID?, new: StableID?) -> StableID {
        StableID(namespace: "flow-node-delta", components: [old?.rawValue ?? "", new?.rawValue ?? ""])
    }

    private func deltaEdgeID(old: StableID?, new: StableID?) -> StableID {
        StableID(namespace: "flow-edge-delta", components: [old?.rawValue ?? "", new?.rawValue ?? ""])
    }
}

private struct NodePair {
    let old: FlowNode
    let new: FlowNode
    let confidence: MatchConfidence
}

private struct NodeDraft {
    let id: StableID
    let old: FlowNode?
    let new: FlowNode?
    var state: DeltaState
    let confidence: MatchConfidence?
    var causality: [CausalityLink] = []
}
