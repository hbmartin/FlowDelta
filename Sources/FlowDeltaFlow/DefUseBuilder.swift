import FlowDeltaCore
import FlowDeltaParse
import Foundation
import OSLog

public struct DefUseBuilder: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "DataFlow")

    public init() {}

    public func build(
        for entity: SourceEntity,
        graph: ControlFlowGraph,
        language: SourceLanguage
    ) -> DataFlowGraph? {
        let syntaxByID = Dictionary(
            entity.body.descendants.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let orderedNodes = graph.nodes.sorted(by: { ($0.sourceOrder, $0.id) < ($1.sourceOrder, $1.id) })
        let profile = LanguageProfile.profile(for: language)
        let syntaxFacts = profile.binding.map { SyntaxBindingFacts(entity: entity, profile: profile, rules: $0) }
        let factsByNode = Dictionary(uniqueKeysWithValues: orderedNodes.map { node in
            if node.isSynthetic {
                return (node.id, LexicalFacts.empty)
            }
            if let syntaxFacts {
                return (node.id, syntaxFacts.facts(for: node))
            }
            let source = sourceText(for: node, syntaxByID: syntaxByID)
            return (node.id, lexicalFacts(in: source, language: language))
        })
        let predecessors = Dictionary(grouping: graph.edges, by: \.target).mapValues { edges in
            Set(edges.map(\.source))
        }
        let parameters = entity.parameterNames.map(Set.init) ?? parameterNames(in: entity, language: language)
        let scopes = syntaxFacts?.scopes(for: orderedNodes, function: entity.body.id)
            ?? BindingScopes(function: entity.body.id)
        let parameterState = Dictionary(uniqueKeysWithValues: parameters.map {
            (BindingKey(name: $0, scope: scopes.function), Set([graph.entryID]))
        })
        var incomingByNode: [StableID: DefinitionState] = [:]
        var outgoingByNode: [StableID: DefinitionState] = [:]
        var changed = true
        while changed {
            changed = false
            for node in orderedNodes {
                var incoming = mergeDefinitions(
                    from: predecessors[node.id, default: []],
                    outgoingByNode: outgoingByNode
                )
                if node.id == graph.entryID {
                    incoming.merge(parameterState) { $0.union($1) }
                }
                // A name declared in a block ends with it, and the binding it shadowed is visible again.
                incoming = incoming.filter { key, _ in scopes.isVisible(key.scope, at: node.id) }
                incomingByNode[node.id] = incoming
                var outgoing = incoming
                let facts = factsByNode[node.id, default: .empty]
                for symbol in facts.definitions {
                    let key = facts.declarations.contains(symbol)
                        ? BindingKey(name: symbol, scope: scopes.declaringScope(of: node.id))
                        : scopes.innermost(symbol, in: incoming) ?? BindingKey(name: symbol, scope: scopes.function)
                    outgoing[key] = [node.id]
                }
                if outgoingByNode[node.id] != outgoing {
                    outgoingByNode[node.id] = outgoing
                    changed = true
                }
            }
        }

        var edges: Set<DataFlowEdge> = []
        for node in orderedNodes where !node.isSynthetic {
            let facts = factsByNode[node.id, default: .empty]
            let incoming = incomingByNode[node.id, default: [:]]
            for symbol in facts.uses.sorted() {
                guard let key = scopes.innermost(symbol, in: incoming) else { continue }
                for definition in incoming[key, default: []] where definition != node.id {
                    edges.insert(DataFlowEdge(symbol: symbol, definition: definition, use: node.id))
                }
            }
        }
        let result = DataFlowGraph(entityID: entity.id, edges: Array(edges))
        Self.logger.debug(
            "Built \(language.displayName, privacy: .public) def-use graph for \(entity.qualifiedName, privacy: .public): \(result.edges.count) edges"
        )
        return result
    }

    private func lexicalFacts(in source: String, language: SourceLanguage) -> LexicalFacts {
        let text = strippingStringsAndComments(source)
        let identifiers = identifiersExcludingMemberNames(in: text)
        var definitions = Set(matches(
            pattern: #"\b(?:let|var|const)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#,
            in: text,
            group: 1
        ))
        definitions.formUnion(matches(
            pattern: #"\bfor\s+(?:let\s+|var\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s+(?:in|of)\b"#,
            in: text,
            group: 1
        ))
        definitions.formUnion(assignmentDefinitions(in: text))
        definitions.formUnion(matches(
            pattern: #"\bcatch\s*(?:\(|let\s+|var\s+)?([A-Za-z_$][A-Za-z0-9_$]*)"#,
            in: text,
            group: 1
        ))

        let counts = Dictionary(grouping: identifiers, by: { $0 }).mapValues(\.count)
        let keywords = Self.keywords(for: language)
        var uses = Set(identifiers.filter { !keywords.contains($0) })
        for definition in definitions where counts[definition, default: 0] <= 1 {
            uses.remove(definition)
        }
        return LexicalFacts(definitions: definitions, uses: uses)
    }

    private func sourceText(for node: FlowNode, syntaxByID: [StableID: SyntaxNode]) -> String {
        if node.kind == .switchCase || node.kind == .deferBlock {
            return node.label
        }
        if node.kind == .catchBlock {
            return node.label.split(separator: "{", maxSplits: 1).first.map(String.init) ?? node.label
        }
        let candidates = node.syntaxIDs.compactMap { syntaxByID[$0] }
        return candidates.max { lhs, rhs in
            lhs.range.utf16Range.count < rhs.range.utf16Range.count
        }?.text ?? node.label
    }

    private func mergeDefinitions(
        from predecessors: Set<StableID>,
        outgoingByNode: [StableID: DefinitionState]
    ) -> DefinitionState {
        var result: DefinitionState = [:]
        for predecessor in predecessors {
            for (symbol, definitions) in outgoingByNode[predecessor, default: [:]] {
                result[symbol, default: []].formUnion(definitions)
            }
        }
        return result
    }

    private func parameterNames(in entity: SourceEntity, language: SourceLanguage) -> Set<String> {
        guard let opening = entity.qualifiedName.firstIndex(of: "("),
              let closing = entity.qualifiedName.lastIndex(of: ")"),
              opening < closing
        else { return [] }
        let clause = entity.qualifiedName[entity.qualifiedName.index(after: opening) ..< closing]
        if language == .go {
            return goParameterNames(in: splitParameters(String(clause)))
        }
        return Set(splitParameters(String(clause)).compactMap { parameter in
            var declaration = parameter.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !declaration.isEmpty, !declaration.hasPrefix("{"), !declaration.hasPrefix("[") else {
                return nil
            }
            if let equals = declaration.firstIndex(of: "=") {
                declaration = String(declaration[..<equals])
            }
            if let colon = declaration.firstIndex(of: ":") {
                declaration = String(declaration[..<colon])
            }
            let normalized = declaration
                .replacingOccurrences(of: "...", with: "")
                .replacingOccurrences(of: "?", with: "")
            let pieces = normalized.split(whereSeparator: { $0.isWhitespace })
            let ignored: Set = ["_", "inout", "isolated", "borrowing", "consuming"]
            let tokens = pieces.map(String.init).filter { !ignored.contains($0) }
            guard let candidate = tokens.last,
                  candidate.range(of: #"^[A-Za-z_$][A-Za-z0-9_$]*$"#, options: .regularExpression) != nil
            else { return nil }
            return candidate
        })
    }

    /// Go names come before their types, and either every parameter is named or none is: `a, b int` names `a` and
    /// `b`, while `int, string` names nothing.
    private func goParameterNames(in parameters: [String]) -> Set<String> {
        let pieces = parameters.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }.filter { !$0.isEmpty }
        guard pieces.contains(where: { $0.count > 1 }) else { return [] }
        return Set(pieces.compactMap { piece in
            let name = piece[0]
            guard name != "_", name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                return nil
            }
            return name
        })
    }

    private func splitParameters(_ clause: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        for character in clause {
            switch character {
            case "(", "[", "{", "<":
                depth += 1
            case ")", "]", "}", ">":
                depth = max(0, depth - 1)
            case "," where depth == 0:
                result.append(current)
                current = ""
                continue
            default:
                break
            }
            current.append(character)
        }
        result.append(current)
        return result
    }

    private func identifiersExcludingMemberNames(in source: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\b[A-Za-z_$][A-Za-z0-9_$]*\b"#) else {
            return []
        }
        let range = NSRange(source.startIndex ..< source.endIndex, in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: source) else { return nil }
            let prefix = source[..<matchRange.lowerBound]
            if prefix.last(where: { !$0.isWhitespace }) == "." {
                return nil
            }
            return String(source[matchRange])
        }
    }

    private func assignmentDefinitions(in source: String) -> Set<String> {
        guard let expression = try? NSRegularExpression(
            pattern: #"\b([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:\+|-|\*|/|%|\?\?)?=(?!=|>)"#
        ) else { return [] }
        let range = NSRange(source.startIndex ..< source.endIndex, in: source)
        return Set(expression.matches(in: source, range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: source) else { return nil }
            let prefix = source[..<nameRange.lowerBound]
            guard prefix.last(where: { !$0.isWhitespace }) != "." else { return nil }
            return String(source[nameRange])
        })
    }

    private func strippingStringsAndComments(_ source: String) -> String {
        var result = source
        for pattern in [#"\"(?:\\.|[^\"\\])*\""#, #"'(?:\\.|[^'\\])*'"#, #"//.*$"#, #"/\*[\s\S]*?\*/"#] {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                continue
            }
            let range = NSRange(result.startIndex ..< result.endIndex, in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }
        return result
    }

    private func matches(pattern: String, in source: String, group: Int) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex ..< source.endIndex, in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard group < match.numberOfRanges,
                  let range = Range(match.range(at: group), in: source)
            else { return nil }
            return String(source[range])
        }
    }

    private static func keywords(for language: SourceLanguage) -> Set<String> {
        let shared: Set = [
            "break", "case", "catch", "class", "continue", "default", "else", "false", "for", "func",
            "function", "if", "in", "let", "nil", "null", "return", "self", "super", "switch", "throw",
            "true", "try", "var", "while"
        ]
        switch language {
        case .swift:
            return shared.union(["as", "await", "defer", "do", "guard", "is", "some", "throws"])
        case .typescript, .javascript:
            return shared.union(["async", "await", "const", "extends", "instanceof", "new", "this", "typeof"])
        case .python, .go:
            return shared
        }
    }
}

struct LexicalFacts {
    let definitions: Set<String>
    let uses: Set<String>
    /// The definitions that declare a new name in the node's innermost scope instead of assigning one.
    var declarations: Set<String> = []

    static let empty = LexicalFacts(definitions: [], uses: [])
}

/// One binding of a name: the name and the scope that declares it.
struct BindingKey: Hashable {
    let name: String
    let scope: StableID
}

typealias DefinitionState = [BindingKey: Set<StableID>]

/// Which scopes each node is inside and declares into. A scope outside a node's chain has ended there.
struct BindingScopes {
    /// The function's own scope, which holds parameters and every name in languages without block scopes.
    let function: StableID
    /// Each positioned node's enclosing block scopes, not counting the function's.
    var enclosing: [StableID: Set<StableID>] = [:]
    /// The scope each node declares its names into.
    var declaring: [StableID: StableID] = [:]
    /// How deeply each block scope is nested, counting from the function's scope at zero.
    var depth: [StableID: Int] = [:]

    /// Whether a binding declared in `scope` can reach `node`. A node without syntax keeps every binding.
    func isVisible(_ scope: StableID, at node: StableID) -> Bool {
        scope == function || enclosing[node].map { $0.contains(scope) } ?? true
    }

    func declaringScope(of node: StableID) -> StableID {
        declaring[node] ?? function
    }

    /// The innermost binding of `name` that reaches a node, which shadows the others.
    func innermost(_ name: String, in state: DefinitionState) -> BindingKey? {
        state.keys
            .filter { $0.name == name }
            .max { depth[$0.scope, default: 0] < depth[$1.scope, default: 0] }
    }
}
