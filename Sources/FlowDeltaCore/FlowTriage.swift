/// One entity change in a review's triage list.
public struct FlowTriageEntry: Hashable, Sendable {
    public let file: FileFlowDelta
    public let change: EntityChange
    /// The change's function delta, or nil when the entity is not callable or did not change.
    public let function: FunctionFlowDelta?
}

/// A run of triage entries: the whole list, or one concern group and finally the unchanged entities.
public struct FlowTriageSection: Hashable, Sendable {
    /// The group's title, or nil for an ungrouped list.
    public let title: String?
    /// The group's kind, or nil for an ungrouped list and for the unchanged entities.
    public let kind: FlowConcernKind?
    public let entries: [FlowTriageEntry]
}

/// The order a review lists entity changes in.
public enum FlowTriage {
    /// Every entity change in file order, or grouped by concern when `groupsByConcern` is set and the report has
    /// concerns. Changes no concern holds follow as Other Changes, and unchanged entities come last.
    public static func sections(for report: RevisionFlowDeltaReport, groupsByConcern: Bool) -> [FlowTriageSection] {
        let entries = report.files.flatMap { file in
            file.entityChanges.map { change in
                FlowTriageEntry(
                    file: file,
                    change: change,
                    function: file.functionDeltas.first { $0.entityChange == change }
                )
            }
        }
        guard groupsByConcern, let concerns = report.concerns else {
            return [FlowTriageSection(title: nil, kind: nil, entries: entries)]
        }
        var remaining = entries
        var sections: [FlowTriageSection] = []
        for concern in concerns {
            let members = Set(concern.memberIDs)
            let isMember = { (entry: FlowTriageEntry) in entry.change.entityID.map(members.contains) ?? false }
            sections.append(FlowTriageSection(
                title: concern.title,
                kind: concern.kind,
                entries: remaining.filter(isMember)
            ))
            remaining.removeAll(where: isMember)
        }
        let changed = remaining.filter { $0.change.kind != .unchanged }
        if !changed.isEmpty {
            sections.append(FlowTriageSection(title: "Other Changes", kind: nil, entries: changed))
        }
        let unchanged = remaining.filter { $0.change.kind == .unchanged }
        if !unchanged.isEmpty {
            sections.append(FlowTriageSection(title: "Unchanged", kind: nil, entries: unchanged))
        }
        return sections
    }

    /// The function deltas in triage order, for a walkthrough that follows the list.
    public static func functionOrder(of sections: [FlowTriageSection]) -> [StableID] {
        sections.flatMap(\.entries).compactMap(\.function?.id)
    }
}
