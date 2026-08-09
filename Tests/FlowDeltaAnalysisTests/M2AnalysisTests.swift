import FlowDeltaAnalysis
import FlowDeltaCore
import XCTest

final class M2AnalysisTests: XCTestCase {
    func testEveryM2LanguageBuildsBranchAndLoopControlFlow() throws {
        let fixtures: [(SourceLanguage, String, String)] = [
            (
                .swift,
                "Fixture.swift",
                """
                func total(_ values: [Int]) -> Int {
                    var sum = 0
                    for value in values {
                        if value > 0 { sum += value }
                    }
                    return sum
                }
                """
            ),
            (
                .typescript,
                "fixture.ts",
                """
                export function total(values: number[]): number {
                    let sum = 0;
                    for (const value of values) {
                        if (value > 0) { sum += value; }
                    }
                    return sum;
                }
                """
            ),
            (
                .javascript,
                "fixture.js",
                """
                export function total(values) {
                    let sum = 0;
                    for (const value of values) {
                        if (value > 0) { sum += value; }
                    }
                    return sum;
                }
                """
            ),
            (
                .python,
                "fixture.py",
                """
                def total(values):
                    result = 0
                    for value in values:
                        if value > 0:
                            result += value
                    return result
                """
            ),
            (
                .go,
                "fixture.go",
                """
                package fixture

                func total(values []int) int {
                    sum := 0
                    for _, value := range values {
                        if value > 0 { sum += value }
                    }
                    return sum
                }
                """
            )
        ]

        for (language, path, text) in fixtures {
            let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
                path: path,
                revision: RevisionIdentity("fixture"),
                language: language,
                text: text
            ))
            let graph = try XCTUnwrap(analysis.graphs.values.first, language.displayName)
            let edgeKinds = Set(graph.edges.map(\.kind))

            XCTAssertTrue(graph.nodes.contains { $0.kind == .condition }, language.displayName)
            XCTAssertTrue(edgeKinds.contains(.conditionTrue), language.displayName)
            XCTAssertTrue(edgeKinds.contains(.conditionFalse), language.displayName)
            XCTAssertTrue(edgeKinds.contains(.loopBack), language.displayName)
            XCTAssertTrue(edgeKinds.contains(.returnFlow), language.displayName)
            XCTAssertEqual(analysis.dataGraphs.isEmpty, language == .python || language == .go)
        }
    }

    func testJavaScriptBuildsSwitchExceptionAndLoopTransferFlow() throws {
        let text = """
        export function inspect(values) {
            for (const value of values) {
                if (value < 0) {
                    continue;
                } else {
                    consume(value);
                }
                switch (value) {
                case 0:
                    break;
                default:
                    try {
                        if (value > 10) { throw new Error("large"); }
                    } catch (error) {
                        report(error);
                    } finally {
                        cleanup();
                    }
                }
            }
            return values.length;
        }
        """
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "inspect.js",
            revision: RevisionIdentity("fixture"),
            language: .javascript,
            text: text
        ))
        let graph = try XCTUnwrap(analysis.graphs.values.first)
        let kinds = Set(graph.edges.map(\.kind))

        XCTAssertTrue(graph.nodes.contains { $0.kind == .switchCase })
        XCTAssertTrue(graph.nodes.contains { $0.kind == .catchBlock })
        XCTAssertTrue(kinds.contains(.switchCase))
        XCTAssertTrue(kinds.contains(.catchFlow))
        XCTAssertTrue(kinds.contains(.throwFlow))
        XCTAssertTrue(kinds.contains(.continueFlow))
    }

    func testSwitchBreakTargetsSwitchJoinAndNoDefaultHasNoMatchPath() throws {
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "switch.js",
            revision: RevisionIdentity("fixture"),
            language: .javascript,
            text: """
            function inspect(value) {
                while (value > 0) {
                    switch (value) {
                    case 1:
                        break;
                    }
                    afterSwitch();
                    break;
                }
            }
            """
        ))
        let graph = try XCTUnwrap(analysis.graphs.values.first)
        let switchJoin = try XCTUnwrap(graph.nodes.first { $0.label == "after switch" })
        let switchBreak = try XCTUnwrap(
            graph.nodes.filter { $0.label.hasPrefix("break") }.min { $0.sourceOrder < $1.sourceOrder }
        )
        let switchDecision = try XCTUnwrap(graph.nodes.first { $0.label.hasPrefix("switch ") })

        XCTAssertTrue(graph.edges.contains {
            $0.source == switchBreak.id && $0.target == switchJoin.id && $0.kind == .breakFlow
        })
        XCTAssertTrue(graph.edges.contains {
            $0.source == switchDecision.id && $0.target == switchJoin.id && $0.kind == .conditionFalse
        })
        XCTAssertTrue(graph.nodes.contains { $0.label.contains("afterSwitch") })
    }

    func testJavaScriptSwitchModelsImplicitFallthrough() throws {
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "fallthrough.js",
            revision: RevisionIdentity("fixture"),
            language: .javascript,
            text: """
            function inspect(value) {
                switch (value) {
                case 1:
                    first();
                case 2:
                    second();
                    break;
                }
            }
            """
        ))
        let graph = try XCTUnwrap(analysis.graphs.values.first)
        let first = try XCTUnwrap(graph.nodes.first { $0.label.contains("first()") })
        let secondCase = try XCTUnwrap(graph.nodes.first {
            $0.kind == .switchCase && $0.label.contains("case 2")
        })

        XCTAssertTrue(graph.edges.contains {
            $0.source == first.id && $0.target == secondCase.id && $0.kind == .fallthrough
        })
    }

    func testGoSwitchFallsThroughOnlyWhenExplicit() throws {
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "fallthrough.go",
            revision: RevisionIdentity("fixture"),
            language: .go,
            text: """
            package fixture
            func inspect(value int) {
                switch value {
                case 1:
                    first()
                    fallthrough
                case 2:
                    second()
                }
                switch value {
                case 3:
                    third()
                case 4:
                    fourth()
                }
            }
            """
        ))
        let graph = try XCTUnwrap(analysis.graphs.values.first)
        let explicit = try XCTUnwrap(graph.nodes.first { $0.label == "fallthrough" })
        let secondCase = try XCTUnwrap(graph.nodes.first {
            $0.kind == .switchCase && $0.label.contains("case 2")
        })
        let third = try XCTUnwrap(graph.nodes.first { $0.label.contains("third()") })
        let fourthCase = try XCTUnwrap(graph.nodes.first {
            $0.kind == .switchCase && $0.label.contains("case 4")
        })

        XCTAssertTrue(graph.edges.contains { $0.source == explicit.id && $0.target == secondCase.id })
        XCTAssertFalse(graph.edges.contains { $0.source == third.id && $0.target == fourthCase.id })
    }

    func testOuterSwitchDoesNotImportNestedCases() throws {
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "nested-switch.js",
            revision: RevisionIdentity("fixture"),
            language: .javascript,
            text: """
            function inspect(outer, inner) {
                switch (outer) {
                case 1:
                    switch (inner) {
                    case 2:
                        consume();
                    }
                }
            }
            """
        ))
        let graph = try XCTUnwrap(analysis.graphs.values.first)
        let outer = try XCTUnwrap(
            graph.nodes.filter { $0.label.hasPrefix("switch ") && $0.label.contains("outer") }
                .min { $0.sourceOrder < $1.sourceOrder }
        )

        XCTAssertEqual(graph.outgoing(from: outer.id).count { $0.kind == .switchCase }, 1)
    }

    func testTryCatchFinallyRoutesThrowThroughCatchAndFinally() throws {
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "errors.js",
            revision: RevisionIdentity("fixture"),
            language: .javascript,
            text: """
            function inspect(value) {
                try {
                    throw value;
                } catch (error) {
                    recover(error);
                } finally {
                    cleanup();
                }
                after();
            }
            """
        ))
        let graph = try XCTUnwrap(analysis.graphs.values.first)
        let throwing = try XCTUnwrap(graph.nodes.first { $0.label.hasPrefix("throw ") })
        let dispatch = try XCTUnwrap(graph.nodes.first { $0.label == "catch" })
        let catchNode = try XCTUnwrap(graph.nodes.first { $0.kind == .catchBlock })
        let finalizer = try XCTUnwrap(graph.nodes.first { $0.kind == .deferBlock && $0.label == "finally" })
        let cleanup = try XCTUnwrap(graph.nodes.first { $0.label.contains("cleanup()") })
        let after = try XCTUnwrap(graph.nodes.first { $0.label.contains("after()") })

        XCTAssertTrue(graph.edges.contains {
            $0.source == throwing.id && $0.target == dispatch.id && $0.kind == .throwFlow
        })
        XCTAssertFalse(graph.edges.contains { $0.source == throwing.id && $0.target == graph.errorExitID })
        XCTAssertTrue(graph.edges.contains {
            $0.source == dispatch.id && $0.target == catchNode.id && $0.kind == .catchFlow
        })
        XCTAssertFalse(graph.incoming(to: finalizer.id).isEmpty)
        XCTAssertTrue(hasPath(from: cleanup.id, to: after.id, graph: graph))
    }

    func testReturnInsideTryExecutesFinallyBeforeExit() throws {
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "return-finally.js",
            revision: RevisionIdentity("fixture"),
            language: .javascript,
            text: """
            function inspect() {
                try { return 1; }
                finally { cleanup(); }
            }
            """
        ))
        let graph = try XCTUnwrap(analysis.graphs.values.first)
        let returning = try XCTUnwrap(graph.nodes.first { $0.label.hasPrefix("return ") })
        let deferred = try XCTUnwrap(graph.outgoing(from: returning.id).first { $0.kind == .deferredFlow })

        XCTAssertEqual(graph.node(id: deferred.target)?.kind, .deferBlock)
        XCTAssertTrue(graph.edges
            .contains { $0.source == deferred.target && $0.target == graph.exitID && $0.kind == .returnFlow })
    }

    func testGenericControlFlowLimitsProduceDiagnostics() throws {
        let snapshot = SourceSnapshot(
            path: "limits.js",
            revision: RevisionIdentity("fixture"),
            language: .javascript,
            text: "function limited(value) { consume(value); return value; }"
        )

        let nodeLimited = try SourceAnalyzer().analyze(
            snapshot,
            limits: AnalysisLimits(maximumFlowNodesPerFunction: 0)
        )
        let edgeLimited = try SourceAnalyzer().analyze(
            snapshot,
            limits: AnalysisLimits(maximumFlowEdgesPerFunction: 0)
        )

        XCTAssertTrue(nodeLimited.diagnostics.contains { $0.code == .resourceLimit })
        XCTAssertTrue(edgeLimited.diagnostics.contains { $0.code == .resourceLimit })
        XCTAssertTrue(nodeLimited.graphs.isEmpty)
        XCTAssertTrue(edgeLimited.graphs.isEmpty)
    }

    func testRemovingAConditionClassifiesTheRemovedBranch() throws {
        let old = """
        function normalize(value) {
            if (value < 0) { return 0; }
            return value;
        }
        """
        let new = """
        function normalize(value) {
            return value;
        }
        """

        let delta = try XCTUnwrap(
            analyze(old: old, new: new, path: "normalize.js", language: .javascript).functionDeltas.first
        )

        XCTAssertTrue(delta.classifications.contains(.branchRemoved))
        XCTAssertTrue(delta.nodes.contains { $0.state == .removed && $0.old?.kind == .condition })
    }

    func testTSXParserUsesTypeScriptEntitiesAndRecoversMalformedInput() throws {
        let text = """
        export class Counter {
            increment = (value: number) => value + 1
            broken(value: number) { return value + }
        }
        """
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "Counter.tsx",
            revision: RevisionIdentity("fixture"),
            language: .typescript,
            text: text
        ))

        XCTAssertTrue(analysis.entities.contains { $0.name == "Counter" && $0.kind == .type })
        XCTAssertTrue(analysis.entities.contains { $0.name == "increment" && $0.kind == .method })
        XCTAssertTrue(analysis.entities.contains { $0.name == "broken" && $0.kind == .method })
        XCTAssertTrue(analysis.diagnostics.contains { $0.code == .partialParse })
    }

    func testDataFlowDeltaMarksUnchangedUseAsDataAffectedAndSupportsBackwardSlice() throws {
        let old = """
        func invoice(_ value: Int, tax: Int) {
            var subtotal = value
            print(subtotal)
        }
        """
        let new = """
        func invoice(_ value: Int, tax: Int) {
            var subtotal = value
            if tax > 0 { subtotal += tax }
            print(subtotal)
        }
        """
        let report = try analyze(old: old, new: new, path: "Invoice.swift", language: .swift)
        let delta = try XCTUnwrap(report.functionDeltas.first)
        let nodeSummary = delta.nodes.map { node in
            let label = (node.new ?? node.old)?.label ?? "missing"
            return "\(node.state.rawValue):\(label):\(node.causality.map(\.basis.rawValue))"
        }
        let dataSummary = delta.dataFlow?.edges.map { edge in
            "\(edge.state.rawValue):\((edge.new ?? edge.old)?.symbol ?? "missing")"
        } ?? []
        let dataAffected = try XCTUnwrap(
            delta.nodes.first { node in
                node.state == .affected && node.causality.contains { $0.basis == .data }
            },
            "Nodes: \(nodeSummary) • Data: \(dataSummary)"
        )

        XCTAssertFalse(delta.dataFlow?.edges.isEmpty ?? true)
        XCTAssertTrue(dataAffected.causality.contains { $0.explanation.contains("Data dependency") })
        XCTAssertGreaterThan(delta.backwardSlice(from: dataAffected.id).count, 1)
    }

    func testTypeScriptDataFlowTracksDefinitionsAndUses() throws {
        let text = """
        function format(value: number): string {
            const doubled = value * 2;
            const label = String(doubled);
            return label;
        }
        """
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "format.ts",
            revision: RevisionIdentity("fixture"),
            language: .typescript,
            text: text
        ))
        let graph = try XCTUnwrap(analysis.dataGraphs.values.first)

        XCTAssertTrue(graph.edges.contains { $0.symbol == "doubled" })
        XCTAssertTrue(graph.edges.contains { $0.symbol == "label" })
    }

    func testDataFlowSeedsParametersAndMergesBranchDefinitions() throws {
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "reaching.js",
            revision: RevisionIdentity("fixture"),
            language: .javascript,
            text: """
            function inspect(value, condition) {
                let result = value;
                if (condition) { result = 1; }
                print(result);
            }
            """
        ))
        let control = try XCTUnwrap(analysis.graphs.values.first)
        let data = try XCTUnwrap(analysis.dataGraphs.values.first)
        let printNode = try XCTUnwrap(control.nodes.first { $0.label.contains("print(result)") })
        let valueUse = try XCTUnwrap(data.edges.first { $0.symbol == "value" })
        let reachingResultDefinitions = Set(data.edges.filter {
            $0.symbol == "result" && $0.use == printNode.id
        }.map(\.definition))

        XCTAssertEqual(valueUse.definition, control.entryID)
        XCTAssertEqual(reachingResultDefinitions.count, 2)
    }

    func testDataFlowUsesFullSyntaxAndDoesNotDefineMemberNames() throws {
        let padding = Array(repeating: "padding", count: 16).joined(separator: " + ")
        let analysis = try SourceAnalyzer().analyze(SourceSnapshot(
            path: "facts.js",
            revision: RevisionIdentity("fixture"),
            language: .javascript,
            text: """
            function inspect(value, object) {
                object.value = 2;
                const result = \(padding) + value;
                return result;
            }
            """
        ))
        let control = try XCTUnwrap(analysis.graphs.values.first)
        let data = try XCTUnwrap(analysis.dataGraphs.values.first)
        let memberAssignment = try XCTUnwrap(control.nodes.first { $0.label.contains("object.value") })
        let longStatement = try XCTUnwrap(control.nodes.first { $0.label.hasPrefix("const result") })

        XCTAssertFalse(data.edges.contains { $0.symbol == "value" && $0.definition == memberAssignment.id })
        XCTAssertTrue(data.edges.contains {
            $0.symbol == "value" && $0.definition == control.entryID && $0.use == longStatement.id
        })
    }

    func testCallGraphReportsChangedNeighborhoodAndExternalCalls() throws {
        let old = """
        func helper() {}
        func caller() { helper() }
        """
        let new = """
        func helper() {}
        func caller() { helper(); audit() }
        """
        let report = try analyze(old: old, new: new, path: "Calls.swift", language: .swift)
        let graph = try XCTUnwrap(report.callGraph)
        let caller = try XCTUnwrap(graph.nodes.first { $0.name.hasPrefix("caller") })
        let neighborhood = graph.neighborhood(around: [caller.id], radius: 1)

        XCTAssertTrue(neighborhood.nodes.contains { $0.name.hasPrefix("helper") && !$0.external })
        XCTAssertTrue(neighborhood.nodes.contains { $0.name == "audit" && $0.external })
        XCTAssertTrue(neighborhood.edges.contains { $0.caller == caller.id && $0.state == .added })
    }

    private func hasPath(from source: StableID, to target: StableID, graph: ControlFlowGraph) -> Bool {
        var visited: Set<StableID> = []
        var pending = [source]
        while let next = pending.popLast() {
            if next == target {
                return true
            }
            guard visited.insert(next).inserted else { continue }
            pending.append(contentsOf: graph.outgoing(from: next).map(\.target))
        }
        return false
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
