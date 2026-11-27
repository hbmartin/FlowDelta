@preconcurrency import ArgumentParser
import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaExport
import FlowDeltaGit
import Foundation

@main
struct FlowDeltaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flowdelta",
        abstract: "Explain how two Git revisions change source control and data flow.",
        version: "0.3.0"
    )

    @Option(name: [.customShort("C"), .long], help: "Path to the Git repository.")
    var repository = "."

    @Option(name: .long, help: "Output format: table, json, mermaid, or markdown.")
    var format: CLIExportFormat = .table

    @Option(name: [.customShort("o"), .long], help: "Write output to this path instead of standard output.")
    var output: String?

    @Option(name: .long, help: "Noise to hide: show-all, hide-formatting, or hide-cosmetic. Rewrites are never hidden.")
    var noise: FlowNoisePolicy = .showAll

    @Flag(name: .long, help: "Group the triage by concern and note a tangled revision.")
    var groupByConcern = false

    @Flag(name: .long, help: "Append walkthrough steps (table, json, and markdown).")
    var walkthrough = false

    @Argument(help: "Base commit-ish.")
    var base: String

    @Argument(help: "Target commit-ish (default: HEAD).")
    var target = "HEAD"

    mutating func run() throws {
        let repositoryURL = URL(fileURLWithPath: repository, isDirectory: true).standardizedFileURL
        let baseRevision = base
        let targetRevision = target
        let result = BlockingResult<RevisionFlowDeltaReport>()
        Task.detached {
            do {
                let comparison = try await GitCLIRevisionProvider().comparison(
                    repositoryURL: repositoryURL,
                    base: baseRevision,
                    target: targetRevision
                )
                try result.complete(.success(FlowDeltaAnalyzer().analyze(comparison)))
            } catch {
                result.complete(.failure(error))
            }
        }
        let report = try result.wait()
        let rendered = try FlowDeltaReportExporter().render(report, format: format.exportFormat, options: exportOptions)
        let data = Data(rendered.utf8)
        if let output {
            let outputURL = URL(fileURLWithPath: output).standardizedFileURL
            try data.write(to: outputURL, options: .atomic)
        } else {
            FileHandle.standardOutput.write(data)
        }
    }
}

extension FlowDeltaCommand {
    var exportOptions: FlowDeltaExportOptions {
        FlowDeltaExportOptions(noise: noise, groupByConcern: groupByConcern, includeWalkthrough: walkthrough)
    }
}

extension FlowNoisePolicy: ExpressibleByArgument {
    /// Help shows the spelling `--noise` accepts rather than the Swift case name.
    public var defaultValueDescription: String {
        rawValue
    }
}

private final class BlockingResult<Value>: @unchecked Sendable {
    private let condition = NSCondition()
    private var result: Result<Value, any Error>?

    func complete(_ result: Result<Value, any Error>) {
        condition.lock()
        self.result = result
        condition.broadcast()
        condition.unlock()
    }

    func wait() throws -> Value {
        condition.lock()
        while true {
            if let result {
                condition.unlock()
                return try result.get()
            }
            condition.wait()
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
