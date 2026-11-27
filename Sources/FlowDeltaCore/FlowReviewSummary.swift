/// The one-line summary a review shows above its triage list. It names the languages and says which basis
/// `affected` uses.
public enum FlowReviewSummary {
    public static func text(for report: RevisionFlowDeltaReport) -> String {
        let languages = Set(report.files.map(\.comparison.language))
        let names = languages.map(\.displayName).sorted().joined(separator: ", ")
        let files = counted(report.files.count, "file")
        let deltas = counted(report.functionDeltas.count, "function delta")
        return "\(files) (\(names)) • \(deltas) • \(affectedBasis(for: languages))"
    }

    private static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// Every language has def-use rules, so any analyzed file has data context.
    public static func affectedBasis(for languages: Set<SourceLanguage>) -> String {
        languages.isEmpty ? "affected = control context" : "affected = control + data context"
    }
}
