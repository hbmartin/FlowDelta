import FlowDeltaAnalysis
import FlowDeltaCore
import XCTest

final class FlowDeltaAnalyzerTests: XCTestCase {
    func testRevisionAnalysisProducesAllNodeStatesAndControlCausality() throws {
        let report = try analyzeDemo()
        let states = Set(report.functionDeltas.flatMap { $0.nodes.map(\.state) })
        let affected = report.functionDeltas.flatMap(\.nodes).filter { $0.state == .affected }

        XCTAssertTrue(states.contains(.added))
        XCTAssertTrue(states.contains(.removed))
        XCTAssertTrue(states.contains(.retained))
        XCTAssertTrue(
            states.contains(.modified),
            report.functionDeltas
                .flatMap(\.nodes)
                .map { "\($0.state.rawValue):\(($0.new ?? $0.old)?.label ?? "<missing>")" }
                .joined(separator: " | ")
        )
        XCTAssertTrue(states.contains(.affected))
        XCTAssertFalse(affected.isEmpty)
        XCTAssertTrue(affected.allSatisfy { !$0.causality.isEmpty })
        XCTAssertTrue(affected.flatMap(\.causality).allSatisfy { $0.basis == .control })
        XCTAssertTrue(affected.flatMap(\.causality).allSatisfy { $0.explanation.contains("Control context") })
        let calculated = try XCTUnwrap(report.functionDeltas.first { $0.displayName.hasPrefix("calculate") })
        XCTAssertTrue(calculated.classifications.contains(.guardInserted))
        XCTAssertTrue(calculated.classifications.contains(.conditionChanged))
        XCTAssertTrue(calculated.classifications.contains(.earlyReturnAdded))
    }

    func testEveryProjectedDeltaHasValidSidesAndUniqueIdentity() throws {
        let report = try analyzeDemo()
        for function in report.functionDeltas {
            XCTAssertEqual(Set(function.nodes.map(\.id)).count, function.nodes.count)
            XCTAssertEqual(Set(function.edges.map(\.id)).count, function.edges.count)
            XCTAssertTrue(function.nodes.allSatisfy { $0.old != nil || $0.new != nil })
            XCTAssertTrue(function.edges.allSatisfy { $0.old != nil || $0.new != nil })
            XCTAssertTrue(function.nodes.filter { $0.state == .added }.allSatisfy { $0.old == nil && $0.new != nil })
            XCTAssertTrue(function.nodes.filter { $0.state == .removed }.allSatisfy { $0.old != nil && $0.new == nil })
        }
    }

    func testReportCountsEntityTriageAcrossAddedRemovedAndModifiedFunctions() throws {
        let report = try analyzeDemo()

        XCTAssertGreaterThanOrEqual(report.count(of: .added), 1)
        XCTAssertGreaterThanOrEqual(report.count(of: .removed), 1)
        XCTAssertGreaterThanOrEqual(report.count(of: .modified), 1)
        XCTAssertEqual(report.files.count, 1)
        XCTAssertEqual(report.functionDeltas.count, 3)
    }

    func testCommitScopeTriageRecognizesCrossFileMove() throws {
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        let moved = "func relocated(_ value: Int) -> Int { value * 2 }"
        let report = try FlowDeltaAnalyzer().analyze(RevisionComparison(
            base: base,
            target: target,
            files: [
                FileComparison(
                    old: SourceSnapshot(path: "Old.swift", revision: base, language: .swift, text: moved),
                    new: SourceSnapshot(path: "Old.swift", revision: target, language: .swift, text: "")
                ),
                FileComparison(
                    old: SourceSnapshot(path: "New.swift", revision: base, language: .swift, text: ""),
                    new: SourceSnapshot(path: "New.swift", revision: target, language: .swift, text: moved)
                )
            ]
        ))

        let change = try XCTUnwrap(report.entityChanges.first { $0.new?.name == "relocated" })
        XCTAssertEqual(change.kind, .moved)
        XCTAssertEqual(change.old?.path, "Old.swift")
        XCTAssertEqual(change.new?.path, "New.swift")
        XCTAssertEqual(change.confidence?.tier, .exactName)
    }

    func testCancelledAnalysisStopsWithACancellationError() async throws {
        let target = RevisionIdentity("target")
        let comparison = RevisionComparison(
            base: RevisionIdentity("base"),
            target: target,
            files: [FileComparison(
                old: nil,
                new: SourceSnapshot(
                    path: "New.swift",
                    revision: target,
                    language: .swift,
                    text: "func added() { print(1) }"
                )
            )]
        )
        let analysis = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FlowDeltaAnalyzer().analyze(comparison)
        }
        do {
            _ = try await analysis.value
            XCTFail("Expected the cancelled analysis to throw")
        } catch is CancellationError {}

        let entityAnalysis = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SourceAnalyzer().analyze(XCTUnwrap(comparison.files.first?.new))
        }
        do {
            _ = try await entityAnalysis.value
            XCTFail("Expected the cancelled file analysis to throw")
        } catch is CancellationError {}
    }

    func testRevisionAnalysisReportsFileResourceFailuresWithoutAborting() throws {
        let target = RevisionIdentity("target")
        let report = try FlowDeltaAnalyzer().analyze(
            RevisionComparison(
                base: RevisionIdentity("base"),
                target: target,
                files: [FileComparison(
                    old: nil,
                    new: SourceSnapshot(
                        path: "Oversized.swift",
                        revision: target,
                        language: .swift,
                        text: "func oversized() { print(1) }"
                    )
                )]
            ),
            limits: AnalysisLimits(maximumSyntaxNodesPerFile: 1)
        )

        let diagnostic = try XCTUnwrap(report.files.first?.diagnostics.first)
        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertEqual(diagnostic.code, .resourceLimit)
        XCTAssertEqual(report.diagnostics, [diagnostic])
        XCTAssertTrue(report.entityChanges.isEmpty)
    }

    func testRevisionAnalysisExplainsCallableSkippedByFlowGraphLimit() throws {
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        let report = try FlowDeltaAnalyzer().analyze(
            RevisionComparison(
                base: base,
                target: target,
                files: [FileComparison(
                    old: SourceSnapshot(
                        path: "Limited.swift",
                        revision: base,
                        language: .swift,
                        text: "func limited() {}"
                    ),
                    new: SourceSnapshot(
                        path: "Limited.swift",
                        revision: target,
                        language: .swift,
                        text: "func limited() { print(1) }"
                    )
                )]
            ),
            limits: AnalysisLimits(maximumFlowNodesPerFunction: 0)
        )

        XCTAssertTrue(report.functionDeltas.isEmpty)
        XCTAssertEqual(report.files.first?.entityChanges.first?.kind, .modified)
        XCTAssertTrue(report.files.first?.diagnostics.contains { $0.code == .unsupportedConstruct } == true)
        XCTAssertGreaterThanOrEqual(report.files.first?.diagnostics.count ?? 0, 3)
    }

    func testRemovedFunctionWithoutAGraphIsNamedFromItsBaseRevision() throws {
        let base = RevisionIdentity("base")
        let report = try FlowDeltaAnalyzer().analyze(
            RevisionComparison(
                base: base,
                target: RevisionIdentity("target"),
                files: [FileComparison(
                    old: SourceSnapshot(
                        path: "Removed.swift",
                        revision: base,
                        language: .swift,
                        text: "func kept() {}\nfunc removed() { print(1) }\n"
                    ),
                    new: SourceSnapshot(
                        path: "Removed.swift",
                        revision: RevisionIdentity("target"),
                        language: .swift,
                        text: "func kept() {}\n"
                    )
                )]
            ),
            limits: AnalysisLimits(maximumFlowNodesPerFunction: 0)
        )

        let removed = try XCTUnwrap(report.files.first?.entityChanges.first { $0.old?.name == "removed" })
        XCTAssertEqual(removed.kind, .removed)
        let diagnostic = try XCTUnwrap(report.files.first?.diagnostics.first {
            $0.message == "No flow graph was available for \(removed.old?.qualifiedName ?? "")."
        })
        XCTAssertEqual(diagnostic.code, .unsupportedConstruct)
        XCTAssertEqual(diagnostic.range, removed.old?.range)
    }

    private func analyzeDemo() throws -> RevisionFlowDeltaReport {
        let old = """
        func calculate(_ values: [Int], enabled: Bool) -> Int {
            var result = 0
            for value in values {
                if enabled {
                    result += value
                }
            }
            return result
        }

        func removed(_ values: [Int]) -> Int {
            values.reduce(0, +)
        }
        """
        let new = """
        func calculate(_ values: [Int], enabled: Bool) -> Int {
            guard !values.isEmpty else { return 0 }
            var result = 0
            for value in values {
                if enabled && value > 0 {
                    result += value
                }
            }
            return result
        }

        func added() {
            print("new")
        }
        """
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        return try FlowDeltaAnalyzer().analyze(RevisionComparison(
            base: base,
            target: target,
            files: [FileComparison(
                old: SourceSnapshot(path: "Demo.swift", revision: base, language: .swift, text: old),
                new: SourceSnapshot(path: "Demo.swift", revision: target, language: .swift, text: new),
                unifiedDiff: "@@ demo @@"
            )]
        ))
    }
}
