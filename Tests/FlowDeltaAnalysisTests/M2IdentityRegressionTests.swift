import FlowDeltaAnalysis
import FlowDeltaCore
import XCTest

final class M2IdentityRegressionTests: XCTestCase {
    func testSwiftDataFlowSeedsLocalParameterNames() throws {
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "parameters.swift",
            revision: RevisionIdentity("fixture"),
            language: .swift,
            text: "func inspect(_ value: Int, labeled local: Int) { print(value + local) }"
        ))
        let control = try XCTUnwrap(analysis.graphs.values.first)
        let data = try XCTUnwrap(analysis.dataGraphs.values.first)

        XCTAssertTrue(data.edges.contains { $0.symbol == "value" && $0.definition == control.entryID })
        XCTAssertTrue(data.edges.contains { $0.symbol == "local" && $0.definition == control.entryID })
    }

    func testTypeScriptInterfaceMethodsRemainTriageOnly() throws {
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "Service.ts",
            revision: RevisionIdentity("fixture"),
            language: .typescript,
            text: "interface Service { fetch(value: string): void; }"
        ))
        let signature = try XCTUnwrap(analysis.entities.first { $0.name == "fetch" })

        XCTAssertEqual(signature.body.kind, "method_signature")
        XCTAssertNil(analysis.graphs[signature.id])
        XCTAssertNil(analysis.dataGraphs[signature.id])
    }

    func testGoMethodIdentityIncludesReceiverType() throws {
        let old = """
        package fixture
        type A struct{}
        type B struct{}
        func (a A) Run() int { return 1 }
        func (b B) Run() int { return 1 }
        """
        let new = """
        package fixture
        type A struct{}
        type B struct{}
        func (a A) Run() int { return 2 }
        func (b B) Run() int { return 1 }
        """
        let report = try analyze(old: old, new: new, path: "methods.go", language: .go)
        let methods = report.entityChanges.filter { ($0.new ?? $0.old)?.name == "Run" }

        XCTAssertEqual(Set(methods.compactMap { ($0.new ?? $0.old)?.qualifiedName }), ["A.Run()", "B.Run()"])
        XCTAssertEqual(methods.first { ($0.new ?? $0.old)?.qualifiedName == "A.Run()" }?.kind, .modified)
        XCTAssertEqual(methods.first { ($0.new ?? $0.old)?.qualifiedName == "B.Run()" }?.kind, .unchanged)
    }

    func testCallGraphDoesNotAttributeNestedFunctionCallsToOuterFunction() throws {
        let source = """
        function outer() {
            function inner() { audit(); }
            inner();
        }
        """
        let report = try analyze(old: source, new: source, path: "nested.js", language: .javascript)
        let graph = try XCTUnwrap(report.callGraph)
        let outer = try XCTUnwrap(graph.nodes.first { $0.name.hasPrefix("outer") })
        let inner = try XCTUnwrap(graph.nodes.first { $0.name.hasPrefix("inner") && !$0.external })
        let audit = try XCTUnwrap(graph.nodes.first { $0.name == "audit" })

        XCTAssertTrue(graph.edges.contains { $0.caller == inner.id && $0.callee == audit.id })
        XCTAssertFalse(graph.edges.contains { $0.caller == outer.id && $0.callee == audit.id })
    }

    private func analyze(
        old: String,
        new: String,
        path: String,
        language: SourceLanguage
    ) throws -> RevisionFlowDeltaReport {
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        return try FlowDeltaAnalyzer().analyze(RevisionComparison(
            base: base,
            target: target,
            files: [FileComparison(
                old: SourceSnapshot(path: path, revision: base, language: language, text: old),
                new: SourceSnapshot(path: path, revision: target, language: language, text: new)
            )]
        ))
    }
}
