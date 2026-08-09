import FlowDeltaCore
import FlowDeltaParse
import Foundation
import OSLog

public struct CallGraphBuilder: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "CallGraph")

    public init() {}

    public func build(from changes: [EntityChange]) -> CallGraph {
        let callableChanges = changes.filter { Self.isCallable($0.old?.kind ?? $0.new?.kind) }
        var nodes: [StableID: CallGraphNode] = [:]
        var oldNodeByEntity: [StableID: StableID] = [:]
        var newNodeByEntity: [StableID: StableID] = [:]
        var oldNodesByName: [String: [StableID]] = [:]
        var newNodesByName: [String: [StableID]] = [:]

        for change in callableChanges {
            let id = StableID(
                namespace: "call-node",
                components: [
                    change.old?.path ?? "",
                    change.new?.path ?? "",
                    change.old?.qualifiedName ?? "",
                    change.new?.qualifiedName ?? ""
                ]
            )
            let entity = change.new ?? change.old
            guard let entity else { continue }
            nodes[id] = CallGraphNode(
                id: id,
                name: entity.qualifiedName,
                path: entity.path,
                range: entity.range,
                state: Self.deltaState(for: change.kind)
            )
            if let old = change.old {
                oldNodeByEntity[old.id] = id
                oldNodesByName[old.name, default: []].append(id)
            }
            if let new = change.new {
                newNodeByEntity[new.id] = id
                newNodesByName[new.name, default: []].append(id)
            }
        }

        let edges = buildEdges(
            changes: callableChanges,
            oldNodeByEntity: oldNodeByEntity,
            newNodeByEntity: newNodeByEntity,
            oldNodesByName: oldNodesByName,
            newNodesByName: newNodesByName,
            nodes: &nodes
        )
        let graph = CallGraph(nodes: Array(nodes.values), edges: edges)
        Self.logger.notice("Built call-graph delta with \(graph.nodes.count) nodes and \(graph.edges.count) edges")
        return graph
    }

    private func buildEdges(
        changes: [EntityChange],
        oldNodeByEntity: [StableID: StableID],
        newNodeByEntity: [StableID: StableID],
        oldNodesByName: [String: [StableID]],
        newNodesByName: [String: [StableID]],
        nodes: inout [StableID: CallGraphNode]
    ) -> [CallGraphEdge] {
        var externalNodes: [String: StableID] = [:]
        var oldPairs: Set<CallPair> = []
        var newPairs: Set<CallPair> = []
        for change in changes {
            if let old = change.old, let caller = oldNodeByEntity[old.id] {
                let profile = LanguageProfile.profile(for: SourceLanguage(path: old.path) ?? .swift)
                for calledName in calledNames(in: old.body, profile: profile) {
                    let callee = resolveNode(
                        named: calledName,
                        candidates: oldNodesByName,
                        nodes: &nodes,
                        externalNodes: &externalNodes
                    )
                    oldPairs.insert(CallPair(caller: caller, callee: callee))
                }
            }
            if let new = change.new, let caller = newNodeByEntity[new.id] {
                let profile = LanguageProfile.profile(for: SourceLanguage(path: new.path) ?? .swift)
                for calledName in calledNames(in: new.body, profile: profile) {
                    let callee = resolveNode(
                        named: calledName,
                        candidates: newNodesByName,
                        nodes: &nodes,
                        externalNodes: &externalNodes
                    )
                    newPairs.insert(CallPair(caller: caller, callee: callee))
                }
            }
        }

        return oldPairs.union(newPairs).map { pair in
            let state: DeltaState = switch (oldPairs.contains(pair), newPairs.contains(pair)) {
            case (true, true): .retained
            case (true, false): .removed
            case (false, true): .added
            case (false, false): .retained
            }
            return CallGraphEdge(caller: pair.caller, callee: pair.callee, state: state)
        }
    }

    private func resolveNode(
        named name: String,
        candidates: [String: [StableID]],
        nodes: inout [StableID: CallGraphNode],
        externalNodes: inout [String: StableID]
    ) -> StableID {
        if let matches = candidates[name], matches.count == 1, let only = matches.first {
            return only
        }
        if let existing = externalNodes[name] {
            return existing
        }
        let id = StableID(namespace: "external-call-node", components: [name])
        externalNodes[name] = id
        nodes[id] = CallGraphNode(id: id, name: name, state: .retained, external: true)
        return id
    }

    private func calledNames(in body: SyntaxNode, profile: LanguageProfile) -> Set<String> {
        var result: Set<String> = []
        func visit(_ node: SyntaxNode, isRoot: Bool) {
            if !isRoot, Self.nestedCallableKinds.contains(node.kind) {
                return
            }
            if profile.callKinds.contains(node.kind) {
                let callable = node.firstChild(fieldName: "function")
                    ?? node.firstChild(fieldName: "callee")
                    ?? node.children.first(where: { child in
                        profile.identifierKinds.contains(child.kind)
                            || child.kind.contains("member")
                            || child.kind.contains("selector")
                    })
                let candidate = callable?.firstChild(fieldName: "property")?.text
                    ?? callable?.firstChild(fieldName: "field")?.text
                    ?? callable?.descendants.last(where: { profile.identifierKinds.contains($0.kind) })?.text
                    ?? callable?.text
                if let candidate {
                    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        result.insert(trimmed)
                    }
                }
            }
            for child in node.children {
                visit(child, isRoot: false)
            }
        }
        visit(body, isRoot: true)
        return result
    }

    private static let nestedCallableKinds: Set<String> = [
        "function_declaration", "generator_function_declaration", "function_expression", "generator_function",
        "arrow_function", "method_definition", "function_definition", "lambda", "function_literal",
        "method_declaration", "initializer_declaration", "deinitializer_declaration", "subscript_declaration"
    ]

    private static func deltaState(for kind: EntityChangeKind) -> DeltaState {
        switch kind {
        case .added: .added
        case .removed: .removed
        case .modified, .moved, .renamed: .modified
        case .unchanged: .retained
        }
    }

    private static func isCallable(_ kind: EntityKind?) -> Bool {
        switch kind {
        case .function, .method, .initializer, .deinitializer, .subscriptDeclaration, .operatorDeclaration:
            true
        case .type, .typeExtension, .topLevelBinding, nil:
            false
        }
    }
}

private struct CallPair: Hashable {
    let caller: StableID
    let callee: StableID
}
