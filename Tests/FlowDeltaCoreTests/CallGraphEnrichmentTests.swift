import FlowDeltaCore
import XCTest

/// `enrichingCallGraph(using:sourceFiles:)` hands the report's call graph to an enricher, such as the IndexStore
/// extension, and keeps everything else in the report.
final class CallGraphEnrichmentTests: XCTestCase {
    private struct EnrichmentFailure: Error {}

    // swift6-safety-justification: each test calls the enricher synchronously on one thread.
    /// Adds an edge from the first node to an external node and records what it was given.
    private final class RecordingEnricher: CallGraphEnriching, @unchecked Sendable {
        private(set) var calls: [(graph: CallGraph, sourceFiles: [String])] = []
        var fails = false

        func enrich(_ graph: CallGraph, sourceFiles: [String]) throws -> CallGraph {
            calls.append((graph, sourceFiles))
            if fails {
                throw EnrichmentFailure()
            }
            let external = CallGraphNode(
                id: StableID(rawValue: "external"),
                name: "print",
                state: .retained,
                external: true
            )
            return CallGraph(
                nodes: graph.nodes + [external],
                edges: graph.edges + [CallGraphEdge(caller: graph.nodes[0].id, callee: external.id, state: .added)]
            )
        }
    }

    private func report(callGraph: CallGraph?) -> RevisionFlowDeltaReport {
        RevisionFlowDeltaReport(
            base: RevisionIdentity("base"),
            target: RevisionIdentity("target"),
            files: [],
            callGraph: callGraph,
            diagnostics: [AnalysisDiagnostic(
                severity: .warning,
                code: .partialParse,
                message: "partial",
                path: "A.swift"
            )],
            concerns: [
                FlowConcern(
                    id: StableID(rawValue: "concern"),
                    kind: .behavioral,
                    title: "Totals",
                    memberIDs: [StableID(rawValue: "member")],
                    links: []
                )
            ]
        )
    }

    private var graph: CallGraph {
        CallGraph(
            nodes: [
                CallGraphNode(id: StableID(rawValue: "caller"), name: "total", state: .modified),
                CallGraphNode(id: StableID(rawValue: "callee"), name: "tax", state: .retained)
            ],
            edges: [CallGraphEdge(
                caller: StableID(rawValue: "caller"),
                callee: StableID(rawValue: "callee"),
                state: .retained
            )]
        )
    }

    func testEnrichmentReplacesOnlyTheCallGraph() throws {
        let enricher = RecordingEnricher()
        let original = report(callGraph: graph)

        let enriched = try original.enrichingCallGraph(using: enricher, sourceFiles: ["A.swift", "B.swift"])

        XCTAssertEqual(enricher.calls.count, 1)
        XCTAssertEqual(enricher.calls.first?.graph, graph)
        XCTAssertEqual(enricher.calls.first?.sourceFiles, ["A.swift", "B.swift"])
        XCTAssertEqual(enriched.callGraph?.nodes.map(\.name), ["tax", "total", "print"], "Nodes stay sorted by ID")
        XCTAssertEqual(enriched.callGraph?.edges.count, 2)
        XCTAssertEqual(enriched.base, original.base)
        XCTAssertEqual(enriched.target, original.target)
        XCTAssertEqual(enriched.files, original.files)
        XCTAssertEqual(enriched.diagnostics, original.diagnostics)
        XCTAssertEqual(enriched.concerns, original.concerns)
    }

    func testAReportWithoutACallGraphIsReturnedWithoutCallingTheEnricher() throws {
        let enricher = RecordingEnricher()
        let original = report(callGraph: nil)

        XCTAssertEqual(try original.enrichingCallGraph(using: enricher, sourceFiles: ["A.swift"]), original)
        XCTAssertTrue(enricher.calls.isEmpty)
    }

    func testAnEnricherFailureIsThrown() {
        let enricher = RecordingEnricher()
        enricher.fails = true

        XCTAssertThrowsError(try report(callGraph: graph).enrichingCallGraph(
            using: enricher,
            sourceFiles: []
        )) { error in
            XCTAssertTrue(error is EnrichmentFailure)
        }
    }
}
