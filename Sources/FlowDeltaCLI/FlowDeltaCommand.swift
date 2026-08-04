import ArgumentParser
import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaExport
import FlowDeltaGit
import Foundation

@main
struct FlowDeltaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flowdelta",
        abstract: "Explain how two Git revisions change source control and data flow.",
        version: "0.2.0"
    )

    @Option(name: [.customShort("C"), .long], help: "Path to the Git repository.")
    var repository = "."

    @Option(name: .long, help: "Output format: table, json, mermaid, or markdown.")
    var format: CLIExportFormat = .table

    @Option(name: [.customShort("o"), .long], help: "Write output to this path instead of standard output.")
    var output: String?

    @Argument(help: "Base commit-ish.")
    var base: String

    @Argument(help: "Target commit-ish (default: HEAD).")
    var target = "HEAD"

    mutating func run() async throws {
        let repositoryURL = URL(fileURLWithPath: repository, isDirectory: true).standardizedFileURL
        let comparison = try await GitCLIRevisionProvider().comparison(
            repositoryURL: repositoryURL,
            base: base,
            target: target
        )
        let report = try FlowDeltaAnalyzer().analyze(comparison)
        let rendered = try FlowDeltaReportExporter().render(report, format: format.exportFormat)
        let data = Data(rendered.utf8)
        if let output {
            let outputURL = URL(fileURLWithPath: output).standardizedFileURL
            try data.write(to: outputURL, options: .atomic)
        } else {
            FileHandle.standardOutput.write(data)
        }
    }
}

enum CLIExportFormat: String, CaseIterable, ExpressibleByArgument {
    case table
    case json
    case mermaid
    case markdown

    var exportFormat: FlowDeltaExportFormat {
        FlowDeltaExportFormat(rawValue: rawValue) ?? .table
    }
}
