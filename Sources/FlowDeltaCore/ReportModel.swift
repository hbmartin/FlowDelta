import Foundation

public struct FileFlowDelta: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let comparison: FileComparison
    public let entityChanges: [EntityChange]
    public let functionDeltas: [FunctionFlowDelta]
    public let diagnostics: [AnalysisDiagnostic]

    public init(
        comparison: FileComparison,
        entityChanges: [EntityChange],
        functionDeltas: [FunctionFlowDelta],
        diagnostics: [AnalysisDiagnostic] = []
    ) {
        id = StableID(
            namespace: "file-delta",
            components: [comparison.old?.path ?? "", comparison.new?.path ?? ""]
        )
        self.comparison = comparison
        self.entityChanges = entityChanges
        self.functionDeltas = functionDeltas.sorted { $0.displayName < $1.displayName }
        self.diagnostics = diagnostics
    }

    public var path: String {
        comparison.path
    }
}

public struct RevisionFlowDeltaReport: Codable, Hashable, Sendable {
    public let base: RevisionIdentity
    public let target: RevisionIdentity
    public let files: [FileFlowDelta]
    public let callGraph: CallGraph?
    public let diagnostics: [AnalysisDiagnostic]

    public init(
        base: RevisionIdentity,
        target: RevisionIdentity,
        files: [FileFlowDelta],
        callGraph: CallGraph? = nil,
        diagnostics: [AnalysisDiagnostic] = []
    ) {
        self.base = base
        self.target = target
        self.files = files.sorted { $0.path < $1.path }
        self.callGraph = callGraph
        self.diagnostics = diagnostics
    }

    public var entityChanges: [EntityChange] {
        files.flatMap(\.entityChanges)
    }

    public var functionDeltas: [FunctionFlowDelta] {
        files.flatMap(\.functionDeltas)
    }

    public func count(of kind: EntityChangeKind) -> Int {
        entityChanges.count { $0.kind == kind }
    }

    public func enrichingCallGraph(
        using enricher: any CallGraphEnriching,
        sourceFiles: [String]
    ) throws -> RevisionFlowDeltaReport {
        guard let callGraph else { return self }
        return try RevisionFlowDeltaReport(
            base: base,
            target: target,
            files: files,
            callGraph: enricher.enrich(callGraph, sourceFiles: sourceFiles),
            diagnostics: diagnostics
        )
    }
}

public extension FunctionFlowDelta {
    var displayName: String {
        entityChange.new?.qualifiedName ?? entityChange.old?.qualifiedName ?? "<unknown>"
    }

    var path: String {
        entityChange.new?.path ?? entityChange.old?.path ?? ""
    }

    func count(of state: DeltaState) -> Int {
        nodes.count { $0.state == state }
    }
}
