import CoreGraphics
import FlowDeltaCore
import FlowDeltaLayout
import XCTest

final class GraphNavigatorTests: XCTestCase {
    //      entry
    //     /     \
    //  left     right
    //     \     /
    //      exit       far (lower, offset)
    private let entry = StableID(rawValue: "entry")
    private let left = StableID(rawValue: "left")
    private let right = StableID(rawValue: "right")
    private let exit = StableID(rawValue: "exit")
    private let far = StableID(rawValue: "far")

    private var navigator: GraphNavigator {
        GraphNavigator(nodeFrames: [
            entry: CGRect(x: 100, y: 0, width: 80, height: 30),
            left: CGRect(x: 0, y: 80, width: 80, height: 30),
            right: CGRect(x: 200, y: 80, width: 80, height: 30),
            exit: CGRect(x: 100, y: 160, width: 80, height: 30),
            far: CGRect(x: 300, y: 240, width: 80, height: 30)
        ])
    }

    func testReadingOrderIsTopToBottomThenLeftToRight() {
        XCTAssertEqual(navigator.readingOrder, [entry, left, right, exit, far])
    }

    func testArrowsPreferTheNearestRowThenTheSmallestSidewaysOffset() {
        XCTAssertEqual(navigator.target(from: entry, move: .down), left, "Equal rows tie-break by stable ID")
        XCTAssertEqual(navigator.target(from: left, move: .right), right)
        XCTAssertEqual(navigator.target(from: right, move: .left), left)
        XCTAssertEqual(navigator.target(from: right, move: .down), exit)
        XCTAssertEqual(navigator.target(from: exit, move: .up), left)
        XCTAssertEqual(navigator.target(from: exit, move: .down), far)
        XCTAssertEqual(
            navigator.target(from: exit, move: .right),
            right,
            "With nothing in its row, the nearest row wins"
        )
    }

    func testMovesWithNowhereToGoKeepTheSelection() {
        XCTAssertEqual(navigator.target(from: entry, move: .up), entry)
        XCTAssertEqual(navigator.target(from: left, move: .left), left)
        XCTAssertEqual(navigator.target(from: far, move: .down), far)
    }

    func testFirstLastAndMissingSelections() {
        XCTAssertEqual(navigator.target(from: exit, move: .first), entry)
        XCTAssertEqual(navigator.target(from: exit, move: .last), far)
        XCTAssertEqual(navigator.target(from: nil, move: .down), entry)
        XCTAssertEqual(navigator.target(from: StableID(rawValue: "gone"), move: .last), far)
        XCTAssertNil(GraphNavigator(nodeFrames: [:]).target(from: nil, move: .right))
    }
}
