import Foundation

public enum SourceLanguage: String, Codable, CaseIterable, Sendable {
    case swift
    case typescript
    case javascript
    case python
    case go

    public init?(path: String) {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift": self = .swift
        case "ts", "tsx", "mts", "cts": self = .typescript
        case "js", "jsx", "mjs", "cjs": self = .javascript
        case "py", "pyi": self = .python
        case "go": self = .go
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .typescript: "TypeScript"
        case .javascript: "JavaScript"
        case .python: "Python"
        case .go: "Go"
        }
    }

    // Whether FlowDelta builds def-use graphs, and so data context and data slices, for this language.
}

public struct SourceLocation: Codable, Hashable, Sendable, Comparable {
    public let utf8Offset: Int
    public let utf16Offset: Int
    public let line: Int
    public let utf16Column: Int

    public init(utf8Offset: Int, utf16Offset: Int, line: Int, utf16Column: Int) {
        precondition(utf8Offset >= 0)
        precondition(utf16Offset >= 0)
        precondition(line >= 0)
        precondition(utf16Column >= 0)
        self.utf8Offset = utf8Offset
        self.utf16Offset = utf16Offset
        self.line = line
        self.utf16Column = utf16Column
    }

    public static func < (lhs: SourceLocation, rhs: SourceLocation) -> Bool {
        lhs.utf16Offset < rhs.utf16Offset
    }
}

public struct SourceRange: Codable, Hashable, Sendable {
    public let start: SourceLocation
    public let end: SourceLocation

    public init(start: SourceLocation, end: SourceLocation) {
        precondition(start <= end)
        self.start = start
        self.end = end
    }

    public var utf8Range: Range<Int> {
        start.utf8Offset ..< end.utf8Offset
    }

    public var utf16Range: Range<Int> {
        start.utf16Offset ..< end.utf16Offset
    }

    public var isEmpty: Bool {
        start == end
    }

    public func contains(utf16Offset: Int) -> Bool {
        utf16Range.contains(utf16Offset)
    }
}

public struct RevisionIdentity: Codable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }
}

public struct SourceSnapshot: Codable, Hashable, Sendable {
    public let path: String
    public let revision: RevisionIdentity
    public let language: SourceLanguage
    public let text: String

    public init(path: String, revision: RevisionIdentity, language: SourceLanguage, text: String) {
        self.path = path
        self.revision = revision
        self.language = language
        self.text = text
    }
}

public struct FileComparison: Codable, Hashable, Sendable {
    public let old: SourceSnapshot?
    public let new: SourceSnapshot?
    public let unifiedDiff: String?

    public init(old: SourceSnapshot?, new: SourceSnapshot?, unifiedDiff: String? = nil) {
        precondition(old != nil || new != nil)
        self.old = old
        self.new = new
        self.unifiedDiff = unifiedDiff
    }

    public var path: String {
        new?.path ?? old?.path ?? ""
    }

    public var language: SourceLanguage {
        new?.language ?? old?.language ?? SourceLanguage(path: path) ?? .swift
    }
}

public struct RevisionComparison: Codable, Hashable, Sendable {
    public let base: RevisionIdentity
    public let target: RevisionIdentity
    public let files: [FileComparison]

    public init(base: RevisionIdentity, target: RevisionIdentity, files: [FileComparison]) {
        self.base = base
        self.target = target
        self.files = files.sorted { $0.path < $1.path }
    }
}
