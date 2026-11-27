import FlowDeltaCore

/// How an export filters, groups and narrates a report. The default reproduces the 0.2 table, Mermaid and
/// Markdown output.
public struct FlowDeltaExportOptions: Hashable, Sendable {
    /// The noise the export shows as unchanged.
    public var noise: FlowNoisePolicy
    /// Orders the triage by concern group and notes a tangled revision.
    public var groupByConcern: Bool
    /// Appends the walkthrough steps to table, Markdown and JSON output.
    public var includeWalkthrough: Bool

    public init(noise: FlowNoisePolicy = .showAll, groupByConcern: Bool = false, includeWalkthrough: Bool = false) {
        self.noise = noise
        self.groupByConcern = groupByConcern
        self.includeWalkthrough = includeWalkthrough
    }

    public static let `default` = FlowDeltaExportOptions()
}

/// The JSON an export writes when it includes a walkthrough.
public struct FlowDeltaExportDocument: Codable, Hashable, Sendable {
    public let report: RevisionFlowDeltaReport
    public let walkthrough: [FlowWalkthroughStep]
}

/// What an export renders once its options are applied.
struct ExportContext {
    let report: RevisionFlowDeltaReport
    let sections: [FlowTriageSection]
    /// Function deltas in triage order.
    let functions: [FunctionFlowDelta]
    /// Lines after the summary: hidden noise and a tangled revision.
    let notes: [String]
    let walkthrough: [FlowWalkthroughStep]?

    init(report original: RevisionFlowDeltaReport, options: FlowDeltaExportOptions) {
        report = FlowNoiseFilter.apply(options.noise, to: original)
        sections = FlowTriage.sections(for: report, groupsByConcern: options.groupByConcern)
        var notes: [String] = []
        let hidden = FlowNoiseFilter.hiddenNodeCount(options.noise, in: original)
        if hidden > 0 {
            notes.append("Noise: \(hidden) node change\(hidden == 1 ? "" : "s") hidden (\(options.noise.rawValue)).")
        }
        if options.groupByConcern, report.isTangled {
            let count = (report.concerns ?? []).count { $0.kind == .behavioral }
            notes.append("Tangled revision: \(count) separate behavioral concerns.")
        }
        self.notes = notes
        functions = options.groupByConcern ? sections.flatMap(\.entries).compactMap(\.function) : report.functionDeltas
        walkthrough = options.includeWalkthrough
            ? FlowWalkthrough.steps(for: original, policy: options.noise, functionOrder: functions.map(\.id))
            : nil
    }
}

extension FlowTriageSection {
    /// The heading an export writes above the section, or nil for an ungrouped list.
    var heading: String? {
        guard let title else { return nil }
        return kind.map { "\(title) — \($0.rawValue)" } ?? title
    }
}
