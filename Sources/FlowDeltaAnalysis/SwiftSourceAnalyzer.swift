import FlowDeltaCore
import FlowDeltaFlow
import FlowDeltaParse
import Foundation
import OSLog

public struct SourceFileAnalysis: Sendable, Hashable {
    public let tree: SyntaxTree
    public let entities: [SourceEntity]
    public let graphs: [StableID: ControlFlowGraph]
    public let dataGraphs: [StableID: DataFlowGraph]
    public let diagnostics: [AnalysisDiagnostic]

    public init(
        tree: SyntaxTree,
        entities: [SourceEntity],
        graphs: [StableID: ControlFlowGraph],
        dataGraphs: [StableID: DataFlowGraph] = [:],
        diagnostics: [AnalysisDiagnostic]
    ) {
        self.tree = tree
        self.entities = entities
        self.graphs = graphs
        self.dataGraphs = dataGraphs
        self.diagnostics = diagnostics
    }
}

public typealias SwiftFileAnalysis = SourceFileAnalysis

public struct SwiftSourceAnalyzer: Sendable {
    public init() {}

    public func analyze(
        _ snapshot: SourceSnapshot,
        limits: AnalysisLimits = .default
    ) throws -> SwiftFileAnalysis {
        guard snapshot.language == .swift else {
            throw SourceSyntaxParserError.languageMismatch(expected: .swift, actual: snapshot.language)
        }
        return try SourceAnalyzer().analyze(snapshot, limits: limits)
    }
}

public struct SourceAnalyzer: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Analysis")
    private let parser: SourceSyntaxParser
    private let extractor: SourceEntityExtractor
    private let flowBuilder: SourceControlFlowBuilder
    private let defUseBuilder: DefUseBuilder

    public init() {
        parser = SourceSyntaxParser()
        extractor = SourceEntityExtractor()
        flowBuilder = SourceControlFlowBuilder()
        defUseBuilder = DefUseBuilder()
    }

    public func analyze(
        _ snapshot: SourceSnapshot,
        limits: AnalysisLimits = .default
    ) throws -> SourceFileAnalysis {
        let tree = try parser.parse(snapshot, limits: limits)
        let entities = extractor.entities(in: tree)
        var graphs: [StableID: ControlFlowGraph] = [:]
        var dataGraphs: [StableID: DataFlowGraph] = [:]
        var diagnostics: [AnalysisDiagnostic] = []
        if tree.errorCount > 0 {
            diagnostics.append(AnalysisDiagnostic(
                severity: .warning,
                code: .partialParse,
                message: "\(snapshot.language.displayName) parsed with \(tree.errorCount) recoverable syntax error node(s).",
                path: snapshot.path
            ))
        }

        for entity in entities where Self.supportsFlow(entity.kind) && entity.body.kind != "method_signature" {
            do {
                let graph = try flowBuilder.build(
                    for: entity,
                    language: snapshot.language,
                    limits: limits
                )
                graphs[entity.id] = graph
                dataGraphs[entity.id] = defUseBuilder.build(
                    for: entity,
                    graph: graph,
                    language: snapshot.language
                )
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
        return SourceFileAnalysis(
            tree: tree,
            entities: entities,
            graphs: graphs,
            dataGraphs: dataGraphs,
            diagnostics: diagnostics
        )
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
