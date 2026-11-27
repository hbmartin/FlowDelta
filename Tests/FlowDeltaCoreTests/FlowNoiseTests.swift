@testable import FlowDeltaCore
import XCTest

final class FlowNoiseTests: XCTestCase {
    private func node(
        _ name: String,
        _ state: DeltaState,
        noise: FlowNoiseLevel? = nil,
        triggers: [String] = []
    ) -> FlowNodeDelta {
        let id = StableID(rawValue: name)
        let flow = FlowNode(id: id, kind: .basicBlock, label: name, sourceOrder: 0)
        return FlowNodeDelta(
            id: id,
            old: state == .added ? nil : flow,
            new: state == .removed ? nil : flow,
            state: state,
            causality: triggers.map {
                CausalityLink(triggerID: StableID(rawValue: $0), affectedID: id, basis: .control, explanation: "")
            },
            noise: noise
        )
    }

    private func function(_ nodes: [FlowNodeDelta]) -> FunctionFlowDelta {
        FunctionFlowDelta(
            id: StableID(rawValue: "function"),
            entityChange: EntityChange(kind: .modified, old: nil, new: nil, confidence: nil),
            editScript: nil,
            oldGraph: nil,
            newGraph: nil,
            nodes: nodes,
            edges: []
        )
    }

    func testPoliciesHideFormattingThenOptionalSyntaxButNeverRewrites() {
        XCTAssertEqual(FlowNoiseLevel.allCases.filter(FlowNoisePolicy.showAll.hides), [])
        XCTAssertEqual(FlowNoiseLevel.allCases.filter(FlowNoisePolicy.hideFormatting.hides), [.formatting])
        XCTAssertEqual(
            FlowNoiseLevel.allCases.filter(FlowNoisePolicy.hideCosmetic.hides),
            [.formatting, .optionalSyntax]
        )
        XCTAssertFalse(FlowNoisePolicy.hideCosmetic.hides(nil))
        XCTAssertEqual(FlowNoisePolicy(rawValue: "hide-cosmetic"), .hideCosmetic)
        XCTAssertEqual(FlowNoisePolicy.allCases.map(\.displayName).count, 3)
        XCTAssertEqual(FlowNoiseLevel.allCases.map(\.displayName), ["formatting", "optional syntax", "rewrite"])
    }

    func testHiddenNodesShowAsRetainedAndPruneTheCausalityTheyTriggered() {
        let delta = function([
            node("comment", .modified, noise: .formatting),
            node("semicolon", .modified, noise: .optionalSyntax),
            node("real", .modified),
            node("onlyCosmetic", .affected, triggers: ["comment"]),
            node("mixed", .affected, triggers: ["comment", "real"])
        ])

        let result = FlowNoiseFilter.apply(.hideCosmetic, to: delta)
        let states = Dictionary(uniqueKeysWithValues: result.function.nodes.map { ($0.id.rawValue, $0.state) })
        XCTAssertEqual(states, [
            "comment": .retained, "semicolon": .retained, "real": .modified, "onlyCosmetic": .retained,
            "mixed": .affected
        ])
        XCTAssertEqual(result.hiddenNodeIDs.map(\.rawValue).sorted(), ["comment", "semicolon"])
        XCTAssertEqual(
            result.function.nodes.first { $0.id.rawValue == "mixed" }?.causality.map(\.triggerID.rawValue),
            ["real"]
        )
        XCTAssertEqual(
            result.function.nodes.first { $0.id.rawValue == "comment" }?.noise,
            .formatting,
            "The level is kept"
        )

        let formattingOnly = FlowNoiseFilter.apply(.hideFormatting, to: delta)
        XCTAssertEqual(formattingOnly.hiddenNodeIDs.map(\.rawValue), ["comment"])
        XCTAssertEqual(FlowNoiseFilter.apply(.showAll, to: delta).function, delta)
    }

    func testFunctionNoiseLevelIsTheHighestLevelWhenEveryChangeIsNoise() {
        XCTAssertEqual(FlowNoiseFilter.noiseLevel(of: function([
            node("a", .modified, noise: .formatting), node("b", .modified, noise: .optionalSyntax), node("c", .retained)
        ])), .optionalSyntax)
        XCTAssertEqual(FlowNoiseFilter.noiseLevel(of: function([node("a", .modified, noise: .rewrite)])), .rewrite)
        XCTAssertNil(FlowNoiseFilter.noiseLevel(of: function([
            node("a", .modified, noise: .formatting),
            node("b", .added)
        ])))
        XCTAssertNil(FlowNoiseFilter.noiseLevel(of: function([node("a", .modified)])))
        XCTAssertNil(FlowNoiseFilter.noiseLevel(of: function([node("a", .retained), node("b", .affected)])))
    }

    func testReportsWithoutNoiseStillDecode() throws {
        let json = #"{"id":"n","state":"modified","causality":[]}"#
        let decoded = try JSONDecoder().decode(FlowNodeDelta.self, from: Data(json.utf8))
        XCTAssertNil(decoded.noise)
    }
}
