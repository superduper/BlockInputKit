import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputMixedSelectionTests: XCTestCase {
    func testMixedSelectionValidityRequiresDocumentOrderedPartialEdges() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])

        XCTAssertFalse(mounted.view.containsValidSelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 1)),
            trailingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 1))
        ))))
    }

    func testMixedSelectionValidityRequiresWholeBlocksBetweenPartialEdges() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])

        XCTAssertFalse(mounted.view.containsValidSelection(.mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            leadingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 1)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 1))
        ))))
    }

    func testMixedSelectionValidityRejectsSkippedWholeBlockBetweenPartialEdges() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])

        XCTAssertFalse(mounted.view.containsValidSelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 1))
        ))))
    }

    func testMixedSelectionValidityAcceptsContiguousWholeBlockBetweenPartialEdges() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])

        XCTAssertTrue(mounted.view.containsValidSelection(.mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 1))
        ))))
    }

    func testMixedSelectionValidityRejectsEmptyPartialRanges() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First")
        ])

        XCTAssertFalse(mounted.view.containsValidSelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 0))
        ))))
    }

    func testShiftDownFromMiddleOfSingleLineBlockKeepsNextBlockPartialAtCaretX() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 1))
        )))
        XCTAssertEqual(item.temporarySelectionHighlightRange, NSRange(location: 2, length: 3))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertFalse(item.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(
            item.testingSelectionBackgroundView.frame.height,
            try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1)).testingSelectionBackgroundView.frame.height
        )
        XCTAssertFalse(try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1)).testingSelectionBackgroundView.isHidden)
    }

    func testPartialSelectionStartingAtTextStartAlignsWithWholeBlockSelectionLeadingEdge() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, kind: .checklistItem(isChecked: false), text: "Checklist data"),
            BlockInputBlock(id: secondID, text: "Try mention query")
        ])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [firstID],
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 4))
        )), notify: true)

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let checklistBackground = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)).testingSelectionBackgroundView
        XCTAssertEqual(item.testingSelectionBackgroundView.frame.minX, checklistBackground.frame.minX)
    }

    func testPartialOnlyMixedSelectionRestoresHighlightsAfterReload() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 1))
        )), notify: true)
        mounted.window.makeFirstResponder(nil)

        mounted.view.reloadDataKeepingFocus()

        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        XCTAssertEqual(firstItem.temporarySelectionHighlightRange, NSRange(location: 2, length: 3))
        XCTAssertEqual(secondItem.temporarySelectionHighlightRange, NSRange(location: 0, length: 1))
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)
        XCTAssertFalse(secondItem.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testContinuingShiftDownPromotesPreviousPartialEndpointToWholeBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 1))
        )))
    }

    func testShiftUpFromMiddleOfSingleLineBlockKeepsPreviousBlockPartialAtCaretX() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 4, length: 1)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 3))
        )))
        XCTAssertEqual(item.temporarySelectionHighlightRange, NSRange(location: 0, length: 3))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertFalse(item.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(
            item.testingSelectionBackgroundView.frame.height,
            try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)).testingSelectionBackgroundView.frame.height
        )
        XCTAssertFalse(try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)).testingSelectionBackgroundView.isHidden)
    }
}
