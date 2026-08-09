import FlowDeltaCore
import Foundation
import OSLog

public enum GitRevisionProviderError: Error, Equatable, Sendable, CustomStringConvertible {
    case repositoryNotFound(String)
    case gitFailed(arguments: [String], status: Int32, message: String)
    case invalidUTF8(context: String)
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

        let canonicalBase = try stringOutput(
            runGit(["rev-parse", "--verify", "\(base)^{commit}"], in: repositoryURL),
            context: "base revision"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalTarget = try stringOutput(
            runGit(["rev-parse", "--verify", "\(target)^{commit}"], in: repositoryURL),
            context: "target revision"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let statusData = try runGit(
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
            let oldSnapshot = try record.oldPath.map { path in
                try loadSnapshot(
                    path: path,
                    revision: canonicalBase,
                    repositoryURL: repositoryURL,
                    limits: limits
                )
            }
            let newSnapshot = try record.newPath.map { path in
                try loadSnapshot(
                    path: path,
                    revision: canonicalTarget,
                    repositoryURL: repositoryURL,
                    limits: limits
                )
            }
            let pathArguments = Array(Set([record.oldPath, record.newPath].compactMap(\.self))).sorted()
            let diff = try stringOutput(
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
        revision: String,
        repositoryURL: URL,
        limits: AnalysisLimits
    ) throws -> SourceSnapshot {
        let data = try runGit(["show", "\(revision):\(path)"], in: repositoryURL)
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
        guard let language = SourceLanguage(path: path) else {
            preconditionFailure("Unsupported source path passed through revision filtering: \(path)")
        }
        return SourceSnapshot(
            path: path,
            revision: RevisionIdentity(revision),
            language: language,
            text: text
        )
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws -> Data {
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
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
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
