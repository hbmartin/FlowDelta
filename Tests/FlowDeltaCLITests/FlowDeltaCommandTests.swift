import ArgumentParser
@testable import FlowDeltaCLI
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
}
