import FlowDeltaCore
import Foundation

public struct LanguageProfile: Hashable, Sendable {
    public let language: SourceLanguage
    public let statementContainers: Set<String>
    public let conditionKinds: Set<String>
    public let loopKinds: Set<String>
    public let switchKinds: Set<String>
    public let returnKinds: Set<String>
    public let throwKinds: Set<String>
    public let breakKinds: Set<String>
    public let continueKinds: Set<String>
    public let tryKinds: Set<String>
    public let catchKinds: Set<String>
    public let finallyKinds: Set<String>
    public let callKinds: Set<String>
    public let identifierKinds: Set<String>

    public static func profile(for language: SourceLanguage) -> LanguageProfile {
        switch language {
        case .swift:
            LanguageProfile(
                language: .swift,
                statementContainers: ["statements"],
                conditionKinds: ["if_statement", "guard_statement"],
                loopKinds: ["for_statement", "while_statement", "repeat_while_statement"],
                switchKinds: ["switch_statement"],
                returnKinds: ["control_transfer_statement"],
                throwKinds: ["control_transfer_statement"],
                breakKinds: ["control_transfer_statement"],
                continueKinds: ["control_transfer_statement"],
                tryKinds: ["do_statement"],
                catchKinds: ["catch_block"],
                finallyKinds: [],
                callKinds: ["call_expression"],
                identifierKinds: ["simple_identifier"]
            )
        case .typescript, .javascript:
            LanguageProfile(
                language: language,
                statementContainers: ["program", "statement_block"],
                conditionKinds: ["if_statement", "ternary_expression"],
                loopKinds: ["for_statement", "for_in_statement", "while_statement", "do_statement"],
                switchKinds: ["switch_statement"],
                returnKinds: ["return_statement"],
                throwKinds: ["throw_statement"],
                breakKinds: ["break_statement"],
                continueKinds: ["continue_statement"],
                tryKinds: ["try_statement"],
                catchKinds: ["catch_clause"],
                finallyKinds: ["finally_clause"],
                callKinds: ["call_expression", "new_expression"],
                identifierKinds: ["identifier", "property_identifier", "shorthand_property_identifier"]
            )
        case .python:
            LanguageProfile(
                language: .python,
                statementContainers: ["module", "block"],
                conditionKinds: ["if_statement", "conditional_expression"],
                loopKinds: ["for_statement", "while_statement"],
                switchKinds: ["match_statement"],
                returnKinds: ["return_statement"],
                throwKinds: ["raise_statement"],
                breakKinds: ["break_statement"],
                continueKinds: ["continue_statement"],
                tryKinds: ["try_statement"],
                catchKinds: ["except_clause"],
                finallyKinds: ["finally_clause"],
                callKinds: ["call"],
                identifierKinds: ["identifier"]
            )
        case .go:
            LanguageProfile(
                language: .go,
                statementContainers: ["source_file", "block"],
                conditionKinds: ["if_statement"],
                loopKinds: ["for_statement"],
                switchKinds: ["expression_switch_statement", "type_switch_statement", "select_statement"],
                returnKinds: ["return_statement"],
                throwKinds: [],
                breakKinds: ["break_statement"],
                continueKinds: ["continue_statement"],
                tryKinds: [],
                catchKinds: [],
                finallyKinds: [],
                callKinds: ["call_expression"],
                identifierKinds: ["identifier", "field_identifier", "package_identifier"]
            )
        }
    }
}
