import ArgumentParser
@testable import FlowDeltaCommandLine
import FlowDeltaExport
import Foundation
import XCTest

final class FlowDeltaCommandTests: XCTestCase {
    func testParsesRepositoryFormatOutputAndRevisions() throws {
        let command = try FlowDeltaCommand.parse([
            "-C", "/tmp/repository",
            "--format", "markdown",
            "--output", "/tmp/report.md",
            "base", "target"
        ])

        XCTAssertEqual(command.repository, "/tmp/repository")
        XCTAssertEqual(command.format, .markdown)
        XCTAssertEqual(command.output, "/tmp/report.md")
        XCTAssertEqual(command.base, "base")
        XCTAssertEqual(command.target, "target")
    }

    func testTargetDefaultsToHead() throws {
        let command = try FlowDeltaCommand.parse(["base"])

        XCTAssertEqual(command.target, "HEAD")
        XCTAssertEqual(command.format, .table)
    }

    func testRejectsUnknownFormat() {
        XCTAssertThrowsError(try FlowDeltaCommand.parse(["--format", "xml", "base"]))
    }

    func testParsesNoiseGroupingAndWalkthroughIntoExportOptions() throws {
        let command = try FlowDeltaCommand.parse([
            "--noise",
            "hide-cosmetic",
            "--group-by-concern",
            "--walkthrough",
            "base"
        ])
        XCTAssertEqual(
            command.exportOptions,
            FlowDeltaExportOptions(noise: .hideCosmetic, groupByConcern: true, includeWalkthrough: true)
        )
        XCTAssertEqual(try FlowDeltaCommand.parse(["base"]).exportOptions, .default)
        XCTAssertThrowsError(try FlowDeltaCommand.parse(["--noise", "hide-everything", "base"]))
        XCTAssertEqual(FlowDeltaCommand.configuration.version, "0.3.3")
    }

    func testHelpShowsTheNoiseDefaultAsTheSpellingTheParserAccepts() throws {
        let help = FlowDeltaCommand.helpMessage(columns: 1000)
        XCTAssertTrue(help.contains("(default: show-all)"), help)
        XCTAssertEqual(try FlowDeltaCommand.parse(["--noise", "show-all", "base"]).exportOptions, .default)
    }

    func testHideCosmeticKeepsBehavioralPunctuationInTheExport() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func git(_ arguments: String...) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.currentDirectoryURL = directory
            process.arguments = [
                "-c",
                "user.name=FlowDelta",
                "-c",
                "user.email=test@example.com",
                "-c",
                "commit.gpgsign=false"
            ] + arguments
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }

        try git("init", "-q")
        let source = directory.appending(path: "view.jsx")
        try "function View() { return <p>;</p>; }".write(to: source, atomically: true, encoding: .utf8)
        try git("add", "view.jsx")
        try git("commit", "-qm", "base")
        try "function View() { return <p></p>; }".write(to: source, atomically: true, encoding: .utf8)
        try git("commit", "-qam", "target")

        let output = directory.appending(path: "report.json")
        var command = try FlowDeltaCommand.parse([
            "-C", directory.path, "--format", "json", "--output", output.path,
            "--noise", "hide-cosmetic", "--group-by-concern", "--walkthrough", "HEAD^"
        ])
        try command.run()
        let document = try JSONDecoder().decode(FlowDeltaExportDocument.self, from: Data(contentsOf: output))
        XCTAssertEqual(document.report.concerns?.map(\.kind), [.behavioral])
        XCTAssertTrue(document.report.functionDeltas.flatMap(\.nodes).contains { $0.state == .modified })
        XCTAssertEqual(document.walkthrough.count, 1)
    }
}
