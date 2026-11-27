@testable import FlowDeltaCore
import XCTest

final class FlowWalkthroughTests: XCTestCase {
    /// entry → a → b → c → d → exit in the target; the base also had `gone` between b and c.
    private func function(
        states: [String: DeltaState],
        noise: [String: FlowNoiseLevel] = [:],
        causality: [String: [(trigger: String, basis: AffectedBasis)]] = [:]
    ) -> FunctionFlowDelta {
        let newOrder = ["entry", "a", "b", "c", "d", "exit"]
        let oldOrder = ["entry", "a", "b", "gone", "c", "d", "exit"]
        func graph(_ order: [String], prefix: String) -> ControlFlowGraph {
            let nodes = order.enumerated().map { index, name in
                FlowNode(
                    id: StableID(rawValue: prefix + name),
                    kind: kind(of: name),
                    label: "\(name)()",
                    sourceOrder: index
                )
            }
            let edges = zip(order, order.dropFirst()).map { source, target in
                FlowEdge(
                    source: StableID(rawValue: prefix + source),
                    target: StableID(rawValue: prefix + target),
                    kind: .fallthrough
                )
            }
            return ControlFlowGraph(
                entityID: StableID(rawValue: "entity"),
                nodes: nodes + [FlowNode(
                    id: StableID(rawValue: prefix + "error"),
                    kind: .errorExit,
                    label: "Error Exit",
                    sourceOrder: 99
                )],
                edges: edges,
                entryID: StableID(rawValue: prefix + "entry"),
                exitID: StableID(rawValue: prefix + "exit"),
                errorExitID: StableID(rawValue: prefix + "error")
            )
        }
        let oldGraph = graph(oldOrder, prefix: "old.")
        let newGraph = graph(newOrder, prefix: "new.")
        let names = Set(oldOrder + newOrder)
        let nodes = names.map { name -> FlowNodeDelta in
            let state = states[name] ?? .retained
            let id = StableID(rawValue: name)
            return FlowNodeDelta(
                id: id,
                old: state == .added || !oldOrder.contains(name) ? nil : oldGraph
                    .node(id: StableID(rawValue: "old." + name)),
                new: state == .removed || !newOrder.contains(name) ? nil : newGraph
                    .node(id: StableID(rawValue: "new." + name)),
                state: state,
                causality: (causality[name] ?? []).map {
                    CausalityLink(
                        triggerID: StableID(rawValue: $0.trigger),
                        affectedID: id,
                        basis: $0.basis,
                        explanation: ""
                    )
                },
                noise: noise[name]
            )
        }
        return FunctionFlowDelta(
            id: StableID(rawValue: "function.\(states.keys.sorted().joined())"),
            entityChange: EntityChange(kind: .modified, old: nil, new: nil, confidence: nil),
            editScript: nil,
            oldGraph: oldGraph,
            newGraph: newGraph,
            nodes: nodes,
            edges: []
        )
    }

    private func kind(of name: String) -> FlowNodeKind {
        switch name {
        case "entry": .entry
        case "exit": .exit
        default: .basicBlock
        }
    }

    func testConnectedChangesFormOneStepAndStepsFollowControlOrder() {
        let delta = function(
            states: ["d": .modified, "a": .added, "b": .modified, "gone": .removed],
            causality: ["c": [("gone", .control)]]
        )
        let steps = FlowWalkthrough.steps(for: delta)
        XCTAssertEqual(steps.map { $0.nodeIDs.map(\.rawValue) }, [["a", "b", "gone"], ["d"]])
        XCTAssertEqual(steps.map(\.affectedNodeIDs), [[StableID(rawValue: "c")], []])
        XCTAssertEqual(steps[0].narration, "Changes `a()` and 2 more statements — affects 1 node by control.")
        XCTAssertEqual(steps[1].narration, "Changes `d()` to `d()`")
        XCTAssertEqual(steps[0].id, "\(delta.id.rawValue)#a")
        XCTAssertEqual(Set(steps.map(\.functionID)), [delta.id])
    }

    func testCodeSpansOutlastTheBackticksInTheirLabel() {
        XCTAssertEqual(FlowWalkthrough.code("a()"), "`a()`")
        XCTAssertEqual(FlowWalkthrough.code("return `<b>new</b>`"), "`` return `<b>new</b>` ``")
        XCTAssertEqual(FlowWalkthrough.code("a ``b`` c"), "```a ``b`` c```")
        XCTAssertEqual(FlowWalkthrough.code("first\nsecond"), "`first second`")
    }

    func testNarrationDescribesAddsRemovesRewritesAndTheBasisOfWhatIsAffected() {
        func narration(
            _ states: [String: DeltaState],
            noise: [String: FlowNoiseLevel] = [:],
            causality: [String: [(trigger: String, basis: AffectedBasis)]] = [:]
        ) -> [String] {
            FlowWalkthrough.steps(for: function(states: states, noise: noise, causality: causality)).map(\.narration)
        }
        XCTAssertEqual(narration(["a": .added]), ["Adds `a()`"])
        XCTAssertEqual(narration(["a": .added, "b": .added]), ["Adds `a()` and 1 more statement"])
        XCTAssertEqual(narration(["gone": .removed]), ["Removes `gone()`"])
        XCTAssertEqual(narration(["a": .removed, "b": .removed]), ["Removes `a()` and 1 more statement"])
        XCTAssertEqual(
            narration(["a": .modified], noise: ["a": .rewrite]),
            ["Changes `a()` to `a()` (equivalent rewrite)"]
        )
        XCTAssertEqual(
            narration(["a": .modified], causality: ["b": [("a", .data)], "c": [("a", .control), ("a", .data)]]),
            ["Changes `a()` to `a()` — affects 2 nodes by control and data."]
        )
        XCTAssertEqual(
            narration(["a": .modified], causality: ["b": [("a", .data)]]),
            ["Changes `a()` to `a()` — affects 1 node by data."]
        )
        XCTAssertEqual(narration([:]), [])
    }

    func testReportStepsFollowTriageOrderUseThePolicyAndAcceptAHostOrder() {
        let first = function(states: ["a": .added])
        let cosmetic = function(states: ["b": .modified], noise: ["b": .formatting])
        let path = "A.swift"
        let revision = RevisionIdentity("r")
        let snapshot = SourceSnapshot(path: path, revision: revision, language: .swift, text: "")
        let file = FileFlowDelta(
            comparison: FileComparison(old: snapshot, new: snapshot),
            entityChanges: [first.entityChange],
            functionDeltas: [first]
        )
        // Both functions share an empty entity change, so give the cosmetic one its own file.
        let otherSnapshot = SourceSnapshot(path: "Other.swift", revision: revision, language: .swift, text: "")
        let other = FileFlowDelta(
            comparison: FileComparison(old: otherSnapshot, new: otherSnapshot),
            entityChanges: [cosmetic.entityChange],
            functionDeltas: [cosmetic]
        )
        let report = RevisionFlowDeltaReport(base: revision, target: revision, files: [file, other])

        XCTAssertEqual(FlowWalkthrough.steps(for: report, policy: .showAll).map(\.functionID), [first.id, cosmetic.id])
        XCTAssertEqual(FlowWalkthrough.steps(for: report, policy: .hideCosmetic).map(\.functionID), [first.id])
        XCTAssertEqual(
            FlowWalkthrough.steps(for: report, policy: .showAll, functionOrder: [cosmetic.id, first.id])
                .map(\.functionID),
            [cosmetic.id, first.id]
        )
    }
}
