import FlowDeltaCore
import FlowDeltaMatch
import Foundation
import OSLog

public struct FlowDeltaAnalyzer: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "RevisionAnalysis")
    private let sourceAnalyzer: SourceAnalyzer
    private let entityMatcher: EntityMatcher
    private let syntaxMatcher: GumTreeMatcher
    private let graphDeltaBuilder: MatchedFlowDeltaBuilder
    private let callGraphBuilder: CallGraphBuilder

    public init() {
        sourceAnalyzer = SourceAnalyzer()
        entityMatcher = EntityMatcher()
        syntaxMatcher = GumTreeMatcher()
        graphDeltaBuilder = MatchedFlowDeltaBuilder()
        callGraphBuilder = CallGraphBuilder()
    }

    public func analyze(
        _ comparison: RevisionComparison,
        limits: AnalysisLimits = .default
    ) throws -> RevisionFlowDeltaReport {
        var analyzedFiles: [AnalyzedFile] = []
        var oldEntities: [SourceEntity] = []
        var newEntities: [SourceEntity] = []
        var oldAnalyses: [String: SourceFileAnalysis] = [:]
        var newAnalyses: [String: SourceFileAnalysis] = [:]
        for file in comparison.files {
            let (oldAnalysis, oldDiagnostics) = analyze(file.old, limits: limits)
            let (newAnalysis, newDiagnostics) = analyze(file.new, limits: limits)
            if let oldAnalysis, let path = file.old?.path {
                oldAnalyses[path] = oldAnalysis
                oldEntities.append(contentsOf: oldAnalysis.entities)
            }
            if let newAnalysis, let path = file.new?.path {
                newAnalyses[path] = newAnalysis
                newEntities.append(contentsOf: newAnalysis.entities)
            }
            analyzedFiles.append(AnalyzedFile(
                comparison: file,
                diagnostics: oldDiagnostics + newDiagnostics
            ))
        }

        let triage = entityMatcher.triage(old: oldEntities, new: newEntities)
        var changesByFile: [StableID: [EntityChange]] = [:]
        for change in triage.changes {
            let destinationPath = change.new?.path ?? change.old?.path
            let file = analyzedFiles.first { analyzed in
                analyzed.comparison.new?.path == destinationPath
                    || (change.new == nil && analyzed.comparison.old?.path == destinationPath)
            }
            if let file {
                changesByFile[file.id, default: []].append(change)
            }
        }

        var files: [FileFlowDelta] = []
        var reportDiagnostics: [AnalysisDiagnostic] = []
        for analyzedFile in analyzedFiles {
            let file = analyzedFile.comparison
            var diagnostics = analyzedFile.diagnostics
            let changes = changesByFile[analyzedFile.id, default: []]
            var functionDeltas: [FunctionFlowDelta] = []
            for change in changes where change.kind != .unchanged
                && Self.isCallable(change.old?.kind ?? change.new?.kind)
            {
                let oldGraph = change.old.flatMap { old in oldAnalyses[old.path]?.graphs[old.id] }
                let newGraph = change.new.flatMap { new in newAnalyses[new.path]?.graphs[new.id] }
                let oldDataGraph = change.old.flatMap { old in oldAnalyses[old.path]?.dataGraphs[old.id] }
                let newDataGraph = change.new.flatMap { new in newAnalyses[new.path]?.dataGraphs[new.id] }
                guard oldGraph != nil || newGraph != nil else {
                    diagnostics.append(AnalysisDiagnostic(
                        severity: .warning,
                        code: .unsupportedConstruct,
                        message: "No flow graph was available for \(change.new?.qualifiedName ?? change.old?.qualifiedName ?? "entity").",
                        path: file.path,
                        range: change.new?.range ?? change.old?.range
                    ))
                    continue
                }
                let editScript: EditScript? = if let old = change.old, let new = change.new {
                    syntaxMatcher.match(old: old.body, new: new.body)
                } else {
                    nil
                }
                functionDeltas.append(graphDeltaBuilder.build(
                    entityChange: change,
                    editScript: editScript,
                    oldGraph: oldGraph,
                    newGraph: newGraph,
                    oldDataGraph: oldDataGraph,
                    newDataGraph: newDataGraph
                ))
            }
            files.append(FileFlowDelta(
                comparison: file,
                entityChanges: changes,
                functionDeltas: functionDeltas,
                diagnostics: diagnostics
            ))
            reportDiagnostics.append(contentsOf: diagnostics.filter { $0.severity == .error })
        }
        let report = RevisionFlowDeltaReport(
            base: comparison.base,
            target: comparison.target,
            files: files,
            callGraph: callGraphBuilder.build(from: triage.changes),
            diagnostics: reportDiagnostics
        )
        Self.logger.notice(
            "Analyzed revision delta: \(report.files.count) files, \(report.entityChanges.count) entities, \(report.functionDeltas.count) functions"
        )
        return report
    }

    private func analyze(
        _ snapshot: SourceSnapshot?,
        limits: AnalysisLimits
    ) -> (SourceFileAnalysis?, [AnalysisDiagnostic]) {
        guard let snapshot else { return (nil, []) }
        do {
            let analysis = try sourceAnalyzer.analyze(snapshot, limits: limits)
            return (analysis, analysis.diagnostics)
        } catch {
            return (nil, [AnalysisDiagnostic(
                severity: .error,
                code: .resourceLimit,
                message: "Could not analyze \(snapshot.path): \(String(describing: error)).",
                path: snapshot.path
            )])
        }
    }

    private static func isCallable(_ kind: EntityKind?) -> Bool {
        guard let kind else { return false }
        switch kind {
        case .function, .method, .initializer, .deinitializer, .subscriptDeclaration, .operatorDeclaration:
            return true
        case .type, .typeExtension, .topLevelBinding:
            return false
        }
    }
}

private struct AnalyzedFile {
    let id: StableID
    let comparison: FileComparison
    let diagnostics: [AnalysisDiagnostic]

    init(comparison: FileComparison, diagnostics: [AnalysisDiagnostic]) {
        id = StableID(
            namespace: "analyzed-file",
            components: [comparison.old?.path ?? "", comparison.new?.path ?? ""]
        )
        self.comparison = comparison
        self.diagnostics = diagnostics
    }
}
