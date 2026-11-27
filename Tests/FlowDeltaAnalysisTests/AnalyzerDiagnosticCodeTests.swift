@testable import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaParse
import XCTest

final class AnalyzerDiagnosticCodeTests: XCTestCase {
    private struct UnexpectedFailure: Error {}

    func testOnlyExceededLimitsAreResourceLimits() {
        XCTAssertEqual(
            FlowDeltaAnalyzer.diagnosticCode(for: SourceSyntaxParserError.nodeLimitExceeded(limit: 1)),
            .resourceLimit
        )
        XCTAssertEqual(
            FlowDeltaAnalyzer.diagnosticCode(for: SourceSyntaxParserError.parserInitialization),
            .internalInvariant
        )
        XCTAssertEqual(
            FlowDeltaAnalyzer.diagnosticCode(for: SourceSyntaxParserError.languageMismatch(
                expected: .swift,
                actual: .go
            )),
            .internalInvariant
        )
        XCTAssertEqual(FlowDeltaAnalyzer.diagnosticCode(for: UnexpectedFailure()), .internalInvariant)
    }
}
