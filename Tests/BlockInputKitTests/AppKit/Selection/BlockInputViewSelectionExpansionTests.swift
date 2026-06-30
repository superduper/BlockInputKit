import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewSelectionExpansionTests: XCTestCase {
    func testShiftDownFromCollapsedCaretSelectsLine() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First\nSecond\nThird")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 6))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )))
        XCTAssertFalse(item.testingSelectionBackgroundView.isHidden)
        XCTAssertTrue(textView.isSelectable)
    }

    func testShiftDownExpandsTextSelectionByLine() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First\nSecond\nThird")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )))
    }

    func testRepeatedShiftDownFromCaretPromotesToPartialNextBlockAfterSelectingAllLines() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First\nSecond"),
            BlockInputBlock(id: secondID, text: "Third")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.keyDown(with: try shiftDownEvent())
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 6)
        )))
        textView.keyDown(with: try shiftDownEvent())
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 12)
        )))
        textView.keyDown(with: try shiftDownEvent())
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 12)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 5))
        )))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testRepeatedShiftUpFromCaretPromotesToPartialPreviousBlockAfterSelectingAllLines() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second\nThird")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 12, length: 0))

        textView.keyDown(with: try shiftUpEvent())
        textView.keyDown(with: try shiftUpEvent())
        textView.keyDown(with: try shiftUpEvent())

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 5)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 12))
        )))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testShiftUpAtTopOfTextSelectionKeepsSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First\nSecond\nThird")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 5))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 5)
        )))
    }

    func testShiftDownAtEndOfTextSelectionKeepsSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First\nSecond\nThird")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 13, length: 5))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 13, length: 5))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 13, length: 5)
        )))
    }

    func testShiftDownPromotesTrailingTextSelectionToPartialNextBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First\nSecond"),
            BlockInputBlock(id: secondID, text: "Third")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 6, length: 6))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 6, length: 6)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 5))
        )))
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), true)
    }

    func testShiftDownKeyDownPromotesTrailingTextSelectionToPartialNextBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First\nSecond"),
            BlockInputBlock(id: secondID, text: "Third")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 6, length: 6))

        textView.keyDown(with: try shiftDownEvent())

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 6, length: 6)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 5))
        )))
    }

    func testShiftUpPromotesLeadingTextSelectionToPartialPreviousBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second\nThird")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 7))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 5)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 7))
        )))
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), true)
    }

    func testShiftDownFromCollapsedCaretExtendsTextSelectionByLine() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First\nSecond\nThird")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertGreaterThan(textView.selectedRange().length, 0)
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: textView.selectedRange()
        )))
    }

    func testMoveDownModifySelectionSelectorFromCollapsedCaretSelectsLine() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First\nSecond\nThird")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.moveDownAndModifySelection(_:)))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 6))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )))
    }

    func testShiftDownExpandsExistingBlockSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID, thirdID]))
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 2), true)
    }

    func testShiftDownKeyDownExpandsExistingBlockSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try shiftDownEvent())

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID, thirdID]))
    }

    func testShiftDownExpandsExistingBlockSelectionWhenTextViewStillReceivesKey() throws {
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
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        mounted.window.makeFirstResponder(textView)

        textView.keyDown(with: try shiftDownEvent())

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID, thirdID]))
    }

    func testMoveDownModifySelectionSelectorExpandsExistingBlockSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)

        mounted.view.doCommand(by: #selector(NSResponder.moveDownAndModifySelection(_:)))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID, thirdID]))
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 2), true)
    }

    func testShiftUpExpandsExistingBlockSelectionInDocumentOrder() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        mounted.view.applySelection(.blocks([secondID, thirdID]), notify: false)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID, thirdID]))
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 2), true)
    }

    func testShiftUpAtTopOfBlockSelectionKeepsSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([firstID]), notify: false)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID]))
    }

    func testShiftDownAtEndOfBlockSelectionKeepsSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([secondID]), notify: false)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([secondID]))
    }

    func testStaleTextSelectionChangeDoesNotClearActiveBlockSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        mounted.view.blockItem(firstItem, didChangeSelectionIn: firstID, selectedRange: nil)

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), true)
    }

    private func itemSelectionBackgroundVisible(in view: BlockInputView, at index: Int) -> Bool {
        view.visibleBlockItemForTesting(at: index)?.testingSelectionBackgroundView.isHidden == false
    }
}
