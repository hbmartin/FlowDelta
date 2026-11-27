import FlowDeltaCore

/// Which syntax a language lets a change add or remove without changing behavior.
public struct LanguageNoiseRules: Hashable, Sendable {
    /// Leaf and subtree kinds that are comments.
    public let commentKinds: Set<String>
    /// Tokens that are optional wherever they appear, such as a statement-ending `;`.
    public let optionalTokens: Set<String>
    /// Receivers that are optional before `.`, such as Swift's `self`.
    public let optionalReceivers: Set<String>
    /// Whether a trailing `,` before a closing bracket is optional.
    public let allowsTrailingCommas: Bool

    public init(
        commentKinds: Set<String>,
        optionalTokens: Set<String>,
        optionalReceivers: Set<String>,
        allowsTrailingCommas: Bool
    ) {
        self.commentKinds = commentKinds
        self.optionalTokens = optionalTokens
        self.optionalReceivers = optionalReceivers
        self.allowsTrailingCommas = allowsTrailingCommas
    }
}

public extension LanguageProfile {
    /// The noise rules of this profile's language.
    var noise: LanguageNoiseRules {
        switch language {
        case .swift:
            LanguageNoiseRules(
                commentKinds: ["comment", "multiline_comment"],
                optionalTokens: [";"],
                optionalReceivers: ["self"],
                allowsTrailingCommas: true
            )
        case .typescript, .javascript:
            LanguageNoiseRules(
                commentKinds: ["comment"],
                optionalTokens: [";"],
                optionalReceivers: ["this"],
                allowsTrailingCommas: true
            )
        case .python:
            // Python's `self.` is how an instance attribute is reached, so it is never optional.
            LanguageNoiseRules(
                commentKinds: ["comment"],
                optionalTokens: [";"],
                optionalReceivers: [],
                allowsTrailingCommas: true
            )
        case .go:
            LanguageNoiseRules(
                commentKinds: ["comment"],
                optionalTokens: [";"],
                optionalReceivers: [],
                allowsTrailingCommas: true
            )
        }
    }
}
