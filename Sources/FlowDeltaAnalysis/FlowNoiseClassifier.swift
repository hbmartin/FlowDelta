import FlowDeltaCore
import FlowDeltaParse
import Foundation

/// Decides whether a paired node changed and, when it did, whether the change is noise. It compares the tokens of
/// the node's syntax, because labels collapse whitespace and are truncated.
struct FlowNoiseClassifier {
    enum TokenRole {
        case syntax
        case literal
        case statementTerminator
    }

    struct Token: Equatable {
        let text: String
        let kind: String?
        let role: TokenRole

        init(_ text: String, kind: String? = nil, role: TokenRole = .syntax) {
            self.text = text
            self.kind = kind
            self.role = role
        }

        var syntaxText: String? {
            role == .literal ? nil : text
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.kind == rhs.kind && lhs.role == rhs.role && lhs.text.utf8.elementsEqual(rhs.text.utf8)
        }
    }

    private enum StatementBoundary: Equatable {
        case start(kind: String, field: String?)
        case end
    }

    private struct NodeSyntax {
        var tokens: [Token] = []
        var statementBoundaries: [StatementBoundary] = []
    }

    private let rules: LanguageNoiseRules?
    private let oldSyntax: [StableID: SyntaxNode]
    private let newSyntax: [StableID: SyntaxNode]

    init(entityChange: EntityChange) {
        let path = entityChange.new?.path ?? entityChange.old?.path
        rules = path.flatMap(SourceLanguage.init(path:)).map { LanguageProfile.profile(for: $0).noise }
        oldSyntax = Self.index(entityChange.old?.body)
        newSyntax = Self.index(entityChange.new?.body)
    }

    func classify(old: FlowNode, new: FlowNode) -> (state: DeltaState, noise: FlowNoiseLevel?) {
        guard old.kind == new.kind else { return (.modified, nil) }
        guard let rules,
              let oldSyntax = nodeSyntax(of: old, in: oldSyntax, rules: rules),
              let newSyntax = nodeSyntax(of: new, in: newSyntax, rules: rules)
        else {
            return (old.label == new.label ? .retained : .modified, nil)
        }
        guard oldSyntax.statementBoundaries == newSyntax.statementBoundaries else { return (.modified, nil) }
        if old.label == new.label, oldSyntax.tokens == newSyntax.tokens {
            return (.retained, nil)
        }
        // Equal labels with different tokens are an edit past the label's truncation point.
        return (
            .modified,
            Self.level(old: oldSyntax.tokens, new: newSyntax.tokens, rules: rules, isCondition: old.kind == .condition)
        )
    }

    static func level(old: [Token], new: [Token], rules: LanguageNoiseRules, isCondition: Bool) -> FlowNoiseLevel? {
        if old == new {
            return .formatting
        }
        let optionalOld = withoutOptionalSyntax(old, rules: rules, isCondition: isCondition)
        let optionalNew = withoutOptionalSyntax(new, rules: rules, isCondition: isCondition)
        if optionalOld == optionalNew {
            return .optionalSyntax
        }
        let oldText = optionalOld.compactMap(\.syntaxText)
        let newText = optionalNew.compactMap(\.syntaxText)
        if oldText.count == optionalOld.count, newText.count == optionalNew.count,
           oldText != newText, canonicalRewrite(oldText) == canonicalRewrite(newText)
        {
            return .rewrite
        }
        return nil
    }

    /// The token for a comma that makes a one-element tuple. It never equals an optional `,`.
    static let tupleComma = ",(one-element tuple)"

    /// Drops optional tokens, optional receivers, trailing commas and one pair of parentheses around a condition.
    /// A comma right after an opening bracket or another comma is an array hole and stays.
    static func withoutOptionalSyntax(_ tokens: [Token], rules: LanguageNoiseRules, isCondition: Bool) -> [Token] {
        var result: [Token] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let next = index + 1 < tokens.count ? tokens[index + 1].syntaxText : nil
            let previous = index > 0 ? tokens[index - 1].syntaxText : nil
            defer { index += 1 }
            guard let syntax = token.syntaxText else {
                result.append(token)
                continue
            }
            if token.role == .statementTerminator, rules.optionalTokens.contains(syntax) {
                continue
            }
            // `self.value` is `value`, but `other.self.value` keeps its `self`.
            if rules.optionalReceivers.contains(syntax), next == ".", previous != "." {
                index += 1
                continue
            }
            if rules.allowsTrailingCommas, syntax == ",", let next, [")", "]", "}"].contains(next),
               index > 0, !["(", "[", "{", ","].contains(previous ?? "")
            {
                continue
            }
            result.append(token)
        }
        if isCondition, result.first?.syntaxText == "(", result.last?.syntaxText == ")",
           closingIndex(ofOpeningAt: 0, in: result.map(\.syntaxText)) == result.count - 1
        {
            result = Array(result.dropFirst().dropLast())
        }
        return result
    }

    /// Expands `a op= x` to `a = a op x` when `x` is one token or one parenthesized group, and orders the operands
    /// of a lone `l == r` or `l != r` comparison.
    static func canonicalRewrite(_ tokens: [String]) -> [String] {
        let compound = ["+=": "+", "-=": "-", "*=": "*", "/=": "/", "%=": "%", "&=": "&", "|=": "|", "^=": "^"]
        if tokens.count >= 3, let op = compound[tokens[1]], isSingleOperand(Array(tokens[2...])) {
            return [tokens[0], "=", tokens[0], op] + tokens[2...]
        }
        if tokens.count == 3, ["==", "!=", "===", "!=="].contains(tokens[1]) {
            let operands = [tokens[0], tokens[2]].sorted()
            return [operands[0], tokens[1], operands[1]]
        }
        return tokens
    }

    private static func isSingleOperand(_ tokens: [String]) -> Bool {
        if tokens.count == 1 {
            return true
        }
        let syntax = tokens.map(Optional.some)
        return tokens.first == "(" && closingIndex(ofOpeningAt: 0, in: syntax) == syntax.count - 1
    }

    private static func closingIndex(ofOpeningAt start: Int, in tokens: [String?]) -> Int? {
        var depth = 0
        for index in start ..< tokens.count {
            if tokens[index] == "(" {
                depth += 1
            } else if tokens[index] == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        return nil
    }

    /// The node's syntax in source order, or nil when any of its syntax is missing.
    private func nodeSyntax(
        of node: FlowNode,
        in syntax: [StableID: SyntaxNode],
        rules: LanguageNoiseRules
    ) -> NodeSyntax? {
        var roots: [SyntaxNode] = []
        for id in node.syntaxIDs {
            guard let root = syntax[id] else { return nil }
            roots.append(root)
        }
        let outermost = roots.filter { root in
            !roots.contains { other in other.id != root.id && Self.contains(other.range, root.range) }
        }
        var result = NodeSyntax()
        for root in outermost
            .sorted(by: { ($0.range.start.utf16Offset, $0.id) < ($1.range.start.utf16Offset, $1.id) })
        {
            Self.collectSyntax(of: root, parent: nil, rules: rules, into: &result)
        }
        return result
    }

    private static func contains(_ outer: SourceRange, _ inner: SourceRange) -> Bool {
        outer.start <= inner.start && inner.end <= outer.end
    }

    static func tokens(of node: SyntaxNode, rules: LanguageNoiseRules) -> [Token] {
        var result = NodeSyntax()
        collectSyntax(of: node, parent: nil, rules: rules, into: &result)
        return result.tokens
    }

    private static let terminatedStatements: Set<String> = [
        "break_statement", "continue_statement", "debugger_statement", "do_statement", "export_statement",
        "expression_statement", "import_statement", "lexical_declaration", "return_statement", "throw_statement",
        "type_alias_declaration", "variable_declaration"
    ]

    private static let statementLists: Set<String> = ["block", "source_file", "statement_block", "statements"]

    private static func collectSyntax(
        of node: SyntaxNode,
        parent: SyntaxNode?,
        rules: LanguageNoiseRules,
        into result: inout NodeSyntax
    ) {
        if rules.commentKinds.contains(node.kind) {
            return
        }
        if rules.literalKinds.contains(node.kind) {
            if let text = literalToken(of: node) {
                result.tokens.append(Token(text, kind: node.kind, role: .literal))
            }
            return
        }
        let isStatementBoundary = node.kind.hasSuffix("_statement") || node.kind.hasSuffix("_declaration")
            || statementLists.contains(node.kind) || node.kind == "else_clause"
        if isStatementBoundary {
            result.statementBoundaries.append(.start(kind: node.kind, field: node.fieldName))
        }
        defer {
            if isStatementBoundary {
                result.statementBoundaries.append(.end)
            }
        }
        if node.children.isEmpty {
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let terminator = text == ";" && !node.isNamed && parent.map { parent in
                parent.fieldName != "initializer"
                    && (terminatedStatements.contains(parent.kind) || statementLists.contains(parent.kind))
            } == true
            result.tokens.append(Token(text, kind: node.kind, role: terminator ? .statementTerminator : .syntax))
            return
        }
        let tupleComma = singletonTupleComma(in: node, rules: rules)
        for index in node.children.indices {
            if index == tupleComma {
                result.tokens.append(Token(Self.tupleComma, kind: ","))
            } else {
                collectSyntax(of: node.children[index], parent: node, rules: rules, into: &result)
            }
        }
    }

    /// A literal's text as one token, or nil for JSX text that renders nothing.
    static func literalToken(of node: SyntaxNode) -> String? {
        guard node.kind == "jsx_text" else { return node.text }
        let rendered = renderedJSXText(node.text)
        return rendered.isEmpty ? nil : rendered
    }

    /// JSX text as React renders it: tabs become spaces, whitespace touching a line break is dropped, lines left
    /// empty disappear, and the rest join with one space. Spaces within a line stay.
    static func renderedJSXText(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\t", with: " ") }
        let lastNonEmpty = lines.lastIndex { $0.contains { $0 != " " } }
        var rendered = ""
        for (index, line) in lines.enumerated() {
            var trimmed = Substring(line)
            if index > 0 {
                trimmed = trimmed.drop { $0 == " " }
            }
            if index < lines.count - 1 {
                while trimmed.last == " " {
                    trimmed = trimmed.dropLast()
                }
            }
            guard !trimmed.isEmpty else { continue }
            rendered += trimmed
            if index != lastNonEmpty {
                rendered += " "
            }
        }
        return rendered
    }

    /// The index of the comma that makes `node` a one-element tuple: its only comma, right before its closing bracket.
    private static func singletonTupleComma(in node: SyntaxNode, rules: LanguageNoiseRules) -> Int? {
        guard rules.singletonTupleKinds.contains(node.kind) else { return nil }
        let significant = node.children.indices.filter { !rules.commentKinds.contains(node.children[$0].kind) }
        let commas = significant.filter { node.children[$0].children.isEmpty && node.children[$0].text == "," }
        guard commas.count == 1, let comma = commas.first,
              let position = significant.firstIndex(of: comma), position + 1 < significant.count,
              [")", "]"].contains(node.children[significant[position + 1]].text)
        else { return nil }
        return comma
    }

    private static func index(_ body: SyntaxNode?) -> [StableID: SyntaxNode] {
        guard let body else { return [:] }
        return Dictionary(([body] + body.descendants).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
