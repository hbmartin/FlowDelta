import FlowDeltaCore
import FlowDeltaParse
import Foundation
import OSLog

/// Groups a revision's entity changes by concern, using calls, name references and shared types as evidence.
public struct HeuristicConcernGrouper: Sendable {
    private static let logger = Logger(subsystem: "com.flowdelta", category: "Concerns")

    public init() {}

    public func concerns(for report: RevisionFlowDeltaReport) -> [FlowConcern] {
        let members = Self.members(of: report)
        guard !members.isEmpty else { return [] }
        var groups = UnionFind(count: members.count)
        var links: [FlowConcernLink] = []
        func join(_ first: Int, _ second: Int, _ reason: FlowConcernLinkReason) {
            if groups.union(first, second) {
                links.append(FlowConcernLink(from: members[first].id, to: members[second].id, reason: reason))
            }
        }
        let behavioral = members.indices.filter { members[$0].kind == .behavioral }

        // 1. Calls between changed entities.
        let indexByCallNode = Dictionary(
            behavioral.map { (CallGraphNode.stableID(for: members[$0].change), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for edge in report.callGraph?.edges ?? [] {
            if let caller = indexByCallNode[edge.caller], let callee = indexByCallNode[edge.callee], caller != callee {
                join(caller, callee, .call)
            }
        }
        // 2. A changed entity's new body naming another changed entity.
        for first in behavioral {
            let names = members[first].referencedNames
            for second in behavioral where second != first {
                if let name = members[second].referenceName, names.contains(name) {
                    join(first, second, .reference)
                }
            }
        }
        // 3. Leftover singletons join the first entity in the same file and type.
        for index in behavioral where groups.size(of: index) == 1 {
            let keys = members[index].typeKeys
            guard !keys.isEmpty,
                  let anchor = behavioral.first(where: { $0 != index && !members[$0].typeKeys.isDisjoint(with: keys) })
            else { continue }
            join(anchor, index, .sameType)
        }

        var concerns = behavioralConcerns(members: members, groups: &groups, links: links, behavioral: behavioral)
        concerns += fixedConcerns(members: members)
        Self.logger.debug("Grouped \(members.count) changes into \(concerns.count) concerns")
        return concerns
    }

    // MARK: Groups

    private func behavioralConcerns(
        members: [Member],
        groups: inout UnionFind,
        links: [FlowConcernLink],
        behavioral: [Int]
    ) -> [FlowConcern] {
        var byRoot: [Int: [Int]] = [:]
        for index in behavioral {
            byRoot[groups.find(index), default: []].append(index)
        }
        // A type that changed only inside changed members goes with its first behavioral member.
        var containers: [Int: [Int]] = [:]
        for index in members.indices where members[index].kind == .container {
            if let member = behavioral.first(where: { members[$0].typeKey == members[index].ownTypeKey }) {
                containers[groups.find(member), default: []].append(index)
            }
        }
        return byRoot.values.sorted { $0[0] < $1[0] }.map { indices in
            let attached = containers[groups.find(indices[0]), default: []]
            let all = (indices + attached).sorted()
            let ids = Set(all.map { members[$0].id })
            let containerLinks = attached.compactMap { container in
                indices.first { members[$0].typeKey == members[container].ownTypeKey }.map {
                    FlowConcernLink(from: members[container].id, to: members[$0].id, reason: .container)
                }
            }
            let first = members[all[0]]
            let title = all.count == 1
                ? "`\(first.name)`"
                : "`\(first.name)` and \(all.count - 1) related change\(all.count == 2 ? "" : "s")"
            return FlowConcern(
                id: StableID(
                    namespace: "concern",
                    components: [FlowConcernKind.behavioral.rawValue, first.id.rawValue]
                ),
                kind: .behavioral,
                title: title,
                memberIDs: all.map { members[$0].id },
                links: links.filter { ids.contains($0.from) && ids.contains($0.to) } + containerLinks
            )
        }
    }

    private func fixedConcerns(members: [Member]) -> [FlowConcern] {
        let behavioralTypeKeys = Set(members.filter { $0.kind == .behavioral }.compactMap(\.typeKey))
        var refactoring: [Int] = []
        var cosmetic: [Int] = []
        for index in members.indices {
            switch members[index].kind {
            case .refactoring:
                refactoring.append(index)
            case .cosmetic:
                cosmetic.append(index)
            case .container:
                // Attached to a behavioral group above, or else to the group of its first changed member.
                guard let key = members[index].ownTypeKey, !behavioralTypeKeys.contains(key) else { continue }
                let member = members.first { $0.typeKey == key && $0.kind != .container }
                if member?.kind == .cosmetic {
                    cosmetic.append(index)
                } else {
                    refactoring.append(index)
                }
            case .behavioral:
                continue
            }
        }
        return [
            (FlowConcernKind.refactoring, "Renames, moves and rewrites", refactoring),
            (.cosmetic, "Formatting and cosmetic changes", cosmetic)
        ].compactMap { kind, title, indices in
            guard !indices.isEmpty else { return nil }
            return FlowConcern(
                id: StableID(namespace: "concern", components: [kind.rawValue]),
                kind: kind,
                title: title,
                memberIDs: indices.sorted().map { members[$0].id },
                links: []
            )
        }
    }

    // MARK: Members

    enum MemberKind: Equatable {
        case behavioral, refactoring, cosmetic
        /// A modified type whose only changes are inside its members.
        case container
    }

    struct Member {
        let change: EntityChange
        let id: StableID
        let name: String
        let kind: MemberKind
        /// The file and type that contain the entity, when it is inside one.
        let typeKey: String?
        /// The file and type the entity is, when it is a type.
        let ownTypeKey: String?
        /// The name other bodies refer to the entity by, if they can.
        let referenceName: String?
        let referencedNames: Set<String>

        /// The type keys that put the entity in a type: the type it is in, and the type it is.
        var typeKeys: Set<String> {
            Set([typeKey, ownTypeKey].compactMap(\.self))
        }
    }

    static func members(of report: RevisionFlowDeltaReport) -> [Member] {
        var members: [(order: (String, Int, String), member: Member)] = []
        for file in report.files {
            let functions = file.functionDeltas
            let entities = file.entityChanges
            for change in entities where change.kind != .unchanged {
                guard let entity = change.new ?? change.old, let id = change.entityID else { continue }
                let kind = classify(change, function: functions.first { $0.entityChange == change }, in: entities)
                let isType = entity.kind == .type || entity.kind == .typeExtension
                members.append((
                    (entity.path, entity.range.start.utf16Offset, entity.qualifiedName),
                    Member(
                        change: change,
                        id: id,
                        name: entity.name,
                        kind: kind,
                        typeKey: container(of: entity).map { "\(entity.path)#\($0)" },
                        ownTypeKey: isType ? "\(entity.path)#\(entity.qualifiedName)" : nil,
                        referenceName: referenceName(of: entity),
                        referencedNames: referencedNames(of: change, isType: isType, in: entities)
                    )
                ))
            }
        }
        return members.sorted { $0.order < $1.order }.map(\.member)
    }

    /// The parameter clause of a qualified name, which a pure rename or move leaves unchanged.
    static func signature(of entity: SourceEntity) -> Substring {
        entity.qualifiedName.firstIndex(of: "(").map { entity.qualifiedName[$0...] } ?? ""
    }

    static func classify(
        _ change: EntityChange,
        function: FunctionFlowDelta?,
        in entities: [EntityChange]
    ) -> MemberKind {
        switch change.kind {
        case .moved, .renamed:
            // A rename keeps the signature and the rest of the header; a changed parameter clause, such as a new
            // default value, or a new `async` or modifier is behavior.
            if let old = change.old, let new = change.new, old.body.structuralDigest == new.body.structuralDigest,
               signature(of: old) == signature(of: new), old.hasSameDeclarationHeader(as: new)
            {
                return .refactoring
            }
            return .behavioral
        case .modified:
            if let old = change.old, let new = change.new, !old.hasSameDeclarationHeader(as: new) {
                return .behavioral
            }
            if let function {
                switch FlowNoiseFilter.noiseLevel(of: function) {
                case .formatting?, .optionalSyntax?: return .cosmetic
                case .rewrite?: return .refactoring
                case nil: return .behavioral
                }
            }
            if let old = change.old, let new = change.new, old.kind == .type || old.kind == .typeExtension,
               ownTokens(of: old, members: entities.compactMap(\.old)) == ownTokens(
                   of: new,
                   members: entities.compactMap(\.new)
               )
            {
                return .container
            }
            return .behavioral
        case .added, .removed, .unchanged:
            return .behavioral
        }
    }

    /// The names a change's new body uses. A type's body holds its members, so only its own tokens count.
    private static func referencedNames(
        of change: EntityChange,
        isType: Bool,
        in entities: [EntityChange]
    ) -> Set<String> {
        guard let new = change.new else { return [] }
        let tokens = isType ? ownTokens(of: new, members: entities.compactMap(\.new)) : new.body.normalizedTokens
        return references(in: tokens).subtracting([new.name])
    }

    /// Bare identifiers: not a member after `.` (calls reach those through the call graph), and not an argument
    /// label, keyword argument or assignment target before `:` or `=`. A type annotation before `=` still counts.
    static func references(in tokens: [String]) -> Set<String> {
        var names: Set<String> = []
        for (index, token) in tokens.enumerated() {
            guard let first = token.unicodeScalars.first,
                  first == "_" || CharacterSet.letters.contains(first),
                  token.unicodeScalars.allSatisfy({ $0 == "_" || CharacterSet.alphanumerics.contains($0) })
            else { continue }
            let previous = index > 0 ? tokens[index - 1] : nil
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            if previous == "." || next == ":" || (next == "=" && previous != ":") {
                continue
            }
            names.insert(token)
        }
        return names
    }

    /// The type's tokens outside the entities declared inside it.
    static func ownTokens(of type: SourceEntity, members: [SourceEntity]) -> [String] {
        let inner = members
            .filter {
                $0.id != type.id && $0.path == type.path && type.range.start <= $0.range.start && $0.range.end <= type
                    .range.end
            }
            .map(\.range)
        let rules = SourceLanguage(path: type.path).map { LanguageProfile.profile(for: $0).noise }
        let comments = rules?.commentKinds ?? ["comment"]
        func tokens(_ node: SyntaxNode) -> [String] {
            if comments.contains(node.kind) || inner
                .contains(where: { $0.start <= node.range.start && node.range.end <= $0.end })
            {
                return []
            }
            // A field's initial value can be a literal, so a change inside the quotes is the type's own change.
            if rules?.literalKinds.contains(node.kind) == true {
                return FlowNoiseClassifier.literalToken(of: node).map { [$0] } ?? []
            }
            if node.children.isEmpty {
                let token = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return token.isEmpty ? [] : [token]
            }
            return node.children.flatMap(tokens)
        }
        return tokens(type.body)
    }

    /// The type part of `Type.name(parameters)`, or nil for a top-level entity.
    static func container(of entity: SourceEntity) -> String? {
        let head = entity.qualifiedName.prefix { $0 != "(" }
        guard let dot = head.lastIndex(of: ".") else { return nil }
        return String(head[..<dot])
    }

    private static func referenceName(of entity: SourceEntity) -> String? {
        switch entity.kind {
        case .initializer, .deinitializer, .subscriptDeclaration, .operatorDeclaration:
            nil
        default:
            entity.name.count > 1 ? entity.name : nil
        }
    }
}

/// Disjoint sets over `0 ..< count` with path compression and union by size.
struct UnionFind {
    private var parent: [Int]
    private var sizes: [Int]

    init(count: Int) {
        parent = Array(0 ..< count)
        sizes = Array(repeating: 1, count: count)
    }

    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root {
            root = parent[root]
        }
        var current = element
        while parent[current] != root {
            (parent[current], current) = (root, parent[current])
        }
        return root
    }

    /// Joins the two sets and reports whether they were separate.
    @discardableResult
    mutating func union(_ first: Int, _ second: Int) -> Bool {
        var (left, right) = (find(first), find(second))
        guard left != right else { return false }
        if sizes[left] < sizes[right] {
            swap(&left, &right)
        }
        parent[right] = left
        sizes[left] += sizes[right]
        return true
    }

    mutating func size(of element: Int) -> Int {
        sizes[find(element)]
    }
}
