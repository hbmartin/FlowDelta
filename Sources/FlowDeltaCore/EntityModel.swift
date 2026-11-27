import Foundation

public enum EntityKind: String, Codable, CaseIterable, Sendable {
    case function
    case method
    case initializer
    case deinitializer
    case subscriptDeclaration
    case operatorDeclaration
    case type
    case typeExtension
    case topLevelBinding
}

public struct SourceEntity: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let kind: EntityKind
    public let name: String
    public let qualifiedName: String
    public let path: String
    public let range: SourceRange
    public let body: SyntaxNode
    /// The callable's receiver, parameter and named-result names, read from its syntax. Nil when the extractor
    /// does not read them for the language, and in 0.2 reports; data flow then parses `qualifiedName`.
    public let parameterNames: [String]?
    /// The callable's named results, which a bare `return` reads, such as Go's `(n int, err error)`. Nil when the
    /// callable has none or the extractor does not read them for the language.
    public let resultNames: [String]?
    /// The declaration's tokens outside its name, body and comments, such as `async def ( x = 1 ) :`: keywords,
    /// modifiers, parameters, results and inheritance. A rename keeps them. Empty when the declaration is its own
    /// body, and nil in reports made before 0.3.2.
    public let declarationHeader: [String]?

    public init(
        id: StableID,
        kind: EntityKind,
        name: String,
        qualifiedName: String,
        path: String,
        range: SourceRange,
        body: SyntaxNode,
        parameterNames: [String]? = nil,
        resultNames: [String]? = nil,
        declarationHeader: [String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.qualifiedName = qualifiedName
        self.path = path
        self.range = range
        self.body = body
        self.parameterNames = parameterNames
        self.resultNames = resultNames
        self.declarationHeader = declarationHeader
    }

    /// Whether `other` declares the same header, or either header is unknown.
    public func hasSameDeclarationHeader(as other: SourceEntity) -> Bool {
        guard let declarationHeader, let otherHeader = other.declarationHeader else { return true }
        return declarationHeader == otherHeader
    }
}

public enum MatchTier: String, Codable, CaseIterable, Sendable {
    case exactName
    case structuralHash
    case fuzzyTokens
    case gumTree
}

public struct MatchConfidence: Codable, Hashable, Sendable {
    public let tier: MatchTier
    public let score: Double

    public init(tier: MatchTier, score: Double) {
        precondition((0 ... 1).contains(score))
        self.tier = tier
        self.score = score
    }
}

public struct EntityMatch: Codable, Hashable, Sendable {
    public let old: SourceEntity
    public let new: SourceEntity
    public let confidence: MatchConfidence

    public init(old: SourceEntity, new: SourceEntity, confidence: MatchConfidence) {
        self.old = old
        self.new = new
        self.confidence = confidence
    }
}

public enum EntityChangeKind: String, Codable, CaseIterable, Sendable {
    case added
    case removed
    case modified
    case moved
    case renamed
    case unchanged
}

public struct EntityChange: Codable, Hashable, Sendable {
    public let kind: EntityChangeKind
    public let old: SourceEntity?
    public let new: SourceEntity?
    public let confidence: MatchConfidence?

    public init(
        kind: EntityChangeKind,
        old: SourceEntity?,
        new: SourceEntity?,
        confidence: MatchConfidence?
    ) {
        self.kind = kind
        self.old = old
        self.new = new
        self.confidence = confidence
    }
}
