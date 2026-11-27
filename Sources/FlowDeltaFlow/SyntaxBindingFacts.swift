import FlowDeltaCore
import FlowDeltaParse

/// Reads the names a flow node defines and uses from its syntax, using a language's binding rules.
struct SyntaxBindingFacts {
    private let rules: LanguageBindingRules
    private let profile: LanguageProfile
    private let syntaxByID: [StableID: SyntaxNode]
    private let parentByID: [StableID: SyntaxNode]
    /// Names that the function's own `global` or `nonlocal` statements declare non-local. Statements in nested
    /// functions and classes declare names of those scopes.
    let nonLocalNames: Set<String>
    /// The named results a bare `return` reads.
    private let resultNames: Set<String>

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
        var statements: [SyntaxNode] = []
        func collectNonLocal(in node: SyntaxNode) {
            for child in node.children {
                if rules.nonLocalKinds.contains(child.kind) {
                    statements.append(child)
                } else if !rules.nestedDeclarationKinds.contains(child.kind), !rules.scopedKinds.contains(child.kind) {
                    collectNonLocal(in: child)
                }
            }
        }
        collectNonLocal(in: entity.body)
        nonLocalNames = Set(statements.flatMap { statement in
            statement.descendants.filter { rules.identifierKinds.contains($0.kind) }.map(\.text)
        })
        resultNames = Set(entity.resultNames ?? [])
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
                if rules.bareReturnKinds.contains(root.kind), !root.children.contains(where: \.isNamed) {
                    // A bare `return` returns the named results.
                    walker.read(resultNames)
                }
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
    /// Uses that come before any definition of their name in evaluation order, which a closure captures.
    private(set) var freeUses: Set<String> = []

    mutating func walk(_ node: SyntaxNode) {
        let kind = node.kind
        if rules.identifierKinds.contains(kind) {
            use(node.text)
        } else if kind == "comment" || rules.nonLocalKinds.contains(kind) {
            return
        } else if rules.scopedKinds.contains(kind) {
            walkScoped(node)
        } else if let field = rules.targetFields[kind] {
            walkAssignment(node, targetField: field)
        } else if let keyTypes = rules.evaluatedKeyLiterals[kind],
                  let type = node.firstChild(fieldName: "type"), keyTypes.contains(type.kind)
        {
            walkEvaluatedKeys(node)
        } else {
            walkDeclarationOrChildren(node)
        }
    }

    mutating func read(_ names: Set<String>) {
        for name in names.sorted() {
            use(name)
        }
    }

    private mutating func use(_ name: String) {
        uses.insert(name)
        if !definitions.contains(name) {
            freeUses.insert(name)
        }
    }

    private mutating func define(_ name: String) {
        definitions.insert(name)
    }

    /// Declarations, aliases, member accesses and keyed elements, or else every child.
    private mutating func walkDeclarationOrChildren(_ node: SyntaxNode) {
        let kind = node.kind
        if rules.nestedDeclarationKinds.contains(kind) {
            let declaration = node.firstChild(fieldName: "definition") ?? node
            if let name = declaration.firstChild(fieldName: "name"), rules.identifierKinds.contains(name.kind) {
                define(name.text)
            }
        } else if rules.declarationKinds.contains(kind) {
            for child in node.children where !isType(child) {
                if child.fieldName == "name", rules.identifierKinds.contains(child.kind) {
                    define(child.text)
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
                define(child.text)
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
        if let valueField = rules.valueFields[node.kind], node.firstChild(fieldName: valueField) == nil {
            // An annotation without a value, such as `x: int`, writes nothing.
            return
        }
        let target = field.isEmpty ? node.children.first(where: \.isNamed) : node.firstChild(fieldName: field)
        let operatorText = node.firstChild(fieldName: "operator")?.text
            ?? node.children.first { !$0.isNamed && $0.text.hasSuffix("=") }?.text
        let compound = rules.compoundKinds.contains(node.kind)
            || (rules.operatorAssignmentKinds.contains(node.kind) && operatorText != "=" && operatorText != ":=")
        // The value is evaluated before the target is written, so `x := x + 1` reads the previous `x`.
        for child in node.children where !isType(child) && !isSkipped(child) && child.id != target?.id {
            walk(child)
        }
        if let target, !isType(target), !isSkipped(target) {
            bind(target, alsoUse: compound)
        }
    }

    /// Binds the identifiers a target names; member and index targets only read their operands.
    private mutating func bind(_ target: SyntaxNode, alsoUse: Bool) {
        if rules.identifierKinds.contains(target.kind) {
            if alsoUse {
                use(target.text)
            }
            define(target.text)
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

    /// A map literal's keys are values it reads, unlike a struct literal's field labels.
    private mutating func walkEvaluatedKeys(_ node: SyntaxNode) {
        for child in node.children where !isType(child) {
            guard child.fieldName == "body" else {
                walk(child)
                continue
            }
            for element in child.children {
                if rules.keyedKinds.contains(element.kind) {
                    walkChildren(of: element)
                } else {
                    walk(element)
                }
            }
        }
    }

    /// A lambda, comprehension or function literal reads outer names but keeps the names it binds.
    private mutating func walkScoped(_ node: SyntaxNode) {
        if node.children.contains(where: { rules.comprehensionClauseKinds.contains($0.kind) }) {
            walkComprehension(node)
            return
        }
        var inner = BindingWalker(rules: rules)
        var bound: Set<String> = []
        for child in node.children where !isType(child) {
            guard rules.scopedBindingFields.contains(child.fieldName ?? "") else {
                inner.walk(child)
                continue
            }
            let parameters = rules.identifierKinds.contains(child.kind) ? [child] : child.children.filter(\.isNamed)
            for parameter in parameters {
                bound.formUnion(rules.declaredNames(ofParameter: parameter))
                // Default values are evaluated where the lambda or literal is created.
                for value in parameter.children where value.fieldName == "value" {
                    walk(value)
                }
            }
        }
        read(inner.freeUses.subtracting(bound))
    }

    /// A comprehension's loop targets stay inside it. Its first iterable is evaluated in the enclosing scope, and an
    /// assignment expression inside it binds in the enclosing scope (PEP 572).
    private mutating func walkComprehension(_ node: SyntaxNode) {
        var inner = BindingWalker(rules: rules)
        var targets: Set<String> = []
        var isFirstClause = true
        for child in node.children where !isType(child) {
            guard rules.comprehensionClauseKinds.contains(child.kind) else {
                inner.walk(child)
                continue
            }
            let field = rules.targetFields[child.kind] ?? "left"
            for part in child.children where !isType(part) {
                if part.fieldName == field {
                    targets.formUnion(([part] + part.descendants).filter { rules.identifierKinds.contains($0.kind) }
                        .map(\.text))
                } else if isFirstClause, part.fieldName == "right" {
                    walk(part)
                } else {
                    inner.walk(part)
                }
            }
            isFirstClause = false
        }
        read(inner.uses.subtracting(targets))
        for name in inner.definitions.subtracting(targets).sorted() {
            define(name)
        }
    }

    private func isType(_ node: SyntaxNode) -> Bool {
        rules.typeFields.contains(node.fieldName ?? "")
    }
}
