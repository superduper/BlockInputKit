import XCTest
@testable import BlockInputKit

final class BlockInputLinearSelectionLadderTests: XCTestCase {
    func testSelectedBoundsNormalizeAnchorAndFocus() {
        let ladder = BlockInputLinearSelectionLadder(anchor: 4, focus: 1, bounds: 0...5)

        XCTAssertEqual(ladder.selectedBounds, 1...4)
        XCTAssertFalse(ladder.isCollapsedAtAnchor)
        XCTAssertFalse(ladder.coversBounds)
    }

    func testFocusAfterMovingStopsAtBounds() {
        let middle = BlockInputLinearSelectionLadder(anchor: 1, focus: 1, bounds: 0...2)
        XCTAssertEqual(middle.focusAfterMoving(.upward), 0)
        XCTAssertEqual(middle.focusAfterMoving(.downward), 2)

        XCTAssertNil(BlockInputLinearSelectionLadder(anchor: 0, focus: 0, bounds: 0...2).focusAfterMoving(.upward))
        XCTAssertNil(BlockInputLinearSelectionLadder(anchor: 2, focus: 2, bounds: 0...2).focusAfterMoving(.downward))
    }

    func testExpansionClampsAtOuterBounds() {
        XCTAssertEqual(
            BlockInputLinearSelectionLadder.boundsAfterExpanding(1...2, direction: .upward, within: 0...3),
            0...2
        )
        XCTAssertEqual(
            BlockInputLinearSelectionLadder.boundsAfterExpanding(1...2, direction: .downward, within: 0...3),
            1...3
        )
        XCTAssertEqual(
            BlockInputLinearSelectionLadder.boundsAfterExpanding(0...3, direction: .downward, within: 0...3),
            0...3
        )
    }

    func testContractionDropsActiveExpansionEdge() {
        XCTAssertEqual(
            BlockInputLinearSelectionLadder.boundsAfterContracting(0...2, expansionDirection: .upward),
            1...2
        )
        XCTAssertEqual(
            BlockInputLinearSelectionLadder.boundsAfterContracting(0...2, expansionDirection: .downward),
            0...1
        )
        XCTAssertNil(BlockInputLinearSelectionLadder.boundsAfterContracting(1...1, expansionDirection: .downward))
    }

    func testWholeSelectionDemotionDropsActiveExpansionEdge() {
        XCTAssertEqual(
            BlockInputLinearSelectionLadder.boundsAfterDemotingWholeSelection(within: 0...2, expansionDirection: .upward),
            1...2
        )
        XCTAssertEqual(
            BlockInputLinearSelectionLadder.boundsAfterDemotingWholeSelection(within: 0...2, expansionDirection: .downward),
            0...1
        )
        XCTAssertNil(BlockInputLinearSelectionLadder.boundsAfterDemotingWholeSelection(within: 0...0, expansionDirection: .upward))
    }

    func testEntryAndPromotedFocusEdgesMatchSelectionDirection() {
        let bounds = 0...2

        XCTAssertEqual(BlockInputLinearSelectionLadder.edgeIndex(in: bounds, direction: .downward), 0)
        XCTAssertEqual(BlockInputLinearSelectionLadder.edgeIndex(in: bounds, direction: .upward), 2)
        XCTAssertEqual(BlockInputLinearSelectionLadder.promotedFocusIndex(in: bounds, direction: .downward), 2)
        XCTAssertEqual(BlockInputLinearSelectionLadder.promotedFocusIndex(in: bounds, direction: .upward), 0)
    }

    func testBoundsForCountRejectsEmptyCollections() {
        XCTAssertEqual(BlockInputLinearSelectionLadder.bounds(count: 3), 0...2)
        XCTAssertNil(BlockInputLinearSelectionLadder.bounds(count: 0))
    }
}
