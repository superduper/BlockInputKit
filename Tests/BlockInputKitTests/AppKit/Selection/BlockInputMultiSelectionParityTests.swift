import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputMultiSelectionParityTests: XCTestCase {
    func testShiftDownAndMouseDragCreateMatchingPartialLeadingSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let blocks = [
            BlockInputBlock(id: firstID, text: "First\nSecond"),
            BlockInputBlock(id: secondID, text: "Third")
        ]
        let selectedRange = NSRange(location: 6, length: 6)

        let shiftResult = try selectionByShiftArrow(
            blocks: blocks,
            sourceIndex: 0,
            selectedRange: selectedRange,
            direction: .downward
        )
        let mouseResult = try selectionByMouseDrag(
            blocks: blocks,
            sourceIndex: 0,
            targetIndex: 1,
            selectedRange: selectedRange
        )

        XCTAssertEqual(shiftResult.selection, mouseResult.selection)
        XCTAssertEqual(shiftResult.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: selectedRange),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 5))
        )))
        XCTAssertEqual(shiftResult.chrome, mouseResult.chrome)
    }

    func testShiftUpAndMouseDragCreateMatchingPartialTrailingSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let blocks = [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second\nThird")
        ]
        let selectedRange = NSRange(location: 0, length: 7)

        let shiftResult = try selectionByShiftArrow(
            blocks: blocks,
            sourceIndex: 1,
            selectedRange: selectedRange,
            direction: .upward
        )
        let mouseResult = try selectionByMouseDrag(
            blocks: blocks,
            sourceIndex: 1,
            targetIndex: 0,
            selectedRange: selectedRange
        )

        XCTAssertEqual(shiftResult.selection, mouseResult.selection)
        XCTAssertEqual(shiftResult.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 5)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: selectedRange)
        )))
        XCTAssertEqual(shiftResult.chrome, mouseResult.chrome)
    }

    func testShiftDownFromFullBlockAndMouseDragCreateMatchingPartialSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let blocks = [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]
        let selectedRange = NSRange(location: 0, length: 5)

        let shiftResult = try selectionByShiftArrow(
            blocks: blocks,
            sourceIndex: 0,
            selectedRange: selectedRange,
            direction: .downward
        )
        let mouseResult = try selectionByMouseDrag(
            blocks: blocks,
            sourceIndex: 0,
            targetIndex: 1,
            selectedRange: selectedRange
        )

        XCTAssertEqual(shiftResult.selection, mouseResult.selection)
        XCTAssertEqual(shiftResult.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: selectedRange),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 3))
        )))
        XCTAssertEqual(shiftResult.chrome, mouseResult.chrome)
    }

    func testShiftDownFromCaretAndMouseAnchorCreateMatchingPartialSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let blocks = [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]

        let shiftResult = try selectionByShiftArrow(
            blocks: blocks,
            sourceIndex: 0,
            selectedRange: NSRange(location: 2, length: 0),
            direction: .downward
        )
        let mouseResult = try selectionByMouseDrag(
            blocks: blocks,
            sourceIndex: 0,
            targetIndex: 1,
            selectedRange: NSRange(location: 2, length: 0)
        )

        XCTAssertEqual(shiftResult.selection, mouseResult.selection)
        XCTAssertEqual(shiftResult.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 1))
        )))
        XCTAssertEqual(shiftResult.chrome, mouseResult.chrome)
    }

    func testContinuingAfterMouseDragMatchesShiftArrowPreferredX() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let blocks = [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ]
        let selectedRange = NSRange(location: 2, length: 0)

        let shiftResult = try selectionByShiftArrow(
            blocks: blocks,
            sourceIndex: 0,
            selectedRange: selectedRange,
            direction: .downward,
            continuingDirection: .downward
        )
        let mouseResult = try selectionByMouseDrag(
            blocks: blocks,
            sourceIndex: 0,
            targetIndex: 1,
            selectedRange: selectedRange,
            continuingDirection: .downward
        )

        XCTAssertEqual(shiftResult.selection, mouseResult.selection)
        XCTAssertEqual(shiftResult.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 1))
        )))
        XCTAssertEqual(shiftResult.chrome, mouseResult.chrome)
    }

    private func selectionByShiftArrow(
        blocks: [BlockInputBlock],
        sourceIndex: Int,
        selectedRange: NSRange,
        direction: BlockInputVerticalMovementDirection,
        continuingDirection: BlockInputVerticalMovementDirection? = nil
    ) throws -> SelectionParityResult {
        let mounted = makeMountedBlockInputView(blocks: blocks)
        let sourceItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: sourceIndex))
        let textView = try XCTUnwrap(sourceItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(selectedRange)
        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftArrowEvent(direction)))
        if let continuingDirection {
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftArrowEvent(continuingDirection)))
        }
        return SelectionParityResult(view: mounted.view, itemCount: blocks.count)
    }

    private func selectionByMouseDrag(
        blocks: [BlockInputBlock],
        sourceIndex: Int,
        targetIndex: Int,
        selectedRange: NSRange,
        continuingDirection: BlockInputVerticalMovementDirection? = nil
    ) throws -> SelectionParityResult {
        let mounted = makeMountedBlockInputView(blocks: blocks)
        let sourceItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: sourceIndex))
        let textView = try XCTUnwrap(sourceItem.testingTextView)
        let targetItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: targetIndex))
        let targetTextView = try XCTUnwrap(targetItem.testingTextView)
        let targetLocation = try windowLocation(
            forUTF16Offset: matchingKeyboardTargetOffset(
                sourceItem: sourceItem,
                targetItem: targetItem,
                sourceIndex: sourceIndex,
                targetIndex: targetIndex,
                selectedRange: selectedRange
            ),
            in: targetTextView
        )

        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(selectedRange)
        sourceItem.beginBlockSelectionDrag()
        XCTAssertTrue(sourceItem.updateBlockSelectionDrag(
            with: try mouseDraggedEvent(location: targetLocation, windowNumber: mounted.window.windowNumber),
            selectedRange: selectedRange
        ))
        sourceItem.finishBlockSelectionDrag()
        if let continuingDirection {
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftArrowEvent(continuingDirection)))
        }
        return SelectionParityResult(view: mounted.view, itemCount: blocks.count)
    }

    private func matchingKeyboardTargetOffset(
        sourceItem: BlockInputBlockItem,
        targetItem: BlockInputBlockItem,
        sourceIndex: Int,
        targetIndex: Int,
        selectedRange: NSRange
    ) throws -> Int {
        let direction: BlockInputVerticalMovementDirection = targetIndex > sourceIndex ? .downward : .upward
        let sourceOffset = direction == .downward ? NSMaxRange(selectedRange) : selectedRange.location
        let preferredX = try XCTUnwrap(sourceItem.textContainerX(forUTF16Offset: sourceOffset))
        return targetItem.utf16Offset(
            closestToTextContainerX: preferredX,
            linePosition: direction == .downward ? .first : .last
        )
    }

    private func shiftArrowEvent(_ direction: BlockInputVerticalMovementDirection) throws -> NSEvent {
        switch direction {
        case .upward:
            return try shiftUpEvent()
        case .downward:
            return try shiftDownEvent()
        }
    }
}

private struct SelectionParityResult: Equatable {
    var selection: BlockInputSelection?
    var chrome: [SelectionChromeSnapshot]

    @MainActor
    init(view: BlockInputView, itemCount: Int) {
        selection = view.selection
        chrome = (0..<itemCount).map { index in
            let backgroundView = view.visibleBlockItemForTesting(at: index)?.testingSelectionBackgroundView
            return SelectionChromeSnapshot(
                isHidden: backgroundView?.isHidden ?? true,
                frame: backgroundView?.frame.integral ?? .zero
            )
        }
    }
}

private struct SelectionChromeSnapshot: Equatable {
    var isHidden: Bool
    var frame: NSRect
}
