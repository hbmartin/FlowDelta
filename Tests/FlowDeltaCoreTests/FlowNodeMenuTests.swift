import FlowDeltaCore
import XCTest

final class FlowNodeMenuTests: XCTestCase {
    func testDeltaNodesOfferSourceSlicesAndCopying() {
        let context = FlowNodeMenuContext(
            presentation: .delta,
            isCallNode: false,
            hasSourceLocation: true,
            isSliceActive: false
        )
        XCTAssertEqual(FlowNodeMenu.commands(for: context), [
            .showSource, nil, .forwardSlice, .backwardSlice, nil, .copyLabel, .copyLocation
        ])
        var sliced = context
        sliced.isSliceActive = true
        XCTAssertEqual(FlowNodeMenu.commands(for: sliced), [
            .showSource, nil, .forwardSlice, .backwardSlice, .clearSlice, nil, .copyLabel, .copyLocation
        ])
    }

    func testSlicesAreOnlyOfferedWhereTheyAreDrawn() {
        let context = FlowNodeMenuContext(
            presentation: .beforeAfter,
            isCallNode: false,
            hasSourceLocation: false,
            isSliceActive: false
        )
        XCTAssertEqual(FlowNodeMenu.commands(for: context), [.copyLabel])
    }

    func testCallNodesOfferReviewingTheirFunction() {
        let reviewable = FlowNodeMenuContext(
            presentation: .calls,
            isCallNode: true,
            hasSourceLocation: true,
            isSliceActive: false,
            hasReviewableFunction: true
        )
        XCTAssertEqual(
            FlowNodeMenu.commands(for: reviewable),
            [.reviewFunction, .showSource, nil, .copyLabel, .copyLocation]
        )
        let external = FlowNodeMenuContext(
            presentation: .calls,
            isCallNode: true,
            hasSourceLocation: false,
            isSliceActive: true
        )
        XCTAssertEqual(FlowNodeMenu.commands(for: external), [.copyLabel])
    }

    func testLocationsAreOneBased() {
        let start = SourceLocation(utf8Offset: 10, utf16Offset: 10, line: 4, utf16Column: 2)
        XCTAssertEqual(
            FlowNodeMenu.location(path: "Sources/Cart.swift", range: SourceRange(start: start, end: start)),
            "Sources/Cart.swift:5"
        )
    }
}
