import FlowDeltaCore
import Foundation

public protocol RevisionProvider: Sendable {
    func comparison(
        repositoryURL: URL,
        base: String,
        target: String,
        limits: AnalysisLimits
    ) async throws -> RevisionComparison
}

public extension RevisionProvider {
    func comparison(
        repositoryURL: URL,
        base: String,
        target: String
    ) async throws -> RevisionComparison {
        try await comparison(
            repositoryURL: repositoryURL,
            base: base,
            target: target,
            limits: .default
        )
    }
}
