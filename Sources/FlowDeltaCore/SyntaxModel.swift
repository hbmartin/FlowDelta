import Foundation

public struct SyntaxNode: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let kind: String
    public let fieldName: String?
    public let range: SourceRange
    public let text: String
    public let isNamed: Bool
    public let isMissing: Bool
    public let hasError: Bool
    public let children: [SyntaxNode]

    public init(
        id: StableID,
        kind: String,
        fieldName: String? = nil,
        range: SourceRange,
        text: String,
        isNamed: Bool = true,
        isMissing: Bool = false,
        hasError: Bool = false,
        children: [SyntaxNode] = []
    ) {
        self.id = id
        self.kind = kind
        self.fieldName = fieldName
        self.range = range
        self.text = text
        self.isNamed = isNamed
        self.isMissing = isMissing
        self.hasError = hasError
        self.children = children
    }

    public var descendants: [SyntaxNode] {
        [self] + children.flatMap(\.descendants)
    }

    public var height: Int {
        1 + (children.map(\.height).max() ?? 0)
    }

    public var normalizedTokens: [String] {
        if children.isEmpty {
            let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty || kind == "comment" ? [] : [token]
        }
        return children.flatMap(\.normalizedTokens)
    }

    public var structuralDigest: String {
        let body: String
        if children.isEmpty {
            let token = kind == "comment"
                ? ""
                : text.trimmingCharacters(in: .whitespacesAndNewlines)
            body = "\(kind):\(token)"
        } else {
            body = "\(kind)[\(children.map(\.structuralDigest).joined(separator: ","))]"
        }
        return StableDigest.hex(body)
    }

    public func firstChild(fieldName: String) -> SyntaxNode? {
        children.first { $0.fieldName == fieldName }
    }

    public func firstDescendant(kind: String) -> SyntaxNode? {
        if self.kind == kind { return self }
        return children.lazy.compactMap { $0.firstDescendant(kind: kind) }.first
    }
}

public struct SyntaxTree: Codable, Hashable, Sendable {
    public let snapshot: SourceSnapshot
    public let root: SyntaxNode
    public let errorCount: Int

    public init(snapshot: SourceSnapshot, root: SyntaxNode, errorCount: Int) {
        self.snapshot = snapshot
        self.root = root
        self.errorCount = errorCount
    }
}
