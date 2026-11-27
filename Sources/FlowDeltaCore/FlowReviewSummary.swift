/// The one-line summary a review shows above its triage list. It names the languages and says which basis
/// `affected` uses, because data context exists only for languages with def-use support.
public enum FlowReviewSummary {
    public static func text(for report: RevisionFlowDeltaReport) -> String {
        let languages = Set(report.files.map(\.comparison.language))
        let names = languages.map(\.displayName).sorted().joined(separator: ", ")
        let counts = "\(report.files.count) files (\(names)) • \(report.functionDeltas.count) function deltas"
        return "\(counts) • \(affectedBasis(for: languages))"
    }

    public static func affectedBasis(for languages: Set<SourceLanguage>) -> String {
        let dataFlow = languages.filter(\.supportsDataFlow)
        if dataFlow.isEmpty {
            return "affected = control context"
        }
        if dataFlow.count == languages.count {
            return "affected = control + data context"
        }
        let names = dataFlow.map(\.displayName).sorted().joined(separator: ", ")
        return "affected = control context; data context for \(names)"
    }
}
