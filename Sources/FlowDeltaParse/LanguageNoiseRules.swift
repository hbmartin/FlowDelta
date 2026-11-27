import FlowDeltaCore

/// Which syntax a language lets a change add or remove without changing behavior.
public struct LanguageNoiseRules: Hashable, Sendable {
    /// Leaf and subtree kinds that are comments.
    public let commentKinds: Set<String>
    /// Tokens that are optional wherever they appear, such as a statement-ending `;`.
    public let optionalTokens: Set<String>
    /// Receivers that are optional before `.`. No built-in language has one: a parameter or local can shadow a
    /// member, so Swift's `self.x` and `x` can name different values, and `this.` and `self.` reach members in
    /// scripts and Python.
    public let optionalReceivers: Set<String>
    /// Whether a trailing `,` before a closing bracket is optional. A comma right after an opening bracket or another
    /// comma is an array hole and is never optional.
    public let allowsTrailingCommas: Bool
    /// Literal kinds compared by their exact text as one token, so whitespace and punctuation inside a string are
    /// never noise.
    public let literalKinds: Set<String>
    /// Kinds whose only comma, written right before the closing bracket, makes a one-element tuple, such as
    /// Python's `(x,)` and `a[x,]`. That comma is never optional.
    public let singletonTupleKinds: Set<String>

    public init(
        commentKinds: Set<String>,
        optionalTokens: Set<String>,
        optionalReceivers: Set<String>,
        allowsTrailingCommas: Bool,
        literalKinds: Set<String> = [],
        singletonTupleKinds: Set<String> = []
    ) {
        self.commentKinds = commentKinds
        self.optionalTokens = optionalTokens
        self.optionalReceivers = optionalReceivers
        self.allowsTrailingCommas = allowsTrailingCommas
        self.literalKinds = literalKinds
        self.singletonTupleKinds = singletonTupleKinds
    }
}

public extension LanguageProfile {
    /// The noise rules of this profile's language.
    var noise: LanguageNoiseRules {
        switch language {
        case .swift:
            // `self.x` reads the property even where a parameter or local `x` shadows it, so `self.` stays.
            LanguageNoiseRules(
                commentKinds: ["comment", "multiline_comment"],
                optionalTokens: [";"],
                optionalReceivers: [],
                allowsTrailingCommas: true,
                literalKinds: [
                    "line_string_literal",
                    "multi_line_string_literal",
                    "raw_string_literal",
                    "regex_literal"
                ]
            )
        case .typescript, .javascript:
            // `this.reset()` calls a member while `reset()` resolves a lexical or global binding, so `this.` stays.
            LanguageNoiseRules(
                commentKinds: ["comment"],
                optionalTokens: [";"],
                optionalReceivers: [],
                allowsTrailingCommas: true,
                // JSX text is content: it compares as it renders.
                literalKinds: ["string", "template_string", "regex", "jsx_text"]
            )
        case .python:
            // Python's `self.` is how an instance attribute is reached, so it is never optional.
            LanguageNoiseRules(
                commentKinds: ["comment"],
                optionalTokens: [";"],
                optionalReceivers: [],
                allowsTrailingCommas: true,
                literalKinds: ["string", "concatenated_string"],
                singletonTupleKinds: ["tuple", "tuple_pattern", "subscript"]
            )
        case .go:
            LanguageNoiseRules(
                commentKinds: ["comment"],
                optionalTokens: [";"],
                optionalReceivers: [],
                allowsTrailingCommas: true,
                literalKinds: ["interpreted_string_literal", "raw_string_literal", "rune_literal"]
            )
        }
    }
}
