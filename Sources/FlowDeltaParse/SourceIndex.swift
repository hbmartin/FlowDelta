import FlowDeltaCore
import Foundation

struct SourceIndex {
    let text: String
    private let utf8Offsets: [Int]
    private let lineStarts: [Int]

    init(_ text: String) {
        self.text = text
        var offsets = Array(repeating: 0, count: text.utf16.count + 1)
        var utf16Offset = 0
        var utf8Offset = 0
        var starts = [0]

        for scalar in text.unicodeScalars {
            let utf16Length = scalar.utf16.count
            let utf8Length = scalar.utf8.count
            for intermediate in 0 ..< utf16Length {
                offsets[utf16Offset + intermediate] = utf8Offset
            }
            utf16Offset += utf16Length
            utf8Offset += utf8Length
            offsets[utf16Offset] = utf8Offset
            if scalar == "\n" {
                starts.append(utf16Offset)
            }
        }
        utf8Offsets = offsets
        lineStarts = starts
    }

    func sourceRange(_ range: NSRange) -> SourceRange {
        let lower = max(0, min(range.location, utf8Offsets.count - 1))
        let upper = max(lower, min(range.location + range.length, utf8Offsets.count - 1))
        return SourceRange(start: location(lower), end: location(upper))
    }

    func substring(_ range: NSRange) -> String {
        guard let stringRange = Range(range, in: text) else { return "" }
        return String(text[stringRange])
    }

    private func location(_ utf16Offset: Int) -> SourceLocation {
        let line = max(0, lineStarts.partitioningIndex { $0 > utf16Offset } - 1)
        let lineStart = lineStarts[line]
        return SourceLocation(
            utf8Offset: utf8Offsets[utf16Offset],
            utf16Offset: utf16Offset,
            line: line,
            utf16Column: utf16Offset - lineStart
        )
    }
}

private extension RandomAccessCollection {
    func partitioningIndex(where predicate: (Element) -> Bool) -> Index {
        var lower = startIndex
        var upper = endIndex
        while lower != upper {
            let distance = distance(from: lower, to: upper)
            let middle = index(lower, offsetBy: distance / 2)
            if predicate(self[middle]) {
                upper = middle
            } else {
                lower = index(after: middle)
            }
        }
        return lower
    }
}
