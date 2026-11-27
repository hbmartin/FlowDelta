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

/// A run of triage rows, under a concern title when the export groups by concern.
struct ExportSection {
    let title: String?
    let changes: [(file: FileFlowDelta, change: EntityChange)]
}

/// What an export renders once its options are applied.
struct ExportContext {
    let report: RevisionFlowDeltaReport
    let sections: [ExportSection]
    /// Function deltas in triage order.
    let functions: [FunctionFlowDelta]
    /// Lines after the summary: hidden noise and a tangled revision.
    let notes: [String]
    let walkthrough: [FlowWalkthroughStep]?

    init(report original: RevisionFlowDeltaReport, options: FlowDeltaExportOptions) {
        report = FlowNoiseFilter.apply(options.noise, to: original)
        let rows = report.files.flatMap { file in file.entityChanges.map { (file: file, change: $0) } }
        var notes: [String] = []
        let hidden = FlowNoiseFilter.hiddenNodeCount(options.noise, in: original)
        if hidden > 0 {
            notes.append("Noise: \(hidden) node change\(hidden == 1 ? "" : "s") hidden (\(options.noise.rawValue)).")
        }
        if options.groupByConcern, let concerns = report.concerns {
            sections = Self.sections(rows: rows, concerns: concerns)
            if report.isTangled {
                let count = concerns.count { $0.kind == .behavioral }
                notes.append("Tangled revision: \(count) separate behavioral concerns.")
            }
        } else {
            sections = [ExportSection(title: nil, changes: rows)]
        }
        let byChange = Dictionary(
            report.functionDeltas.map { ($0.entityChange, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        functions = options.groupByConcern
            ? sections.flatMap(\.changes).compactMap { byChange[$0.change] }
            : report.functionDeltas
        self.notes = notes
        walkthrough = options.includeWalkthrough
            ? FlowWalkthrough.steps(for: original, policy: options.noise, functionOrder: functions.map(\.id))
            : nil
    }

    private static func sections(
        rows: [(file: FileFlowDelta, change: EntityChange)],
        concerns: [FlowConcern]
    ) -> [ExportSection] {
        var remaining = rows
        var result: [ExportSection] = []
        for concern in concerns {
            let members = Set(concern.memberIDs)
            let changes = remaining.filter { $0.change.entityID.map(members.contains) ?? false }
            remaining.removeAll { $0.change.entityID.map(members.contains) ?? false }
            result.append(ExportSection(title: "\(concern.title) — \(concern.kind.rawValue)", changes: changes))
        }
        if !remaining.isEmpty {
            result.append(ExportSection(title: "Unchanged", changes: remaining))
        }
        return result
    }
}
