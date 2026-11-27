import ArgumentParser
@testable import FlowDeltaCLI
import FlowDeltaExport
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
        XCTAssertEqual(FlowDeltaCommand.configuration.version, "0.3.0")
    }

    func testHelpShowsTheNoiseDefaultAsTheSpellingTheParserAccepts() throws {
        let help = FlowDeltaCommand.helpMessage(columns: 1000)
        XCTAssertTrue(help.contains("(default: show-all)"), help)
        XCTAssertEqual(try FlowDeltaCommand.parse(["--noise", "show-all", "base"]).exportOptions, .default)
    }
}
