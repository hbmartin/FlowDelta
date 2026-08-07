import Foundation

public enum EditOperationKind: String, Codable, CaseIterable, Sendable {
    case insert
    case delete
    case update
    case move
}

public struct SyntaxMapping: Codable, Hashable, Sendable {
    public let oldID: StableID
    public let newID: StableID
    public let confidence: MatchConfidence

    public init(oldID: StableID, newID: StableID, confidence: MatchConfidence) {
        self.oldID = oldID
        self.newID = newID
        self.confidence = confidence
    }
}

public struct EditOperation: Codable, Hashable, Sendable {
    public let kind: EditOperationKind
    public let oldID: StableID?
    public let newID: StableID?

    public init(kind: EditOperationKind, oldID: StableID?, newID: StableID?) {
        self.kind = kind
        self.oldID = oldID
        self.newID = newID
    }
}

public struct EditScript: Codable, Hashable, Sendable {
    public let mappings: [SyntaxMapping]
    public let operations: [EditOperation]

    public init(mappings: [SyntaxMapping], operations: [EditOperation]) {
        self.mappings = mappings.sorted { ($0.oldID, $0.newID) < ($1.oldID, $1.newID) }
        self.operations = operations
    }
}
