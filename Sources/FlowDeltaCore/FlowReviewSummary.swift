/// The one-line summary a review shows above its triage list. It names the languages and says which basis
/// `affected` uses.
public enum FlowReviewSummary {
    public static func text(for report: RevisionFlowDeltaReport) -> String {
        let languages = Set(report.files.map(\.comparison.language))
        let names = languages.map(\.displayName).sorted().joined(separator: ", ")
        let counts = "\(report.files.count) files (\(names)) • \(report.functionDeltas.count) function deltas"
        return "\(counts) • \(affectedBasis(for: languages))"
    }

    /// Every language has def-use rules, so any analyzed file has data context.
    public static func affectedBasis(for languages: Set<SourceLanguage>) -> String {
        languages.isEmpty ? "affected = control context" : "affected = control + data context"
    }
}
