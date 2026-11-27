import FlowDeltaCore
import Foundation
import OSLog

public enum GitRevisionProviderError: Error, Equatable, Sendable, CustomStringConvertible {
    case repositoryNotFound(String)
    case gitFailed(arguments: [String], status: Int32, message: String)
    case invalidUTF8(context: String)
    case unsupportedSourcePath(String)
    case malformedNameStatus
    case changedFileLimitExceeded(limit: Int, actual: Int)
    case blobLimitExceeded(path: String, limit: Int, actual: Int)

    public var description: String {
        switch self {
        case let .repositoryNotFound(path):
            "Git repository not found at \(path)."
        case let .gitFailed(arguments, status, message):
            "git \(arguments.joined(separator: " ")) failed with status \(status): \(message)"
        case let .invalidUTF8(context):
            "Git returned non-UTF-8 data for \(context)."
        case let .unsupportedSourcePath(path):
            "Unsupported source path passed through revision filtering: \(path)."
        case .malformedNameStatus:
            "Git returned malformed NUL-delimited name-status data."
        case let .changedFileLimitExceeded(limit, actual):
            "Revision changes \(actual) files, exceeding the limit of \(limit)."
        case let .blobLimitExceeded(path, limit, actual):
            "Blob \(path) is \(actual) bytes, exceeding the limit of \(limit)."
        }
    }
}

public struct GitCLIRevisionProvider: RevisionProvider, Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Git")
    public let executableURL: URL

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.executableURL = executableURL
    }

    public func comparison(
        repositoryURL: URL,
        base: String,
        target: String,
        limits: AnalysisLimits = .default
    ) async throws -> RevisionComparison {
        let repositoryURL = repositoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repositoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw GitRevisionProviderError.repositoryNotFound(repositoryURL.path)
        }

        let canonicalBase = try await stringOutput(
            runGit(["rev-parse", "--verify", "\(base)^{commit}"], in: repositoryURL),
            context: "base revision"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalTarget = try await stringOutput(
            runGit(["rev-parse", "--verify", "\(target)^{commit}"], in: repositoryURL),
            context: "target revision"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let statusData = try await runGit(
            [
                "diff", "--name-status", "-z", "--find-renames", "--diff-filter=ACDMR",
                canonicalBase, canonicalTarget, "--"
            ],
            in: repositoryURL
        )
        let records = try parseNameStatus(statusData).filter { record in
            record.oldPath.flatMap(SourceLanguage.init(path:)) != nil
                || record.newPath.flatMap(SourceLanguage.init(path:)) != nil
        }
        guard records.count <= limits.maximumChangedFiles else {
            throw GitRevisionProviderError.changedFileLimitExceeded(
                limit: limits.maximumChangedFiles,
                actual: records.count
            )
        }

        var files: [FileComparison] = []
        files.reserveCapacity(records.count)
        for record in records {
            try Task.checkCancellation()
            let supportedOld = record.oldPath.flatMap { path in
                SourceLanguage(path: path).map { (path: path, language: $0) }
            }
            let supportedNew = record.newPath.flatMap { path in
                SourceLanguage(path: path).map { (path: path, language: $0) }
            }
            var oldSnapshot: SourceSnapshot?
            if let supportedOld {
                oldSnapshot = try await loadSnapshot(
                    path: supportedOld.path,
                    language: supportedOld.language,
                    revision: canonicalBase,
                    repositoryURL: repositoryURL,
                    limits: limits
                )
            }
            var newSnapshot: SourceSnapshot?
            if let supportedNew {
                newSnapshot = try await loadSnapshot(
                    path: supportedNew.path,
                    language: supportedNew.language,
                    revision: canonicalTarget,
                    repositoryURL: repositoryURL,
                    limits: limits
                )
            }
            let pathArguments = Array(Set([record.oldPath, record.newPath].compactMap(\.self))).sorted()
            let diff = try await stringOutput(
                runGit(
                    ["diff", "-U0", "--no-color", "--find-renames", canonicalBase, canonicalTarget, "--"]
                        + pathArguments,
                    in: repositoryURL
                ),
                context: "diff for \(record.newPath ?? record.oldPath ?? "file")"
            )
            files.append(FileComparison(old: oldSnapshot, new: newSnapshot, unifiedDiff: diff))
        }

        Self.logger.notice(
            "Loaded \(files.count) changed source files from \(canonicalBase, privacy: .public) to \(canonicalTarget, privacy: .public)"
        )
        return RevisionComparison(
            base: RevisionIdentity(canonicalBase),
            target: RevisionIdentity(canonicalTarget),
            files: files
        )
    }

    private func loadSnapshot(
        path: String,
        language: SourceLanguage,
        revision: String,
        repositoryURL: URL,
        limits: AnalysisLimits
    ) async throws -> SourceSnapshot {
        let data = try await runGit(["show", "\(revision):\(path)"], in: repositoryURL)
        guard data.count <= limits.maximumBlobBytes else {
            throw GitRevisionProviderError.blobLimitExceeded(
                path: path,
                limit: limits.maximumBlobBytes,
                actual: data.count
            )
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw GitRevisionProviderError.invalidUTF8(context: path)
        }
        return SourceSnapshot(
            path: path,
            revision: RevisionIdentity(revision),
            language: language,
            text: text
        )
    }

    /// Runs git and returns its output. Cancelling the calling task terminates git and throws `CancellationError`.
    private func runGit(_ arguments: [String], in repositoryURL: URL) async throws -> Data {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-C", repositoryURL.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let running = RunningGit(process)
        // The handler covers reading, waiting and collecting error output, so cancelling terminates git even after
        // it has closed its output. Error output drains on another thread so a full pipe cannot stall git.
        let (outputData, errorData) = await withTaskCancellationHandler {
            let errorOutput = PipeDrain(error.fileHandleForReading)
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (outputData, errorOutput.wait())
        } onCancel: {
            Self.logger.info(
                "Terminating git \(arguments.first ?? "", privacy: .public) because its revision comparison was cancelled"
            )
            running.terminate()
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw GitRevisionProviderError.gitFailed(
                arguments: arguments,
                status: process.terminationStatus,
                message: String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            )
        }
        return outputData
    }

    private func stringOutput(_ data: Data, context: String) throws -> String {
        guard let value = String(data: data, encoding: .utf8) else {
            throw GitRevisionProviderError.invalidUTF8(context: context)
        }
        return value
    }

    private func parseNameStatus(_ data: Data) throws -> [NameStatusRecord] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: true)
        var index = 0
        var records: [NameStatusRecord] = []
        while index < fields.count {
            guard let status = String(data: fields[index], encoding: .utf8) else {
                throw GitRevisionProviderError.invalidUTF8(context: "name status")
            }
            index += 1
            if status.hasPrefix("R") {
                guard index + 1 < fields.count,
                      let oldPath = String(data: fields[index], encoding: .utf8),
                      let newPath = String(data: fields[index + 1], encoding: .utf8)
                else { throw GitRevisionProviderError.malformedNameStatus }
                records.append(NameStatusRecord(oldPath: oldPath, newPath: newPath))
                index += 2
            } else {
                guard index < fields.count,
                      let path = String(data: fields[index], encoding: .utf8)
                else { throw GitRevisionProviderError.malformedNameStatus }
                switch status.first {
                case "A": records.append(NameStatusRecord(oldPath: nil, newPath: path))
                case "D": records.append(NameStatusRecord(oldPath: path, newPath: nil))
                case "M", "C": records.append(NameStatusRecord(oldPath: path, newPath: path))
                default: throw GitRevisionProviderError.malformedNameStatus
                }
                index += 1
            }
        }
        return records
    }
}

private struct NameStatusRecord {
    let oldPath: String?
    let newPath: String?
}

// swift6-safety-justification: the box is immutable, and Process.terminate(), isRunning and kill(2) may be used from
// any thread.
/// Hands the running git process to the cancellation handler, which can run on any thread.
private final class RunningGit: @unchecked Sendable {
    /// How long git has to exit after SIGTERM before it is killed.
    static let terminationGracePeriod: DispatchTimeInterval = .seconds(2)

    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Git")
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    /// Sends SIGTERM, then SIGKILL if git is still running after the grace period, so a git or wrapper that ignores
    /// SIGTERM cannot keep a cancelled comparison waiting. The waiting caller reaps the process.
    func terminate() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.terminationGracePeriod) { [self] in
            guard process.isRunning else { return }
            Self.logger.error("git \(pid, privacy: .public) ignored SIGTERM; sending SIGKILL")
            kill(pid, SIGKILL)
        }
    }
}

// swift6-safety-justification: only the reading thread writes `data`, and `wait()` reads it after the semaphore.
/// Reads a pipe to its end on another thread. The semaphore publishes the data to `wait()`.
private final class PipeDrain: @unchecked Sendable {
    private let finished = DispatchSemaphore(value: 0)
    private var data = Data()

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .utility).async { [self] in
            data = handle.readDataToEndOfFile()
            finished.signal()
        }
    }

    func wait() -> Data {
        finished.wait()
        return data
    }
}
