import FlowDeltaCore
import Foundation
import OSLog

public struct GumTreeConfiguration: Sendable, Hashable {
    public var minimumAnchorHeight: Int
    public var minimumDiceSimilarity: Double

    public init(minimumAnchorHeight: Int = 2, minimumDiceSimilarity: Double = 0.50) {
        self.minimumAnchorHeight = minimumAnchorHeight
        self.minimumDiceSimilarity = minimumDiceSimilarity
    }
}

public struct GumTreeMatcher: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "GumTree")
    public let configuration: GumTreeConfiguration

    public init(configuration: GumTreeConfiguration = .init()) {
        self.configuration = configuration
    }

    public func match(old oldRoot: SyntaxNode, new newRoot: SyntaxNode) -> EditScript {
        let oldNodes = oldRoot.descendants
        let newNodes = newRoot.descendants
        let oldByID = Dictionary(uniqueKeysWithValues: oldNodes.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: newNodes.map { ($0.id, $0) })
        let oldParents = parentMap(root: oldRoot)
        let newParents = parentMap(root: newRoot)
        var oldToNew: [StableID: StableID] = [:]
        var newToOld: [StableID: StableID] = [:]
        var confidence: [StableID: MatchConfidence] = [:]

        if oldRoot.kind == newRoot.kind {
            install(oldRoot, newRoot, score: 1, oldToNew: &oldToNew, newToOld: &newToOld, confidence: &confidence)
        }
        anchorIdenticalSubtrees(
            oldNodes: oldNodes,
            newNodes: newNodes,
            oldToNew: &oldToNew,
            newToOld: &newToOld,
            confidence: &confidence
        )
        bottomUpMatch(
            oldNodes: oldNodes,
            newNodes: newNodes,
            oldToNew: &oldToNew,
            newToOld: &newToOld,
            confidence: &confidence
        )
        alignUniqueChildren(
            oldNodes: oldNodes,
            newByID: newByID,
            oldToNew: &oldToNew,
            newToOld: &newToOld,
            confidence: &confidence
        )

        let mappings = oldToNew.compactMap { oldID, newID -> SyntaxMapping? in
            guard let matchConfidence = confidence[oldID] else { return nil }
            return SyntaxMapping(oldID: oldID, newID: newID, confidence: matchConfidence)
        }
        var operations: [EditOperation] = []
        operations.append(contentsOf: oldNodes.filter { oldToNew[$0.id] == nil }.map {
            EditOperation(kind: .delete, oldID: $0.id, newID: nil)
        })
        operations.append(contentsOf: newNodes.filter { newToOld[$0.id] == nil }.map {
            EditOperation(kind: .insert, oldID: nil, newID: $0.id)
        })

        for mapping in mappings {
            guard let oldNode = oldByID[mapping.oldID], let newNode = newByID[mapping.newID] else { continue }
            if oldNode.children.isEmpty,
               newNode.children.isEmpty,
               oldNode.text.trimmingCharacters(in: .whitespacesAndNewlines)
                != newNode.text.trimmingCharacters(in: .whitespacesAndNewlines)
            {
                operations.append(EditOperation(kind: .update, oldID: oldNode.id, newID: newNode.id))
            }
            if let oldParent = oldParents[oldNode.id],
               let newParent = newParents[newNode.id],
               oldToNew[oldParent] != newParent
            {
                operations.append(EditOperation(kind: .move, oldID: oldNode.id, newID: newNode.id))
            }
        }
        operations.sort(by: operationOrder)
        Self.logger.debug("GumTree produced \(mappings.count) mappings and \(operations.count) operations")
        return EditScript(mappings: mappings, operations: operations)
    }

    private func anchorIdenticalSubtrees(
        oldNodes: [SyntaxNode],
        newNodes: [SyntaxNode],
        oldToNew: inout [StableID: StableID],
        newToOld: inout [StableID: StableID],
        confidence: inout [StableID: MatchConfidence]
    ) {
        let eligibleOld = oldNodes.filter { $0.height >= configuration.minimumAnchorHeight }
        let eligibleNew = newNodes.filter { $0.height >= configuration.minimumAnchorHeight }
        let oldGroups = Dictionary(grouping: eligibleOld, by: { "\($0.kind):\($0.structuralDigest)" })
        let newGroups = Dictionary(grouping: eligibleNew, by: { "\($0.kind):\($0.structuralDigest)" })
        for key in oldGroups.keys.sorted() {
            guard oldGroups[key]?.count == 1,
                  newGroups[key]?.count == 1,
                  let oldNode = oldGroups[key]?.first,
                  let newNode = newGroups[key]?.first
            else { continue }
            installRecursively(
                oldNode,
                newNode,
                oldToNew: &oldToNew,
                newToOld: &newToOld,
                confidence: &confidence
            )
        }
    }

    private func installRecursively(
        _ old: SyntaxNode,
        _ new: SyntaxNode,
        oldToNew: inout [StableID: StableID],
        newToOld: inout [StableID: StableID],
        confidence: inout [StableID: MatchConfidence]
    ) {
        guard old.kind == new.kind, old.children.count == new.children.count else { return }
        install(old, new, score: 1, oldToNew: &oldToNew, newToOld: &newToOld, confidence: &confidence)
        for (oldChild, newChild) in zip(old.children, new.children) {
            installRecursively(
                oldChild,
                newChild,
                oldToNew: &oldToNew,
                newToOld: &newToOld,
                confidence: &confidence
            )
        }
    }

    private func bottomUpMatch(
        oldNodes: [SyntaxNode],
        newNodes: [SyntaxNode],
        oldToNew: inout [StableID: StableID],
        newToOld: inout [StableID: StableID],
        confidence: inout [StableID: MatchConfidence]
    ) {
        let orderedOld = oldNodes.sorted { ($0.height, $0.range.start, $0.id) > ($1.height, $1.range.start, $1.id) }
        for oldNode in orderedOld where oldToNew[oldNode.id] == nil {
            var best: (node: SyntaxNode, score: Double)?
            for newNode in newNodes where newToOld[newNode.id] == nil && oldNode.kind == newNode.kind {
                let score = similarity(old: oldNode, new: newNode, oldToNew: oldToNew)
                if score >= configuration.minimumDiceSimilarity,
                   best == nil || score > best!.score || (score == best!.score && newNode.id < best!.node.id)
                {
                    best = (newNode, score)
                }
            }
            if let best {
                install(
                    oldNode,
                    best.node,
                    score: best.score,
                    oldToNew: &oldToNew,
                    newToOld: &newToOld,
                    confidence: &confidence
                )
            }
        }
    }

    private func similarity(old: SyntaxNode, new: SyntaxNode, oldToNew: [StableID: StableID]) -> Double {
        if old.children.isEmpty && new.children.isEmpty {
            return EntityMatcher.tokenDice(old.normalizedTokens, new.normalizedTokens)
        }
        let newDescendants = Set(new.descendants.map(\.id))
        let mapped = old.descendants.dropFirst().reduce(into: 0) { count, descendant in
            if let mappedID = oldToNew[descendant.id], newDescendants.contains(mappedID) {
                count += 1
            }
        }
        let denominator = old.descendants.count + new.descendants.count - 2
        return denominator == 0 ? 1 : (2 * Double(mapped)) / Double(denominator)
    }

    private func alignUniqueChildren(
        oldNodes: [SyntaxNode],
        newByID: [StableID: SyntaxNode],
        oldToNew: inout [StableID: StableID],
        newToOld: inout [StableID: StableID],
        confidence: inout [StableID: MatchConfidence]
    ) {
        var installed = true
        while installed {
            installed = false
            for oldParent in oldNodes {
                guard let newParentID = oldToNew[oldParent.id],
                      let newParent = newByID[newParentID]
                else { continue }
                let oldGroups = Dictionary(
                    grouping: oldParent.children.filter { oldToNew[$0.id] == nil },
                    by: \.kind
                )
                let newGroups = Dictionary(
                    grouping: newParent.children.filter { newToOld[$0.id] == nil },
                    by: \.kind
                )
                for kind in oldGroups.keys.sorted() {
                    guard let oldChild = oldGroups[kind]?.only,
                          let newChild = newGroups[kind]?.only
                    else { continue }
                    install(
                        oldChild,
                        newChild,
                        score: 0.75,
                        oldToNew: &oldToNew,
                        newToOld: &newToOld,
                        confidence: &confidence
                    )
                    installed = true
                }
            }
        }
    }

    private func install(
        _ old: SyntaxNode,
        _ new: SyntaxNode,
        score: Double,
        oldToNew: inout [StableID: StableID],
        newToOld: inout [StableID: StableID],
        confidence: inout [StableID: MatchConfidence]
    ) {
        guard oldToNew[old.id] == nil, newToOld[new.id] == nil else { return }
        oldToNew[old.id] = new.id
        newToOld[new.id] = old.id
        confidence[old.id] = MatchConfidence(tier: .gumTree, score: min(1, max(0, score)))
    }

    private func parentMap(root: SyntaxNode) -> [StableID: StableID] {
        var result: [StableID: StableID] = [:]
        func walk(_ node: SyntaxNode) {
            for child in node.children {
                result[child.id] = node.id
                walk(child)
            }
        }
        walk(root)
        return result
    }

    private func operationOrder(_ lhs: EditOperation, _ rhs: EditOperation) -> Bool {
        let order: [EditOperationKind: Int] = [.delete: 0, .move: 1, .update: 2, .insert: 3]
        let leftID = lhs.oldID ?? lhs.newID!
        let rightID = rhs.oldID ?? rhs.newID!
        return (order[lhs.kind]!, leftID) < (order[rhs.kind]!, rightID)
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
