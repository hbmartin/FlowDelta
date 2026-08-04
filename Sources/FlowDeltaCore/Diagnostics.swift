import Foundation

public enum DiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case information
    case warning
    case error
}

public enum DiagnosticCode: String, Codable, CaseIterable, Sendable {
    case partialParse
    case resourceLimit
    case unsupportedConstruct
    case internalInvariant
}

public struct AnalysisDiagnostic: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let severity: DiagnosticSeverity
    public let code: DiagnosticCode
    public let message: String
    public let path: String?
    public let range: SourceRange?

    public init(
        severity: DiagnosticSeverity,
        code: DiagnosticCode,
        message: String,
        path: String? = nil,
        range: SourceRange? = nil
    ) {
        id = StableID(
            namespace: "diagnostic",
            components: [severity.rawValue, code.rawValue, path ?? "", message]
        )
        self.severity = severity
        self.code = code
        self.message = message
        self.path = path
        self.range = range
    }
}

public struct AnalysisLimits: Codable, Hashable, Sendable {
    public var maximumChangedFiles: Int
    public var maximumBlobBytes: Int
    public var maximumSyntaxNodesPerFile: Int
    public var maximumSyntaxNodesPerEntity: Int
    public var maximumFlowNodesPerFunction: Int
    public var maximumFlowEdgesPerFunction: Int

    public init(
        maximumChangedFiles: Int = 500,
        maximumBlobBytes: Int = 2 * 1_024 * 1_024,
        maximumSyntaxNodesPerFile: Int = 100_000,
        maximumSyntaxNodesPerEntity: Int = 10_000,
        maximumFlowNodesPerFunction: Int = 500,
        maximumFlowEdgesPerFunction: Int = 2_000
    ) {
        self.maximumChangedFiles = maximumChangedFiles
        self.maximumBlobBytes = maximumBlobBytes
        self.maximumSyntaxNodesPerFile = maximumSyntaxNodesPerFile
        self.maximumSyntaxNodesPerEntity = maximumSyntaxNodesPerEntity
        self.maximumFlowNodesPerFunction = maximumFlowNodesPerFunction
        self.maximumFlowEdgesPerFunction = maximumFlowEdgesPerFunction
    }

    public static let `default` = AnalysisLimits()
}
