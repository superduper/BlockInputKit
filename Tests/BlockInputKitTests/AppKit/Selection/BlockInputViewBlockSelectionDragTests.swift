import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewBlockSelectionDragTests: XCTestCase {
    func testDraggingFromTextViewAcrossBlocksSelectsBlockRange() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let thirdItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))

        try drag(from: firstItem, to: thirdItem.view, in: mounted.window)

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID, thirdID]))
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(mounted.view.visibleBlockItemForTesting(at: 1)?.testingSelectionBackgroundView.isHidden, false)
        XCTAssertFalse(thirdItem.testingSelectionBackgroundView.isHidden)
    }

    func testDraggingFromTextViewAcrossBlocksPreservesPartialLeadingSelectionChrome() throws {
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
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let thirdItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let thirdTextView = try XCTUnwrap(thirdItem.testingTextView)
        let targetLocation = try windowLocation(forUTF16Offset: 4, in: thirdTextView)

        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 3))
        firstItem.beginBlockSelectionDrag()
        XCTAssertTrue(firstItem.updateBlockSelectionDrag(
            with: try mouseDraggedEvent(location: targetLocation, windowNumber: mounted.window.windowNumber),
            selectedRange: NSRange(location: 2, length: 3)
        ))
        firstItem.finishBlockSelectionDrag()

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 4))
        )))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)
        XCTAssertFalse(secondItem.testingSelectionBackgroundView.isHidden)
        try assertPartialSelectionChromeMatchesRenderedLine(in: firstItem, utf16Offset: 2)
        XCTAssertGreaterThan(
            secondItem.testingSelectionBackgroundView.frame.height,
            firstItem.testingSelectionBackgroundView.frame.height
        )
    }

    func testDraggingFromTextViewAcrossBlocksSynthesizesPartialSelectionFromAnchorOffset() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let secondTextView = try XCTUnwrap(secondItem.testingTextView)
        let targetLocation = try windowLocation(forUTF16Offset: 1, in: secondTextView)

        firstItem.beginBlockSelectionDrag()
        XCTAssertTrue(firstItem.updateBlockSelectionDrag(
            with: try mouseDraggedEvent(location: targetLocation, windowNumber: mounted.window.windowNumber),
            selectedRange: NSRange(location: 2, length: 0)
        ))
        firstItem.finishBlockSelectionDrag()

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 1))
        )))
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)
    }

    func testDraggingFromTextViewAcrossBlocksSelectsTargetTextToMouseOffset() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let secondTextView = try XCTUnwrap(secondItem.testingTextView)
        let targetLocation = try windowLocation(forUTF16Offset: 4, in: secondTextView)

        firstItem.beginBlockSelectionDrag()
        XCTAssertTrue(firstItem.updateBlockSelectionDrag(
            with: try mouseDraggedEvent(location: targetLocation, windowNumber: mounted.window.windowNumber),
            selectedRange: NSRange(location: 2, length: 0)
        ))
        firstItem.finishBlockSelectionDrag()

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 4))
        )))
        XCTAssertEqual(firstItem.testingTextView?.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testMouseDragKeepsNativeSelectionCollapsedBeforeBlockSelectionPromotion() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstTextView = try XCTUnwrap(firstItem.testingTextView)
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let secondTextView = try XCTUnwrap(secondItem.testingTextView)
        let startLocation = try windowLocation(forUTF16Offset: 2, in: firstTextView)
        let sameBlockLocation = try windowLocation(forUTF16Offset: 4, in: firstTextView)
        let targetLocation = try windowLocation(forUTF16Offset: 3, in: secondTextView)

        firstTextView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        firstTextView.mouseDragged(with: try mouseDraggedEvent(location: sameBlockLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(firstTextView.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(firstItem.temporarySelectionHighlightRange, NSRange(location: 2, length: 2))
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)

        firstTextView.mouseDragged(with: try mouseDraggedEvent(location: targetLocation, windowNumber: mounted.window.windowNumber))
        firstTextView.mouseUp(with: try mouseUpEvent(location: targetLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 3))
        )))
        XCTAssertEqual(firstTextView.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)
        XCTAssertFalse(secondItem.testingSelectionBackgroundView.isHidden)
    }

    func testMouseDragWithinTextViewRestoresTextSelectionOnMouseUp() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstTextView = try XCTUnwrap(firstItem.testingTextView)
        let startLocation = try windowLocation(forUTF16Offset: 1, in: firstTextView)
        let sameBlockLocation = try windowLocation(forUTF16Offset: 4, in: firstTextView)

        firstTextView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        firstTextView.mouseDragged(with: try mouseDraggedEvent(location: sameBlockLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(firstTextView.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(firstItem.temporarySelectionHighlightRange, NSRange(location: 1, length: 3))
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(firstItem.testingSelectionBackgroundView.frame.minX, try viewX(forUTF16Offset: 1, in: firstItem), accuracy: 1)
        XCTAssertEqual(firstItem.testingSelectionBackgroundView.frame.maxX, try viewX(forUTF16Offset: 4, in: firstItem), accuracy: 1)

        firstTextView.mouseUp(with: try mouseUpEvent(location: sameBlockLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(firstTextView.selectedRange(), NSRange(location: 1, length: 3))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: firstID, range: NSRange(location: 1, length: 3))))
        XCTAssertEqual(firstItem.temporarySelectionHighlightRange, NSRange(location: 1, length: 3))
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)
    }

    func testMouseDragWithinTextViewPersistsSelectionWhenMonitorReceivesMouseUp() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstTextView = try XCTUnwrap(firstItem.testingTextView)
        let startLocation = try windowLocation(forUTF16Offset: 1, in: firstTextView)
        let sameBlockLocation = try windowLocation(forUTF16Offset: 4, in: firstTextView)

        firstTextView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        firstTextView.mouseDragged(with: try mouseDraggedEvent(location: sameBlockLocation, windowNumber: mounted.window.windowNumber))
        firstTextView.updateTrackedSelectionForCurrentMouseEvent(try mouseUpEvent(
            location: sameBlockLocation,
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertTrue(firstTextView.completeTrackedBlockSelectionMouseUp())

        XCTAssertEqual(firstTextView.selectedRange(), NSRange(location: 1, length: 3))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: firstID, range: NSRange(location: 1, length: 3))))
        XCTAssertEqual(firstItem.temporarySelectionHighlightRange, NSRange(location: 1, length: 3))
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)
        XCTAssertFalse(firstTextView.completeTrackedBlockSelectionMouseUp())
    }

    func testOnlyPlainSingleClicksUseCustomDragTracking() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstTextView = try XCTUnwrap(firstItem.testingTextView)
        let location = try windowLocation(forUTF16Offset: 2, in: firstTextView)

        XCTAssertTrue(firstTextView.shouldTrackBlockSelectionDrag(for: try mouseDownEvent(
            location: location,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertFalse(firstTextView.shouldTrackBlockSelectionDrag(for: try mouseDownEvent(
            location: location,
            windowNumber: mounted.window.windowNumber,
            modifierFlags: .shift
        )))
        XCTAssertFalse(firstTextView.shouldTrackBlockSelectionDrag(for: try mouseDownEvent(
            location: location,
            windowNumber: mounted.window.windowNumber,
            clickCount: 2
        )))
    }

    func testDraggingFromTextViewUpAcrossBlocksSelectsTargetTextFromMouseOffset() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstTextView = try XCTUnwrap(firstItem.testingTextView)
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let targetLocation = try windowLocation(forUTF16Offset: 2, in: firstTextView)

        secondItem.beginBlockSelectionDrag()
        XCTAssertTrue(secondItem.updateBlockSelectionDrag(
            with: try mouseDraggedEvent(location: targetLocation, windowNumber: mounted.window.windowNumber),
            selectedRange: NSRange(location: 4, length: 0)
        ))
        secondItem.finishBlockSelectionDrag()

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 4))
        )))
    }

    func testDraggingFromTextViewUpAcrossBlocksSelectsBlockRangeInDocumentOrder() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let thirdItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))

        try drag(from: thirdItem, to: firstItem.view, in: mounted.window)

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID, thirdID]))
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(mounted.view.visibleBlockItemForTesting(at: 1)?.testingSelectionBackgroundView.isHidden, false)
        XCTAssertFalse(thirdItem.testingSelectionBackgroundView.isHidden)
    }

    func testDraggingFromTextViewUpAcrossBlocksPreservesPartialTrailingSelectionChrome() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let thirdItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let textView = try XCTUnwrap(thirdItem.testingTextView)
        let firstTextView = try XCTUnwrap(firstItem.testingTextView)
        let targetLocation = try windowLocation(forUTF16Offset: 0, in: firstTextView)

        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 2))
        thirdItem.beginBlockSelectionDrag()
        XCTAssertTrue(thirdItem.updateBlockSelectionDrag(
            with: try mouseDraggedEvent(location: targetLocation, windowNumber: mounted.window.windowNumber),
            selectedRange: NSRange(location: 0, length: 2)
        ))
        thirdItem.finishBlockSelectionDrag()

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 5)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 2))
        )))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertFalse(thirdItem.testingSelectionBackgroundView.isHidden)
        XCTAssertFalse(secondItem.testingSelectionBackgroundView.isHidden)
        try assertPartialSelectionChromeMatchesRenderedLine(in: thirdItem, utf16Offset: 0)
        XCTAssertGreaterThan(
            secondItem.testingSelectionBackgroundView.frame.height,
            thirdItem.testingSelectionBackgroundView.frame.height
        )
    }

    func testDraggingFromCollectionRowChromeSelectsBlockRange() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let thirdItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let firstLocation = firstItem.view.convert(NSPoint(x: 6, y: firstItem.view.bounds.midY), to: nil)
        let thirdLocation = thirdItem.view.convert(NSPoint(x: 6, y: thirdItem.view.bounds.midY), to: nil)

        mounted.view.collectionView.mouseDown(with: try mouseDownEvent(location: firstLocation, windowNumber: mounted.window.windowNumber))
        mounted.view.collectionView.mouseDragged(with: try mouseDraggedEvent(location: thirdLocation, windowNumber: mounted.window.windowNumber))
        mounted.view.collectionView.mouseUp(with: try mouseUpEvent(location: thirdLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID, thirdID]))
        XCTAssertFalse(firstItem.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(mounted.view.visibleBlockItemForTesting(at: 1)?.testingSelectionBackgroundView.isHidden, false)
        XCTAssertFalse(thirdItem.testingSelectionBackgroundView.isHidden)
    }

    func testDraggingBackToOriginAllowsTextSelectionToResume() throws {
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
        let thirdItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let startLocation = firstItem.view.convert(NSPoint(x: firstItem.view.bounds.midX, y: firstItem.view.bounds.midY), to: nil)
        let thirdLocation = thirdItem.view.convert(NSPoint(x: thirdItem.view.bounds.midX, y: thirdItem.view.bounds.midY), to: nil)

        mounted.window.makeFirstResponder(textView)
        firstItem.beginBlockSelectionDrag()
        XCTAssertTrue(firstItem.updateBlockSelectionDrag(with: try mouseDraggedEvent(
            location: thirdLocation,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        XCTAssertFalse(firstItem.updateBlockSelectionDrag(with: try mouseDraggedEvent(
            location: startLocation,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertTrue(mounted.window.firstResponder === textView)
        firstItem.finishBlockSelectionDrag()
    }

    func testDraggingHorizontalRuleBackToOriginRestoresSingleRuleSelection() throws {
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: ruleID, kind: .horizontalRule),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let ruleItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let thirdItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let ruleLocation = ruleItem.view.convert(NSPoint(x: ruleItem.view.bounds.midX, y: ruleItem.view.bounds.midY), to: nil)
        let thirdLocation = thirdItem.view.convert(NSPoint(x: thirdItem.view.bounds.midX, y: thirdItem.view.bounds.midY), to: nil)

        ruleItem.beginBlockSelectionDrag()
        XCTAssertTrue(ruleItem.updateBlockSelectionDrag(with: try mouseDraggedEvent(
            location: thirdLocation,
            windowNumber: mounted.window.windowNumber
        )))
        XCTAssertEqual(mounted.view.selection, .blocks([ruleID, secondID, thirdID]))
        XCTAssertFalse(ruleItem.updateBlockSelectionDrag(with: try mouseDraggedEvent(
            location: ruleLocation,
            windowNumber: mounted.window.windowNumber
        )))

        XCTAssertEqual(mounted.view.selection, .blocks([ruleID]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        ruleItem.finishBlockSelectionDrag()
    }

    func testDraggingBlockSelectionCanBeCopiedAsMarkdown() throws {
        let first = BlockInputBlock(id: "first", kind: .heading(level: 2), text: "First")
        let second = BlockInputBlock(id: "second", kind: .bulletedListItem, text: "Second")
        let mounted = makeMountedBlockInputView(blocks: [first, second])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        try drag(from: firstItem, to: secondItem.view, in: mounted.window)
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))

        XCTAssertEqual(pasteboard.string(forType: .string), BlockInputDocument(blocks: [first, second]).markdown)
    }

    func testDraggingBlockSelectionCanBeDeleted() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))

        try drag(from: firstItem, to: secondItem.view, in: mounted.window)
        mounted.view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [thirdID])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: thirdID, utf16Offset: 0)))
    }

    private func drag(from item: BlockInputBlockItem, to targetView: NSView, in window: NSWindow) throws {
        let targetLocation = targetView.convert(NSPoint(x: targetView.bounds.midX, y: targetView.bounds.midY), to: nil)
        item.beginBlockSelectionDrag()
        _ = item.updateBlockSelectionDrag(with: try mouseDraggedEvent(location: targetLocation, windowNumber: window.windowNumber))
        item.finishBlockSelectionDrag()
    }

}
