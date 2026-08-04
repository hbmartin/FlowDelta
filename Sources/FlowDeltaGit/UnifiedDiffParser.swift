import FlowDeltaCore
import Foundation

public enum UnifiedDiffParserError: Error, Equatable {
    case malformedHunkHeader(String)
}

public struct UnifiedDiffParser: Sendable {
    public init() {}

    public func parse(_ value: String) throws -> [UnifiedFilePatch] {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var patches: [UnifiedFilePatch] = []
        var oldPath: String?
        var newPath: String?
        var hunks: [UnifiedDiffHunk] = []
        var index = 0

        func finishPatch() {
            if oldPath != nil || newPath != nil || !hunks.isEmpty {
                patches.append(UnifiedFilePatch(oldPath: oldPath, newPath: newPath, hunks: hunks))
            }
            oldPath = nil
            newPath = nil
            hunks = []
        }

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("diff --git ") {
                finishPatch()
            } else if line.hasPrefix("--- ") {
                oldPath = normalizedPath(String(line.dropFirst(4)))
            } else if line.hasPrefix("+++ ") {
                newPath = normalizedPath(String(line.dropFirst(4)))
            } else if line.hasPrefix("@@") {
                let header = try parseHunkHeader(line)
                var body: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].hasPrefix("@@"),
                      !lines[index].hasPrefix("diff --git ")
                {
                    body.append(lines[index])
                    index += 1
                }
                hunks.append(UnifiedDiffHunk(
                    oldLines: header.old,
                    newLines: header.new,
                    context: header.context,
                    lines: body
                ))
                continue
            }
            index += 1
        }
        finishPatch()
        return patches
    }

    private func normalizedPath(_ value: String) -> String? {
        let path = value.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? value
        if path == "/dev/null" {
            return nil
        }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            return String(path.dropFirst(2))
        }
        return path
    }

    private func parseHunkHeader(
        _ line: String
    ) throws -> (old: DiffLineSpan, new: DiffLineSpan, context: String) {
        let expression = try NSRegularExpression(
            pattern: #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: ?(.*))?$"#
        )
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = expression.firstMatch(in: line, range: range), match.range.location != NSNotFound else {
            throw UnifiedDiffParserError.malformedHunkHeader(line)
        }
        let string = line as NSString
        func integer(_ group: Int, default defaultValue: Int? = nil) -> Int? {
            let range = match.range(at: group)
            guard range.location != NSNotFound else { return defaultValue }
            return Int(string.substring(with: range))
        }
        guard let oldStart = integer(1),
              let oldCount = integer(2, default: 1),
              let newStart = integer(3),
              let newCount = integer(4, default: 1)
        else {
            throw UnifiedDiffParserError.malformedHunkHeader(line)
        }
        let contextRange = match.range(at: 5)
        let context = contextRange.location == NSNotFound ? "" : string.substring(with: contextRange)
        return (
            DiffLineSpan(start: oldStart, count: oldCount),
            DiffLineSpan(start: newStart, count: newCount),
            context
        )
    }
}
