import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputSelectionResponderTests: XCTestCase {
    func testShiftDownExpandsModelTextSelectionWhenEditorIsResponder() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First\nSecond"),
            BlockInputBlock(id: secondID, text: "Third")
        ])
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: firstID, range: NSRange(location: 6, length: 6))),
            notify: false
        )
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try shiftDownEvent())

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 6, length: 6)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 5))
        )))
    }

    func testViewLevelShiftDownUsesFocusedTextViewCaretXForPartialTarget() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let blocks = [
            BlockInputBlock(id: firstID, text: "First line"),
            BlockInputBlock(id: secondID, text: "Second line")
        ]
        let expected = makeMountedBlockInputView(blocks: blocks)
        let expectedItem = try XCTUnwrap(expected.view.visibleBlockItemForTesting(at: 0))
        let expectedTextView = try XCTUnwrap(expectedItem.testingTextView)
        expected.window.makeFirstResponder(expectedTextView)
        expectedTextView.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertTrue(expectedTextView.performKeyEquivalent(with: try shiftDownEvent()))

        let mounted = makeMountedBlockInputView(blocks: blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: firstID, utf16Offset: 2)), notify: false)

        XCTAssertTrue(mounted.view.handleSelectionExpansionKeyEvent(try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, expected.view.selection)
        guard case let .mixed(selection) = mounted.view.selection else {
            return XCTFail("Expected mixed selection")
        }
        XCTAssertNotNil(selection.trailingTextRange)
    }

    func testShiftDownExpandsModelCursorWhenEditorIsResponder() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First\nSecond")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try shiftDownEvent())

        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )))
    }

    func testBeginningOfDocumentSelectionActionPromotesFullySelectedBlockToMixedSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Previous"),
            BlockInputBlock(id: secondID, text: "First\nSecond")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        textView.setSelectedRange(NSRange(location: 12, length: 0))

        XCTAssertTrue(textView.requestSelectionExpansionFromOwningBlock(.upward))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: secondID,
            range: NSRange(location: 6, length: 6)
        )))

        XCTAssertTrue(textView.requestSelectionExpansionFromOwningBlock(.upward))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: secondID,
            range: NSRange(location: 0, length: 12)
        )))

        XCTAssertTrue(textView.requestSelectionExpansionFromOwningBlock(.upward))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 8)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 12))
        )))
    }

    func testEndOfDocumentSelectionActionPromotesFullySelectedBlockToMixedSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First\nSecond"),
            BlockInputBlock(id: secondID, text: "Next")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.requestSelectionExpansionFromOwningBlock(.downward))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 6)
        )))

        XCTAssertTrue(textView.requestSelectionExpansionFromOwningBlock(.downward))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 12)
        )))

        XCTAssertTrue(textView.requestSelectionExpansionFromOwningBlock(.downward))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 12)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 4))
        )))
    }

    func testBeginningOfDocumentActionMovesCaretToDocumentStart() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Previous"),
            BlockInputBlock(id: secondID, text: "First\nSecond")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 12))),
            notify: false
        )

        textView.moveToBeginningOfDocument(nil as Any?)

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
    }

    func testEndOfDocumentActionMovesCaretToDocumentEnd() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First\nSecond"),
            BlockInputBlock(id: secondID, text: "Next")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 12))),
            notify: false
        )

        textView.moveToEndOfDocument(nil as Any?)

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 4)))
    }

    func testRepeatedNativeFullTextSelectionPromotesUpwardToMixedSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Previous"),
            BlockInputBlock(id: secondID, text: "First\nSecond")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: secondID, range: NSRange(location: 6, length: 6))),
            notify: false
        )
        textView.setSelectedRange(NSRange(location: 0, length: 12))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: secondID,
            range: NSRange(location: 0, length: 12)
        )))

        mounted.view.blockItem(secondItem, didChangeSelectionIn: secondID, selectedRange: nil)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 8)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 12))
        )))
    }

    func testRepeatedNativeFullTextSelectionPromotesDownwardToMixedSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First\nSecond"),
            BlockInputBlock(id: secondID, text: "Next")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 6))),
            notify: false
        )
        textView.setSelectedRange(NSRange(location: 0, length: 12))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 12)
        )))

        mounted.view.blockItem(firstItem, didChangeSelectionIn: firstID, selectedRange: nil)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 12)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 4))
        )))
    }

    func testRepeatedNativePartialLeadingSelectionPromotesUpwardToMixedSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Previous"),
            BlockInputBlock(id: secondID, text: "First\nSecond")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: secondID, range: NSRange(location: 6, length: 6))),
            notify: false
        )
        textView.setSelectedRange(NSRange(location: 0, length: 6))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: secondID,
            range: NSRange(location: 0, length: 6)
        )))

        mounted.view.blockItem(secondItem, didChangeSelectionIn: secondID, selectedRange: nil)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 8)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 6))
        )))
    }

    func testRepeatedNativePartialTrailingSelectionPromotesDownwardToMixedSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First\nSecond"),
            BlockInputBlock(id: secondID, text: "Next")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 6))),
            notify: false
        )
        textView.setSelectedRange(NSRange(location: 6, length: 6))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 6, length: 6)
        )))

        mounted.view.blockItem(firstItem, didChangeSelectionIn: firstID, selectedRange: nil)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 6, length: 6)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 4))
        )))
    }

    func testShiftUpFromTextViewExpandsActiveBlockSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.view.applySelection(.blocks([secondID, thirdID]), notify: false)

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftNumericPadUpEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID, thirdID]))
    }

    func testShiftDownFromTextViewExpandsActiveBlockSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftNumericPadDownEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID, thirdID]))
    }

    func testNativeShiftUpSelectionAtLeadingEdgePromotesToBlocks() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])

        XCTAssertTrue(mounted.view.promoteNativeSelectionExpansionIfNeeded(
            from: secondID,
            selectedRange: NSRange(location: 0, length: 6),
            direction: .upward
        ))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testNativeShiftDownSelectionAtTrailingEdgePromotesToBlocks() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])

        XCTAssertTrue(mounted.view.promoteNativeSelectionExpansionIfNeeded(
            from: firstID,
            selectedRange: NSRange(location: 0, length: 5),
            direction: .downward
        ))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testNativeShiftUpSelectionAwayFromLeadingEdgeDoesNotPromote() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second\nThird")
        ])

        XCTAssertFalse(mounted.view.promoteNativeSelectionExpansionIfNeeded(
            from: secondID,
            selectedRange: NSRange(location: 7, length: 5),
            direction: .upward
        ))

        XCTAssertNil(mounted.view.selection)
    }
}
