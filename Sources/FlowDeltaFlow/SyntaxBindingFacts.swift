import FlowDeltaCore
import FlowDeltaParse

/// Reads the names a flow node defines and uses from its syntax, using a language's binding rules.
struct SyntaxBindingFacts {
    private let rules: LanguageBindingRules
    private let profile: LanguageProfile
    private let syntaxByID: [StableID: SyntaxNode]
    private let parentByID: [StableID: SyntaxNode]
    /// Names that `global` or `nonlocal` statements anywhere in the body declare non-local.
    let nonLocalNames: Set<String>

    private static let bodyFields: Set<String> = ["body", "consequence", "alternative"]
    private static let clauseKinds: Set<String> = [
        "case_clause", "expression_case", "default_case", "type_case", "communication_case", "elif_clause",
        "else_clause"
    ]
    private static let caseFields: Set<String> = ["value", "communication", "guard", "pattern", "alias"]

    init(entity: SourceEntity, profile: LanguageProfile, rules: LanguageBindingRules) {
        self.rules = rules
        self.profile = profile
        let all = [entity.body] + entity.body.descendants
        syntaxByID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var parents: [StableID: SyntaxNode] = [:]
        for node in all {
            for child in node.children {
                parents[child.id] = node
            }
        }
        parentByID = parents
        nonLocalNames = Set(all.filter { rules.nonLocalKinds.contains($0.kind) }.flatMap { statement in
            statement.descendants.filter { rules.identifierKinds.contains($0.kind) }.map(\.text)
        })
    }

    func facts(for node: FlowNode) -> LexicalFacts {
        guard !node.isSynthetic else { return .empty }
        var walker = BindingWalker(rules: rules)
        for root in node.syntaxIDs.compactMap({ syntaxByID[$0] }) {
            switch node.kind {
            case .condition:
                walker.walkHeader(of: header(containing: root), skipping: isBody)
            case .switchCase:
                for child in root.children
                    where Self.caseFields.contains(child.fieldName ?? "") || child.kind == "case_pattern"
                {
                    walker.walk(child)
                }
            case .catchBlock:
                for child in root.children where !isBody(child) {
                    walker.walk(child)
                }
            case .basicBlock where profile.loopKinds.contains(root.kind):
                // The node after a loop carries the loop's syntax but runs none of it.
                continue
            default:
                walker.walk(root)
            }
        }
        let ignored = rules.ignoredNames
        return LexicalFacts(
            definitions: walker.definitions.subtracting(ignored).subtracting(nonLocalNames),
            uses: walker.uses.subtracting(ignored)
        )
    }

    /// The statement whose header holds `syntax`: a condition, loop or switch, or `syntax` itself.
    private func header(containing syntax: SyntaxNode) -> SyntaxNode {
        let headers = profile.conditionKinds.union(profile.loopKinds).union(profile.switchKinds)
        if headers.contains(syntax.kind) {
            return syntax
        }
        if let parent = parentByID[syntax.id], headers.contains(parent.kind) {
            return parent
        }
        return syntax
    }

    private func isBody(_ child: SyntaxNode) -> Bool {
        Self.bodyFields.contains(child.fieldName ?? "")
            || profile.statementContainers.contains(child.kind)
            || Self.clauseKinds.contains(child.kind)
    }
}

/// Collects definitions and uses from syntax by a language's binding rules.
struct BindingWalker {
    let rules: LanguageBindingRules
    private(set) var definitions: Set<String> = []
    private(set) var uses: Set<String> = []

    mutating func walk(_ node: SyntaxNode) {
        let kind = node.kind
        if rules.identifierKinds.contains(kind) {
            uses.insert(node.text)
        } else if kind == "comment" || rules.nonLocalKinds.contains(kind) {
            return
        } else if rules.scopedKinds.contains(kind) {
            walkScoped(node)
        } else if let field = rules.targetFields[kind] {
            walkAssignment(node, targetField: field)
        } else {
            walkDeclarationOrChildren(node)
        }
    }

    /// Declarations, aliases, member accesses and keyed elements, or else every child.
    private mutating func walkDeclarationOrChildren(_ node: SyntaxNode) {
        let kind = node.kind
        if rules.nestedDeclarationKinds.contains(kind) {
            let declaration = node.firstChild(fieldName: "definition") ?? node
            if let name = declaration.firstChild(fieldName: "name"), rules.identifierKinds.contains(name.kind) {
                definitions.insert(name.text)
            }
        } else if rules.declarationKinds.contains(kind) {
            for child in node.children where !isType(child) {
                if child.fieldName == "name", rules.identifierKinds.contains(child.kind) {
                    definitions.insert(child.text)
                } else {
                    walk(child)
                }
            }
        } else if rules.aliasKinds.contains(kind) {
            bind(node, alsoUse: false)
        } else if let member = rules.memberFields[kind] {
            for child in node.children where child.fieldName != member {
                walk(child)
            }
        } else if rules.keyedKinds.contains(kind) {
            walkKeyed(node)
        } else {
            walkChildren(of: node)
        }
    }

    /// Walks children, binding an identifier that follows an `as` token (`except E as e`, `import a as b`).
    private mutating func walkChildren(of node: SyntaxNode) {
        var afterAs = false
        for child in node.children where !isType(child) {
            if afterAs, rules.identifierKinds.contains(child.kind) {
                definitions.insert(child.text)
            } else {
                walk(child)
            }
            afterAs = !child.isNamed && child.text == "as"
        }
    }

    /// Walks a condition, loop or switch header: its binding rules apply, but its bodies are separate nodes.
    mutating func walkHeader(of statement: SyntaxNode, skipping isBody: (SyntaxNode) -> Bool) {
        if let field = rules.targetFields[statement.kind] {
            walkAssignment(statement, targetField: field, skipping: isBody)
        } else {
            for child in statement.children where !isBody(child) && !isType(child) {
                walk(child)
            }
        }
    }

    private mutating func walkAssignment(
        _ node: SyntaxNode,
        targetField field: String,
        skipping isSkipped: (SyntaxNode) -> Bool = { _ in false }
    ) {
        let target = field.isEmpty ? node.children.first(where: \.isNamed) : node.firstChild(fieldName: field)
        let operatorText = node.firstChild(fieldName: "operator")?.text
            ?? node.children.first { !$0.isNamed && $0.text.hasSuffix("=") }?.text
        let compound = rules.compoundKinds.contains(node.kind)
            || (rules.operatorAssignmentKinds.contains(node.kind) && operatorText != "=" && operatorText != ":=")
        for child in node.children where !isType(child) && !isSkipped(child) {
            if child.id == target?.id {
                bind(child, alsoUse: compound)
            } else {
                walk(child)
            }
        }
    }

    /// Binds the identifiers a target names; member and index targets only read their operands.
    private mutating func bind(_ target: SyntaxNode, alsoUse: Bool) {
        if rules.identifierKinds.contains(target.kind) {
            definitions.insert(target.text)
            if alsoUse {
                uses.insert(target.text)
            }
        } else if rules.targetGroupKinds.contains(target.kind) || rules.aliasKinds.contains(target.kind) {
            for child in target.children where child.isNamed {
                bind(child, alsoUse: alsoUse)
            }
        } else {
            walk(target)
        }
    }

    /// A keyword argument's or struct field's key is a name, not a variable; its value is read.
    private mutating func walkKeyed(_ node: SyntaxNode) {
        let named = node.children.filter(\.isNamed)
        for (index, child) in named.enumerated() {
            let isKey = child.fieldName == "name" || (index == 0 && named.count > 1 && isBareIdentifier(child))
            if !isKey {
                walk(child)
            }
        }
    }

    private func isBareIdentifier(_ node: SyntaxNode) -> Bool {
        if rules.identifierKinds.contains(node.kind) {
            return true
        }
        let named = node.children.filter(\.isNamed)
        return named.count == 1 && isBareIdentifier(named[0])
    }

    /// A lambda, comprehension or function literal reads outer names but keeps the names it binds.
    private mutating func walkScoped(_ node: SyntaxNode) {
        var inner = BindingWalker(rules: rules)
        var bound: Set<String> = []
        for child in node.children where !isType(child) {
            if rules.scopedBindingFields.contains(child.fieldName ?? "") {
                bound
                    .formUnion(([child] + child.descendants).filter { rules.identifierKinds.contains($0.kind) }
                        .map(\.text))
            } else {
                inner.walk(child)
            }
        }
        uses.formUnion(inner.uses.subtracting(inner.definitions).subtracting(bound))
    }

    private func isType(_ node: SyntaxNode) -> Bool {
        rules.typeFields.contains(node.fieldName ?? "")
    }
}
