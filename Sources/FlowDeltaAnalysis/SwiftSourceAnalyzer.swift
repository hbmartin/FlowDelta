import FlowDeltaCore
import FlowDeltaFlow
import FlowDeltaParse
import Foundation
import OSLog

public struct SwiftFileAnalysis: Sendable, Hashable {
    public let tree: SyntaxTree
    public let entities: [SourceEntity]
    public let graphs: [StableID: ControlFlowGraph]
    public let diagnostics: [AnalysisDiagnostic]

    public init(
        tree: SyntaxTree,
        entities: [SourceEntity],
        graphs: [StableID: ControlFlowGraph],
        diagnostics: [AnalysisDiagnostic]
    ) {
        self.tree = tree
        self.entities = entities
        self.graphs = graphs
        self.diagnostics = diagnostics
    }
}

public struct SwiftSourceAnalyzer: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Analysis")
    private let parser: SwiftSyntaxParser
    private let extractor: SwiftEntityExtractor
    private let flowBuilder: SwiftControlFlowBuilder

    public init() {
        parser = SwiftSyntaxParser()
        extractor = SwiftEntityExtractor()
        flowBuilder = SwiftControlFlowBuilder()
    }

    public func analyze(
        _ snapshot: SourceSnapshot,
        limits: AnalysisLimits = .default
    ) throws -> SwiftFileAnalysis {
        let tree = try parser.parse(snapshot, limits: limits)
        let entities = extractor.entities(in: tree)
        var graphs: [StableID: ControlFlowGraph] = [:]
        var diagnostics: [AnalysisDiagnostic] = []
        if tree.errorCount > 0 {
            diagnostics.append(AnalysisDiagnostic(
                severity: .warning,
                code: .partialParse,
                message: "Swift parsed with \(tree.errorCount) recoverable syntax error node(s).",
                path: snapshot.path
            ))
        }

        for entity in entities where Self.supportsFlow(entity.kind) {
            do {
                graphs[entity.id] = try flowBuilder.build(for: entity, limits: limits)
            } catch let error as ControlFlowBuilderError {
                diagnostics.append(AnalysisDiagnostic(
                    severity: .warning,
                    code: .resourceLimit,
                    message: "Skipped flow graph for \(entity.qualifiedName): \(String(describing: error)).",
                    path: entity.path,
                    range: entity.range
                ))
            }
        }
        Self.logger.debug("Completed source analysis for \(snapshot.path, privacy: .public)")
        return SwiftFileAnalysis(tree: tree, entities: entities, graphs: graphs, diagnostics: diagnostics)
    }

    private static func supportsFlow(_ kind: EntityKind) -> Bool {
        switch kind {
        case .function, .method, .initializer, .deinitializer, .subscriptDeclaration, .operatorDeclaration:
            true
        case .type, .typeExtension, .topLevelBinding:
            false
        }
    }
}
