/// Why a modified node's change may not change behavior. Higher levels need more reasoning to prove.
public enum FlowNoiseLevel: Int, Codable, CaseIterable, Comparable, Sendable {
    /// Only whitespace or comments changed.
    case formatting = 1
    /// Only optional syntax changed, such as a statement-ending semicolon or a `self.` receiver.
    case optionalSyntax = 2
    /// The statement was rewritten into an equivalent form, such as `a += b` for `a = a + b`. Never hidden.
    case rewrite = 3

    public static func < (lhs: FlowNoiseLevel, rhs: FlowNoiseLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .formatting: "formatting"
        case .optionalSyntax: "optional syntax"
        case .rewrite: "rewrite"
        }
    }
}

/// Which noise a review hides.
public enum FlowNoisePolicy: String, Codable, CaseIterable, Sendable {
    case showAll = "show-all"
    case hideFormatting = "hide-formatting"
    case hideCosmetic = "hide-cosmetic"

    public var displayName: String {
        switch self {
        case .showAll: "Show All Changes"
        case .hideFormatting: "Hide Formatting"
        case .hideCosmetic: "Hide Cosmetic Changes"
        }
    }

    /// Whether a node with `level` noise is shown as unchanged. Rewrites are always shown.
    public func hides(_ level: FlowNoiseLevel?) -> Bool {
        switch (self, level) {
        case (.hideFormatting, .formatting), (.hideCosmetic, .formatting), (.hideCosmetic, .optionalSyntax): true
        default: false
        }
    }
}

/// A function delta as a noise policy shows it.
public struct FlowNoiseFilterResult: Hashable, Sendable {
    public let function: FunctionFlowDelta
    /// The modified nodes the policy shows as retained.
    public let hiddenNodeIDs: Set<StableID>
}

public enum FlowNoiseFilter {
    /// Shows hidden modified nodes as retained, prunes the causality they triggered, and shows an affected node
    /// left without causality as retained.
    public static func apply(_ policy: FlowNoisePolicy, to function: FunctionFlowDelta) -> FlowNoiseFilterResult {
        let hidden = Set(function.nodes.filter { $0.state == .modified && policy.hides($0.noise) }.map(\.id))
        guard !hidden.isEmpty else {
            return FlowNoiseFilterResult(function: function, hiddenNodeIDs: [])
        }
        let nodes = function.nodes.map { node -> FlowNodeDelta in
            if hidden.contains(node.id) {
                return node.with(state: .retained, causality: [])
            }
            let causality = node.causality.filter { !hidden.contains($0.triggerID) }
            let state: DeltaState = node.state == .affected && causality.isEmpty ? .retained : node.state
            return node.with(state: state, causality: causality)
        }
        let filtered = FunctionFlowDelta(
            id: function.id,
            entityChange: function.entityChange,
            editScript: function.editScript,
            oldGraph: function.oldGraph,
            newGraph: function.newGraph,
            nodes: nodes,
            edges: function.edges,
            dataFlow: function.dataFlow,
            classifications: function.classifications
        )
        return FlowNoiseFilterResult(function: filtered, hiddenNodeIDs: hidden)
    }

    /// The report with every function delta as `policy` shows it.
    public static func apply(_ policy: FlowNoisePolicy, to report: RevisionFlowDeltaReport) -> RevisionFlowDeltaReport {
        guard policy != .showAll else { return report }
        let files = report.files.map { file in
            FileFlowDelta(
                comparison: file.comparison,
                entityChanges: file.entityChanges,
                functionDeltas: file.functionDeltas.map { apply(policy, to: $0).function },
                diagnostics: file.diagnostics
            )
        }
        return RevisionFlowDeltaReport(
            base: report.base,
            target: report.target,
            files: files,
            callGraph: report.callGraph,
            diagnostics: report.diagnostics,
            concerns: report.concerns
        )
    }

    /// How many nodes `policy` hides across a report, for a "N hidden — Show" link.
    public static func hiddenNodeCount(_ policy: FlowNoisePolicy, in report: RevisionFlowDeltaReport) -> Int {
        report.functionDeltas.reduce(0) { count, function in
            count + function.nodes.count { $0.state == .modified && policy.hides($0.noise) }
        }
    }

    /// The highest noise level of a function's changed nodes, or nil when some change is real. A function whose
    /// changes are all noise at or below `.optionalSyntax` is cosmetic; all rewrites make it a refactoring.
    public static func noiseLevel(of function: FunctionFlowDelta) -> FlowNoiseLevel? {
        guard function.edges.allSatisfy({ $0.state == .retained }) else { return nil }
        let changed = function.nodes.filter { $0.state == .added || $0.state == .removed || $0.state == .modified }
        guard !changed.isEmpty else { return nil }
        var highest: FlowNoiseLevel = .formatting
        for node in changed {
            guard node.state == .modified, let noise = node.noise else { return nil }
            highest = max(highest, noise)
        }
        return highest
    }
}
