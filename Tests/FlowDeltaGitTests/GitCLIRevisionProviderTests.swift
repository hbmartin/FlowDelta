import FlowDeltaCore
import FlowDeltaGit
import Foundation
import XCTest

final class GitCLIRevisionProviderTests: XCTestCase {
    func testLoadsModifyRenameAddAndDeleteWithSpaces() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("""
        func value() -> Int {
            return 1
        }

        """, to: "Sources/Value.swift")
        try repository.write("func deleted() {}\n", to: "Sources/Delete Me.swift")
        try repository.write("not analyzed\n", to: "README.txt")
        try repository.commit("base")
        try repository.move("Sources/Value.swift", to: "Sources/Renamed Value.swift")
        try repository.write("""
        func value() -> Int {
            return 2
        }

        """, to: "Sources/Renamed Value.swift")
        try repository.remove("Sources/Delete Me.swift")
        try repository.write("func added() {}\n", to: "Sources/Added.swift")
        try repository.commit("target")

        let comparison = try await GitCLIRevisionProvider().comparison(
            repositoryURL: repository.url,
            base: "HEAD^",
            target: "HEAD"
        )

        XCTAssertEqual(comparison.files.count, 3)
        let rename = try XCTUnwrap(comparison.files.first { $0.old?.path == "Sources/Value.swift" })
        XCTAssertEqual(rename.new?.path, "Sources/Renamed Value.swift")
        XCTAssertTrue(rename.unifiedDiff?.contains("Value.swift") == true)
        XCTAssertNotNil(comparison.files.first { $0.old == nil && $0.new?.path == "Sources/Added.swift" })
        XCTAssertNotNil(comparison.files.first { $0.old?.path == "Sources/Delete Me.swift" && $0.new == nil })
        XCTAssertEqual(comparison.base.value.count, 40)
        XCTAssertEqual(comparison.target.value.count, 40)
    }

    func testInvalidRevisionPreservesGitFailure() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("func value() {}\n", to: "Value.swift")
        try repository.commit("base")

        do {
            _ = try await GitCLIRevisionProvider().comparison(
                repositoryURL: repository.url,
                base: "missing-revision",
                target: "HEAD"
            )
            XCTFail("Expected Git failure")
        } catch let error as GitRevisionProviderError {
            guard case let .gitFailed(arguments, status, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(arguments.contains("rev-parse"))
            XCTAssertNotEqual(status, 0)
        }
    }

    func testLoadsEverySupportedM2LanguageAndIgnoresUnsupportedFiles() async throws {
        let repository = try TemporaryGitRepository()
        let supported = ["Value.swift", "value.ts", "value.js", "value.py", "value.go"]
        for path in supported {
            try repository.write("// base\n", to: path)
        }
        try repository.write("base\n", to: "value.txt")
        try repository.commit("base")
        for path in supported {
            try repository.write("// target\n", to: path)
        }
        try repository.write("target\n", to: "value.txt")
        try repository.commit("target")

        let comparison = try await GitCLIRevisionProvider().comparison(
            repositoryURL: repository.url,
            base: "HEAD^",
            target: "HEAD"
        )

        XCTAssertEqual(Set(comparison.files.map(\.path)), Set(supported))
        XCTAssertEqual(Set(comparison.files.map(\.language)), Set(SourceLanguage.allCases))
    }

    func testCrossExtensionRenamesBecomeSupportedSideAdditionsAndDeletions() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("func outgoing() {}\n", to: "Outgoing.swift")
        try repository.write("func incoming() {}\n", to: "Incoming.txt")
        try repository.commit("base")
        try repository.move("Outgoing.swift", to: "Outgoing.txt")
        try repository.move("Incoming.txt", to: "Incoming.swift")
        try repository.commit("target")

        let comparison = try await GitCLIRevisionProvider().comparison(
            repositoryURL: repository.url,
            base: "HEAD^",
            target: "HEAD"
        )

        XCTAssertEqual(comparison.files.count, 2)
        let deletion = try XCTUnwrap(comparison.files.first { $0.old?.path == "Outgoing.swift" })
        XCTAssertNil(deletion.new)
        let addition = try XCTUnwrap(comparison.files.first { $0.new?.path == "Incoming.swift" })
        XCTAssertNil(addition.old)
    }

    func testRejectsNonUTF8SourceBlob() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("func value() {}\n", to: "Value.swift")
        try repository.commit("base")
        try repository.write(Data([0xFF, 0xFE]), to: "Value.swift")
        try repository.commit("target")

        do {
            _ = try await GitCLIRevisionProvider().comparison(
                repositoryURL: repository.url,
                base: "HEAD^",
                target: "HEAD"
            )
            XCTFail("Expected invalid UTF-8 failure")
        } catch let error as GitRevisionProviderError {
            XCTAssertEqual(error, .invalidUTF8(context: "Value.swift"))
        }
    }

    func testRejectsNonUTF8GitMetadata() async throws {
        let repository = try TemporaryGitRepository()
        let executable = repository.url.appendingPathComponent("fake-git")
        try Data("#!/bin/sh\nprintf '\\377'\n".utf8).write(to: executable, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        do {
            _ = try await GitCLIRevisionProvider(executableURL: executable).comparison(
                repositoryURL: repository.url,
                base: "HEAD^",
                target: "HEAD"
            )
            XCTFail("Expected invalid UTF-8 failure")
        } catch let error as GitRevisionProviderError {
            XCTAssertEqual(error, .invalidUTF8(context: "base revision"))
        }
    }

    func testRejectsNonUTF8NameStatus() async throws {
        let repository = try TemporaryGitRepository()
        let executable = repository.url.appendingPathComponent("fake-git")
        let script = """
        #!/bin/sh
        for argument in "$@"; do
            if [ "$argument" = "--name-status" ]; then printf '\\377\\000Value.swift\\000'; exit 0; fi
        done
        echo 0123456789abcdef0123456789abcdef01234567
        """
        try Data(script.utf8).write(to: executable, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        do {
            _ = try await GitCLIRevisionProvider(executableURL: executable).comparison(
                repositoryURL: repository.url,
                base: "HEAD^",
                target: "HEAD"
            )
            XCTFail("Expected invalid UTF-8 failure")
        } catch let error as GitRevisionProviderError {
            XCTAssertEqual(error, .invalidUTF8(context: "name status"))
        }
    }

    func testCancellingTheComparisonTerminatesGit() async throws {
        let repository = try TemporaryGitRepository()
        let started = repository.url.appendingPathComponent("git-started")
        let executable = repository.url.appendingPathComponent("slow-git")
        // exec keeps sleep as the process git's pipe belongs to, so terminating it closes the pipe.
        try Data("#!/bin/sh\n: > '\(started.path)'\nexec /bin/sleep 60\n".utf8).write(to: executable, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let comparison = Task {
            try await GitCLIRevisionProvider(executableURL: executable).comparison(
                repositoryURL: repository.url,
                base: "HEAD^",
                target: "HEAD"
            )
        }
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: started.path), Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: started.path), "git never started")
        let cancelled = Date()
        comparison.cancel()

        do {
            _ = try await comparison.value
            XCTFail("Expected the cancelled comparison to throw")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(cancelled), 10, "git kept running after cancellation")
        }
    }

    func testCancellingTerminatesGitAfterItClosesItsOutput() async throws {
        let repository = try TemporaryGitRepository()
        let closed = repository.url.appendingPathComponent("output-closed")
        let executable = repository.url.appendingPathComponent("quiet-git")
        try Data("#!/bin/sh\nexec 1>&-\n: > '\(closed.path)'\nexec /bin/sleep 60\n".utf8)
            .write(to: executable, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let comparison = Task {
            try await GitCLIRevisionProvider(executableURL: executable).comparison(
                repositoryURL: repository.url,
                base: "HEAD^",
                target: "HEAD"
            )
        }
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: closed.path), Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: closed.path), "git never closed its output")
        // Let the provider see the end of the output and start waiting for git to exit.
        try await Task.sleep(for: .milliseconds(300))
        let cancelled = Date()
        comparison.cancel()

        do {
            _ = try await comparison.value
            XCTFail("Expected the cancelled comparison to throw")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(cancelled), 10, "git kept running after cancellation")
        }
    }

    func testLargeErrorOutputCannotStallGit() async throws {
        let repository = try TemporaryGitRepository()
        let executable = repository.url.appendingPathComponent("noisy-git")
        try Data("#!/bin/sh\nhead -c 200000 /dev/zero | tr '\\000' e >&2\nexit 3\n".utf8)
            .write(to: executable, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let comparison = Task {
            try await GitCLIRevisionProvider(executableURL: executable).comparison(
                repositoryURL: repository.url,
                base: "HEAD^",
                target: "HEAD"
            )
        }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(10))
            comparison.cancel()
        }
        defer { watchdog.cancel() }
        do {
            _ = try await comparison.value
            XCTFail("Expected git's failure")
        } catch let GitRevisionProviderError.gitFailed(_, status, message) {
            XCTAssertEqual(status, 3)
            XCTAssertEqual(message.count, 200_000)
        } catch {
            XCTFail("git stalled writing its error output: \(error)")
        }
    }

    func testAComparisonCancelledBeforeItStartsLaunchesNoGit() async throws {
        let repository = try TemporaryGitRepository()
        let launched = repository.url.appendingPathComponent("git-launched")
        let executable = repository.url.appendingPathComponent("recording-git")
        try Data("#!/bin/sh\n: > '\(launched.path)'\n".utf8).write(to: executable, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let comparison = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await GitCLIRevisionProvider(executableURL: executable).comparison(
                repositoryURL: repository.url,
                base: "HEAD^",
                target: "HEAD"
            )
        }
        do {
            _ = try await comparison.value
            XCTFail("Expected the cancelled comparison to throw")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: launched.path))
        }
    }

    func testEnforcesChangedFileAndBlobLimits() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write("func first() {}\n", to: "First.swift")
        try repository.commit("base")
        try repository.write("func first() { print(1) }\n", to: "First.swift")
        try repository.write("func second() {}\n", to: "Second.swift")
        try repository.commit("target")

        do {
            _ = try await GitCLIRevisionProvider().comparison(
                repositoryURL: repository.url,
                base: "HEAD^",
                target: "HEAD",
                limits: AnalysisLimits(maximumChangedFiles: 1)
            )
            XCTFail("Expected changed-file limit")
        } catch let error as GitRevisionProviderError {
            XCTAssertEqual(error, .changedFileLimitExceeded(limit: 1, actual: 2))
        }

        do {
            _ = try await GitCLIRevisionProvider().comparison(
                repositoryURL: repository.url,
                base: "HEAD^",
                target: "HEAD",
                limits: AnalysisLimits(maximumBlobBytes: 4)
            )
            XCTFail("Expected blob limit")
        } catch let error as GitRevisionProviderError {
            guard case let .blobLimitExceeded(_, 4, actual) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(actual, 4)
        }
    }

    func testMissingRepositoryIsRejectedBeforeLaunchingGit() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowdelta-missing-\(UUID().uuidString)", isDirectory: true)

        do {
            _ = try await GitCLIRevisionProvider().comparison(
                repositoryURL: missing,
                base: "HEAD^",
                target: "HEAD"
            )
            XCTFail("Expected missing repository failure")
        } catch let error as GitRevisionProviderError {
            XCTAssertEqual(error, .repositoryNotFound(missing.path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testErrorDescriptionsPreserveActionableContext() {
        let errors: [(GitRevisionProviderError, String)] = [
            (.repositoryNotFound("/missing"), "/missing"),
            (.gitFailed(arguments: ["show", "HEAD:file"], status: 128, message: "bad revision"), "status 128"),
            (.invalidUTF8(context: "blob"), "non-UTF-8"),
            (.malformedNameStatus, "name-status"),
            (.changedFileLimitExceeded(limit: 2, actual: 3), "exceeding the limit of 2"),
            (.blobLimitExceeded(path: "Large.swift", limit: 4, actual: 9), "Large.swift")
        ]

        for (error, expected) in errors {
            XCTAssertTrue(error.description.contains(expected), error.description)
        }
    }
}

private final class TemporaryGitRepository: @unchecked Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDeltaGitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try git(["init", "-q"])
        try git(["config", "user.name", "FlowDelta Tests"])
        try git(["config", "user.email", "flowdelta@example.invalid"])
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ value: String, to path: String) throws {
        try write(Data(value.utf8), to: path)
    }

    func write(_ value: Data, to path: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try value.write(to: file, options: .atomic)
    }

    func move(_ path: String, to destination: String) throws {
        let target = url.appendingPathComponent(destination)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: url.appendingPathComponent(path), to: target)
    }

    func remove(_ path: String) throws {
        try FileManager.default.removeItem(at: url.appendingPathComponent(path))
    }

    func commit(_ message: String) throws {
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", message])
    }

    private func git(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path] + arguments
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "TemporaryGitRepository",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
