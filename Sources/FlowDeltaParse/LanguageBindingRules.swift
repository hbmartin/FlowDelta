import FlowDeltaCore

/// Which syntax binds names in a language, for def-use read from syntax trees instead of text.
public struct LanguageBindingRules: Hashable, Sendable {
    /// Leaf kinds that name a variable.
    public let identifierKinds: Set<String>
    /// Names that never hold a value, such as Go's blank identifier.
    public let ignoredNames: Set<String>
    /// Statement or clause kinds whose named field holds assignment targets, such as `assignment` → `left`.
    public let targetFields: [String: String]
    /// Kinds that read their target before writing it, such as `x += 1` and `i++`.
    public let compoundKinds: Set<String>
    /// Kinds whose `operator` child decides compoundness: anything but `=` and `:=` reads the target.
    public let operatorAssignmentKinds: Set<String>
    /// Declaration kinds whose `name` fields are bound, such as Go's `var_spec`.
    public let declarationKinds: Set<String>
    /// Kinds whose identifiers are all bound, such as Python's `as_pattern_target`.
    public let aliasKinds: Set<String>
    /// Kinds that group targets, so their identifiers are bound too.
    public let targetGroupKinds: Set<String>
    /// Statements naming variables that are not local, such as `global x`.
    public let nonLocalKinds: Set<String>
    /// Expressions with their own scope: names they bind stay inside, the names they read are uses.
    public let scopedKinds: Set<String>
    /// The fields of a scoped expression that bind its names, such as a lambda's `parameters`.
    public let scopedBindingFields: Set<String>
    /// Nested declarations that bind their `name` and are otherwise skipped.
    public let nestedDeclarationKinds: Set<String>
    /// Member accesses whose named field is a member name, not a variable, such as `attribute` → `attribute`.
    public let memberFields: [String: String]
    /// Kinds whose leading key is a name, not a variable, such as `f(key=value)` and `T{Field: value}`.
    public let keyedKinds: Set<String>
    /// Fields that hold types, which are never data.
    public let typeFields: Set<String>
    /// Assignment kinds that write their target only when this field holds a value, such as Python's `x: int`.
    public let valueFields: [String: String]
    /// Comprehension clauses that bind loop targets. The first clause's `right` runs in the enclosing scope, and an
    /// assignment expression anywhere in the comprehension binds there too.
    public let comprehensionClauseKinds: Set<String>
    /// Literal kinds whose keys are evaluated when their `type` field has one of these kinds, such as a Go map.
    public let evaluatedKeyLiterals: [String: Set<String>]
    /// Return statements that read the callable's named results when they return no expression.
    public let bareReturnKinds: Set<String>

    /// The names one parameter declares: a bare identifier, its `name` fields, or else the first identifier
    /// outside its type and default, as in `*args`, `**kwargs` and `name: type`.
    public func declaredNames(ofParameter parameter: SyntaxNode) -> [String] {
        if identifierKinds.contains(parameter.kind) {
            return [parameter.text]
        }
        let named = parameter.children.filter { $0.fieldName == "name" && identifierKinds.contains($0.kind) }
        if !named.isEmpty {
            return named.map(\.text)
        }
        func first(_ node: SyntaxNode) -> String? {
            for child in node.children where child.fieldName != "type" && child.fieldName != "value" {
                if identifierKinds.contains(child.kind) {
                    return child.text
                }
                if let found = first(child) {
                    return found
                }
            }
            return nil
        }
        return first(parameter).map { [$0] } ?? []
    }
}

public extension LanguageProfile {
    /// How the language binds names, or nil when data flow reads its text instead.
    var binding: LanguageBindingRules? {
        switch language {
        case .swift, .typescript, .javascript:
            nil
        case .python:
            LanguageBindingRules(
                identifierKinds: ["identifier"],
                ignoredNames: [],
                targetFields: [
                    "assignment": "left", "augmented_assignment": "left", "for_statement": "left",
                    "for_in_clause": "left", "named_expression": "name"
                ],
                compoundKinds: ["augmented_assignment"],
                operatorAssignmentKinds: [],
                declarationKinds: [],
                aliasKinds: ["as_pattern_target"],
                targetGroupKinds: [
                    "pattern_list", "tuple_pattern", "list_pattern", "list_splat_pattern", "parenthesized_expression",
                    "expression_list", "tuple", "list"
                ],
                nonLocalKinds: ["global_statement", "nonlocal_statement"],
                scopedKinds: [
                    "lambda", "list_comprehension", "set_comprehension", "dictionary_comprehension",
                    "generator_expression"
                ],
                scopedBindingFields: ["parameters"],
                nestedDeclarationKinds: ["function_definition", "class_definition", "decorated_definition"],
                memberFields: ["attribute": "attribute"],
                keyedKinds: ["keyword_argument"],
                typeFields: ["type", "return_type"],
                valueFields: ["assignment": "right"],
                comprehensionClauseKinds: ["for_in_clause"],
                evaluatedKeyLiterals: [:],
                bareReturnKinds: []
            )
        case .go:
            LanguageBindingRules(
                identifierKinds: ["identifier"],
                ignoredNames: ["_"],
                targetFields: [
                    "short_var_declaration": "left", "assignment_statement": "left", "range_clause": "left",
                    "inc_statement": "", "dec_statement": ""
                ],
                compoundKinds: ["inc_statement", "dec_statement"],
                operatorAssignmentKinds: ["assignment_statement"],
                declarationKinds: ["var_spec", "const_spec"],
                aliasKinds: [],
                targetGroupKinds: ["expression_list"],
                nonLocalKinds: [],
                scopedKinds: ["func_literal"],
                scopedBindingFields: ["parameters", "result"],
                nestedDeclarationKinds: [],
                memberFields: [:],
                keyedKinds: ["keyed_element"],
                typeFields: ["type"],
                valueFields: [:],
                comprehensionClauseKinds: [],
                evaluatedKeyLiterals: ["composite_literal": ["map_type"]],
                bareReturnKinds: ["return_statement"]
            )
        }
    }
}
