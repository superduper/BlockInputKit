import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewHorizontalRuleTests: XCTestCase {
    func testClickingHorizontalRuleSelectsItWithAccentColor() throws {
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "First"),
                BlockInputBlock(id: ruleID, kind: .horizontalRule)
            ]),
            dropIndicatorColor: .systemPink
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let ruleView = try XCTUnwrap(item.testingHorizontalRuleSelectionView)
        mounted.view.showDropIndicator(atInsertionIndex: 2)

        ruleView.mouseDown(with: try mouseDownEvent(windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .blocks([ruleID]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        XCTAssertEqual(ruleView.testingLineView?.layer?.backgroundColor, NSColor.systemPink.cgColor)
        XCTAssertEqual(ruleView.testingLineHeight, 4)
        XCTAssertTrue(mounted.view.dropIndicatorView.isHidden)
    }

    func testClickingHorizontalRuleRowSelectsOnlyThatRule() throws {
        let firstRuleID = BlockInputBlockID(rawValue: "first-rule")
        let secondRuleID = BlockInputBlockID(rawValue: "second-rule")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstRuleID, kind: .horizontalRule),
            BlockInputBlock(id: "middle", text: "Middle"),
            BlockInputBlock(id: secondRuleID, kind: .horizontalRule)
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))

        secondItem.mouseDown(with: try mouseDownEvent(windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .blocks([secondRuleID]))
        XCTAssertEqual(firstItem.testingHorizontalRuleSelectionView?.testingLineHeight, 2)
        XCTAssertEqual(secondItem.testingHorizontalRuleSelectionView?.testingLineHeight, 4)
    }

    func testClickingHorizontalRuleVisuallySelectsOnlyClickedItemEvenWithDuplicateIDs() throws {
        let sharedRuleID = BlockInputBlockID(rawValue: "shared-rule")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: sharedRuleID, kind: .horizontalRule),
            BlockInputBlock(id: "middle", text: "Middle"),
            BlockInputBlock(id: sharedRuleID, kind: .horizontalRule)
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))

        secondItem.mouseDown(with: try mouseDownEvent(windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(firstItem.testingHorizontalRuleSelectionView?.testingLineHeight, 2)
        XCTAssertEqual(secondItem.testingHorizontalRuleSelectionView?.testingLineHeight, 4)
    }

    func testDeleteKeyRemovesSelectedHorizontalRuleBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        var publishedDocument: BlockInputDocument?
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: ruleID, kind: .horizontalRule),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            onDocumentChange: { publishedDocument = $0 }
        ))
        view.applySelection(.blocks([ruleID]), notify: false)

        view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))
        XCTAssertEqual(publishedDocument, view.document)
    }

    func testDeleteForwardKeyRemovesSelectedHorizontalRuleBlock() throws {
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: ruleID, kind: .horizontalRule),
            BlockInputBlock(id: secondID, text: "Second")
        ])))
        view.applySelection(.blocks([ruleID]), notify: false)

        view.keyDown(with: try keyDownEvent(keyCode: 117, characters: "\u{F728}"))

        XCTAssertEqual(view.document.blocks.map(\.id), [secondID])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 0)))
    }

    func testDeleteKeyOnlyAffectsSelectedHorizontalRuleBlock() throws {
        let firstRuleID = BlockInputBlockID(rawValue: "first-rule")
        let selectedRuleID = BlockInputBlockID(rawValue: "selected-rule")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstRuleID, kind: .horizontalRule),
            BlockInputBlock(id: "middle", text: "Middle"),
            BlockInputBlock(id: selectedRuleID, kind: .horizontalRule)
        ])))
        view.applySelection(.blocks([selectedRuleID]), notify: false)

        view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        XCTAssertEqual(view.document.blocks.map(\.id), [firstRuleID, "middle"])
        XCTAssertEqual(view.document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(view.document.blocks[1].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[1].text, "Middle")
    }

    func testDeleteKeyOnlyDeletesClickedRuleWhenRuleIDsAreDuplicated() throws {
        let sharedRuleID = BlockInputBlockID(rawValue: "shared-rule")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: sharedRuleID, kind: .horizontalRule),
            BlockInputBlock(id: "middle", text: "Middle"),
            BlockInputBlock(id: sharedRuleID, kind: .horizontalRule)
        ])
        let selectedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        selectedItem.mouseDown(with: try mouseDownEvent(windowNumber: mounted.window.windowNumber))

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertEqual(mounted.view.document.blocks[0].id, sharedRuleID)
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(mounted.view.document.blocks[1].id, "middle")
    }

    func testDeletingOnlySelectedHorizontalRuleLeavesEmptyParagraph() {
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: ruleID, kind: .horizontalRule)
        ])))
        view.applySelection(.blocks([ruleID]), notify: false)

        let selection = view.deleteSelectedHorizontalRuleForBackspaceOrDelete()

        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(view.document.blocks[0].id, ruleID)
        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: ruleID, utf16Offset: 0)))
    }

    func testTypingHorizontalRuleShortcutAtBottomDoesNotReconfigureEarlierVisibleItem() throws {
        let checklistID = BlockInputBlockID(rawValue: "checklist")
        let lastID = BlockInputBlockID(rawValue: "last")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(kind: .heading(level: 1), text: "BlockInputKit demo"),
            BlockInputBlock(text: "Each visible block owns its own AppKit text input."),
            BlockInputBlock(kind: .quote, text: "Focus and selection are coordinated."),
            BlockInputBlock(kind: .horizontalRule),
            BlockInputBlock(kind: .code(language: "swift"), text: "let editor = BlockInputView()"),
            BlockInputBlock(kind: .bulletedListItem, text: "Hover rows to reveal reorder handles"),
            BlockInputBlock(kind: .numberedListItem(start: 1), text: "Toggle reordering from the toolbar"),
            BlockInputBlock(id: checklistID, kind: .checklistItem(isChecked: false), text: "Checklist"),
            BlockInputBlock(text: "Try mention query: @av"),
            BlockInputBlock(id: lastID, text: "Try slash query: /code")
        ])
        let lastItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 9))
        let textView = try XCTUnwrap(lastItem.testingTextView)
        textView.string = "---"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        lastItem.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(mounted.view.document.blocks[7].id, checklistID)
        XCTAssertEqual(mounted.view.document.blocks[9].id, lastID)
        XCTAssertEqual(mounted.view.document.blocks[9].kind, .horizontalRule)
        XCTAssertEqual(mounted.view.document.blocks[10].kind, .paragraph)

        let checklistItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 7))
        XCTAssertEqual(checklistItem.representedBlockID, checklistID)
        XCTAssertEqual(checklistItem.testingTextView?.string, "Checklist")
        XCTAssertTrue(try XCTUnwrap(checklistItem.testingHorizontalRuleSelectionView).isHidden)

        let ruleItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 9))
        XCTAssertEqual(ruleItem.representedBlockID, lastID)
        XCTAssertFalse(try XCTUnwrap(ruleItem.testingHorizontalRuleSelectionView).isHidden)
    }
}
