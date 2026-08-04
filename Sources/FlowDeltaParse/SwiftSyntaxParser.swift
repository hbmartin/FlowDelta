import FlowDeltaCore
import Foundation
import OSLog
import SwiftTreeSitter
import TreeSitterSwift

public enum SwiftSyntaxParserError: Error, Equatable {
    case parserInitialization
    case nodeLimitExceeded(limit: Int)
}

public struct SwiftSyntaxParser: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Parse")

    public init() {}

    public func parse(
        _ snapshot: SourceSnapshot,
        limits: AnalysisLimits = .default
    ) throws -> SyntaxTree {
        let parser = Parser()
        let language = Language(language: tree_sitter_swift())
        try parser.setLanguage(language)
        guard let mutableTree = parser.parse(snapshot.text), let root = mutableTree.rootNode else {
            throw SwiftSyntaxParserError.parserInitialization
        }

        let index = SourceIndex(snapshot.text)
        var nodeCount = 0
        var errorCount = 0
        let normalized = try normalize(
            root,
            fieldName: nil,
            path: snapshot.path,
            index: index,
            nodeCount: &nodeCount,
            errorCount: &errorCount,
            limit: limits.maximumSyntaxNodesPerFile
        )
        Self.logger.debug(
            "Parsed \(snapshot.path, privacy: .public): \(nodeCount) nodes, \(errorCount) error nodes"
        )
        return SyntaxTree(snapshot: snapshot, root: normalized, errorCount: errorCount)
    }

    private func normalize(
        _ node: Node,
        fieldName: String?,
        path: String,
        index: SourceIndex,
        nodeCount: inout Int,
        errorCount: inout Int,
        limit: Int
    ) throws -> SyntaxNode {
        nodeCount += 1
        guard nodeCount <= limit else {
            throw SwiftSyntaxParserError.nodeLimitExceeded(limit: limit)
        }
        if node.hasError || node.isMissing {
            errorCount += 1
        }

        var children: [SyntaxNode] = []
        children.reserveCapacity(node.childCount)
        for childIndex in 0 ..< node.childCount {
            guard let child = node.child(at: childIndex) else { continue }
            children.append(try normalize(
                child,
                fieldName: node.fieldNameForChild(at: childIndex),
                path: path,
                index: index,
                nodeCount: &nodeCount,
                errorCount: &errorCount,
                limit: limit
            ))
        }

        let rawKind = node.nodeType ?? "unknown"
        let rawText = index.substring(node.range)
        // tree-sitter-swift 0.7.3 parses `defer { ... }` as a call expression
        // whose callee is the identifier "defer". Promote that unambiguous
        // grammar gap (and its error-recovery form) into FlowDelta's IR.
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDeferCall = rawKind == "call_expression"
            && children.first(where: { $0.kind == "simple_identifier" })?.text == "defer"
        let isRecoveredDefer = rawKind == "ERROR" && trimmedText.hasPrefix("defer")
        let kind = isDeferCall || isRecoveredDefer ? "defer_statement" : rawKind
        let range = index.sourceRange(node.range)
        return SyntaxNode(
            id: StableID(
                namespace: "syntax",
                components: [
                    path,
                    kind,
                    String(range.start.utf16Offset),
                    String(range.end.utf16Offset),
                    fieldName ?? "",
                ]
            ),
            kind: kind,
            fieldName: fieldName,
            range: range,
            text: rawText,
            isNamed: node.isNamed,
            isMissing: node.isMissing,
            hasError: node.hasError,
            children: children
        )
    }
}
