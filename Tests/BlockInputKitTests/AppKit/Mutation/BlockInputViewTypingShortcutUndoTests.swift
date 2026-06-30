import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewTypingShortcutUndoTests: XCTestCase {
    func testTypingShortcutUsesStructuralUndoStack() throws {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "")
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        _ = item.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "# Heading")
        textView.string = "# Heading"
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let undo = view.undoStructuralEdit()
        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Format Block")
        XCTAssertEqual(redo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks[0].kind, .heading(level: 1))
        XCTAssertEqual(view.document.blocks[0].text, "Heading")
    }

    func testTypingShortcutUndoKeepsCapturedTextSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Selected")
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        _ = item.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: 8),
            replacementString: "# Heading"
        )
        textView.string = "# Heading"
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[0].text, "Selected")
        XCTAssertEqual(undo?.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 8)
        )))
    }

    func testBulletToChecklistShortcutUndoRestoresEmptyBulletSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "bullet")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "")
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        _ = item.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "[ ]")
        textView.string = "[ ]"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let undo = view.undoStructuralEdit()
        XCTAssertEqual(view.document.blocks[0].kind, .bulletedListItem)
        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))

        _ = view.redoStructuralEdit()

        XCTAssertEqual(view.document.blocks[0].kind, .checklistItem(isChecked: false))
    }

    func testFrontMatterTypingShortcutUndoRestoresOriginalBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: ""),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        _ = item.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "---")
        textView.string = "---"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0].id, firstID)
        XCTAssertEqual(view.document.blocks[0].kind, .frontMatter)
        XCTAssertEqual(view.document.blocks[1].id, secondID)
        XCTAssertEqual(redo?.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
    }

    func testHorizontalRuleTypingShortcutUndoRestoresTextMovedBelowRule() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "Existing"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        _ = item.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "--- ")
        textView.string = "--- Existing"
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks.map(\.kind), [.horizontalRule, .paragraph, .paragraph])
        XCTAssertEqual(view.document.blocks[1].text, "Existing")

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[0].text, "Existing")
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks.map(\.kind), [.horizontalRule, .paragraph, .paragraph])
        XCTAssertEqual(view.document.blocks[1].text, "Existing")
        XCTAssertEqual(view.document.blocks[2].id, secondID)
    }

    func testNoSpaceHorizontalRuleTypingShortcutUndoRestoresTextMovedBelowRule() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "Existing"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        _ = item.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "---")
        textView.string = "---Existing"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks.map(\.kind), [.horizontalRule, .paragraph, .paragraph])
        XCTAssertEqual(view.document.blocks[1].text, "Existing")

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[0].text, "Existing")
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks.map(\.kind), [.horizontalRule, .paragraph, .paragraph])
        XCTAssertEqual(view.document.blocks[1].text, "Existing")
        XCTAssertEqual(view.document.blocks[2].id, secondID)
    }

    func testHeadingHorizontalRuleTypingShortcutUndoRestoresHeading() throws {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        _ = item.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "--- ")
        textView.string = "--- Heading"
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
        ])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks.map(\.kind), [.horizontalRule, .heading(level: 2)])
        XCTAssertEqual(view.document.blocks[1].text, "Heading")
    }

    func testNoSpaceHeadingHorizontalRuleTypingShortcutUndoRestoresHeading() throws {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        _ = item.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "---")
        textView.string = "---Heading"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
        ])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Format Block")
        XCTAssertEqual(view.document.blocks.map(\.kind), [.horizontalRule, .heading(level: 2)])
        XCTAssertEqual(view.document.blocks[1].text, "Heading")
    }

    func testMountedNoSpaceHeadingHorizontalRuleUndoRefreshesVisibleBlocks() throws {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let quoteID = BlockInputBlockID(rawValue: "quote")
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: headingID, kind: .heading(level: 1), text: "BlockInputKit demo"),
                BlockInputBlock(id: paragraphID, text: "Each visible block owns its own AppKit text input."),
                BlockInputBlock(id: quoteID, kind: .quote, text: "Focus, selection, return, delete, and Cmd+A are coordinated.")
            ]),
            undoController: undoController
        )
        let headingItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(headingItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        _ = headingItem.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "---")
        textView.string = "---BlockInputKit demo"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        headingItem.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.horizontalRule, .heading(level: 1), .paragraph, .quote])
        XCTAssertEqual(mounted.view.document.blocks[1].text, "BlockInputKit demo")
        let insertedHeadingID = mounted.view.document.blocks[1].id

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandZEvent()))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [headingID, paragraphID, quoteID])
        let restoredHeadingItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let restoredParagraphItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        XCTAssertEqual(restoredHeadingItem.representedBlockID, headingID)
        XCTAssertEqual(restoredHeadingItem.testingTextView?.string, "BlockInputKit demo")
        XCTAssertTrue(try XCTUnwrap(restoredHeadingItem.testingHorizontalRuleSelectionView).isHidden)
        XCTAssertEqual(restoredParagraphItem.representedBlockID, paragraphID)
        XCTAssertEqual(restoredParagraphItem.testingTextView?.string, "Each visible block owns its own AppKit text input.")
        XCTAssertTrue(try XCTUnwrap(restoredParagraphItem.testingHorizontalRuleSelectionView).isHidden)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftZEvent()))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.horizontalRule, .heading(level: 1), .paragraph, .quote])
        let redoneRuleItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let redoneHeadingItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let redoneParagraphItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        XCTAssertEqual(redoneRuleItem.representedBlockID, headingID)
        XCTAssertFalse(try XCTUnwrap(redoneRuleItem.testingHorizontalRuleSelectionView).isHidden)
        XCTAssertEqual(redoneHeadingItem.representedBlockID, insertedHeadingID)
        XCTAssertEqual(redoneHeadingItem.testingTextView?.string, "BlockInputKit demo")
        XCTAssertEqual(redoneParagraphItem.representedBlockID, paragraphID)
        XCTAssertEqual(redoneParagraphItem.testingTextView?.string, "Each visible block owns its own AppKit text input.")
    }
}
