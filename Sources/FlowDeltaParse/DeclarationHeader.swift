import FlowDeltaCore

/// Reads a declaration's header: its tokens outside its name, body and comments.
enum DeclarationHeader {
    /// The header tokens of `declaration`, or none when the declaration is its own body. Literals keep their exact
    /// text, so a changed default value inside quotes changes the header.
    static func tokens(
        of declaration: SyntaxNode,
        name: SyntaxNode?,
        body: SyntaxNode,
        rules: LanguageNoiseRules
    ) -> [String] {
        guard body.id != declaration.id else { return [] }
        func tokens(_ node: SyntaxNode) -> [String] {
            if node.id == body.id || node.id == name?.id || rules.commentKinds.contains(node.kind) {
                return []
            }
            if rules.literalKinds.contains(node.kind) {
                return [node.text]
            }
            if node.children.isEmpty {
                let token = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return token.isEmpty ? [] : [token]
            }
            return node.children.flatMap(tokens)
        }
        return tokens(declaration)
    }
}
