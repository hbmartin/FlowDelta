import FlowDeltaCore
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
        guard language == .swift || language == .typescript || language == .javascript else { return nil }
        var definitions: [String: StableID] = [:]
        var edges: Set<DataFlowEdge> = []
        for node in graph.nodes.sorted(by: { ($0.sourceOrder, $0.id) < ($1.sourceOrder, $1.id) })
            where !node.isSynthetic
        {
            let facts = lexicalFacts(in: node.label, language: language)
            for symbol in facts.uses.sorted() {
                guard let definition = definitions[symbol], definition != node.id else { continue }
                edges.insert(DataFlowEdge(symbol: symbol, definition: definition, use: node.id))
            }
            for symbol in facts.definitions.sorted() {
                definitions[symbol] = node.id
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
        let identifiers = matches(pattern: #"\b[A-Za-z_$][A-Za-z0-9_$]*\b"#, in: text, group: 0)
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
        definitions.formUnion(matches(
            pattern: #"\b([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:\+|-|\*|/|%|\?\?)?=(?!=|>)"#,
            in: text,
            group: 1
        ))
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

private struct LexicalFacts {
    let definitions: Set<String>
    let uses: Set<String>
}
