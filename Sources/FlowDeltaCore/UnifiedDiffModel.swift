import Foundation

public struct DiffLineSpan: Codable, Hashable, Sendable {
    public let start: Int
    public let count: Int

    public init(start: Int, count: Int) {
        precondition(start >= 0)
        precondition(count >= 0)
        self.start = start
        self.count = count
    }
}

public struct UnifiedDiffHunk: Codable, Hashable, Sendable {
    public let oldLines: DiffLineSpan
    public let newLines: DiffLineSpan
    public let context: String
    public let lines: [String]

    public init(
        oldLines: DiffLineSpan,
        newLines: DiffLineSpan,
        context: String,
        lines: [String]
    ) {
        self.oldLines = oldLines
        self.newLines = newLines
        self.context = context
        self.lines = lines
    }
}

public struct UnifiedFilePatch: Codable, Hashable, Sendable {
    public let oldPath: String?
    public let newPath: String?
    public let hunks: [UnifiedDiffHunk]

    public init(oldPath: String?, newPath: String?, hunks: [UnifiedDiffHunk]) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.hunks = hunks
    }
}
