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

    public init(
        id: StableID,
        kind: EntityKind,
        name: String,
        qualifiedName: String,
        path: String,
        range: SourceRange,
        body: SyntaxNode
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.qualifiedName = qualifiedName
        self.path = path
        self.range = range
        self.body = body
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
