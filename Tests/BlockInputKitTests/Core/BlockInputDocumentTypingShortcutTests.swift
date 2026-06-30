import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputDocumentTypingShortcutTests: XCTestCase {
    func testTypingShortcutTurnsParagraphMarkerIntoQuote() {
        let blockID = BlockInputBlockID(rawValue: "quote")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "> Quoted",
            proposedUTF16Offset: 8
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .quote)
        XCTAssertEqual(document.blocks[0].text, "Quoted")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)))
    }

    func testTypingShortcutIgnoresRawMarkdownBlocks() {
        let blockID = BlockInputBlockID(rawValue: "raw")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .rawMarkdown, text: "")
        ])

        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "- [ ] Todo",
            proposedUTF16Offset: 10
        )

        XCTAssertNil(shortcut)
    }

    func testTypingShortcutTurnsParagraphMarkerIntoChecklistItem() {
        let blockID = BlockInputBlockID(rawValue: "check")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "- [ ] Todo",
            proposedUTF16Offset: 10
        )

        _ = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .checklistItem(isChecked: false))
        XCTAssertEqual(document.blocks[0].text, "Todo")
    }

    func testTypingShortcutTurnsExactChecklistMarkersIntoEmptyChecklistItems() {
        let uncheckedID = BlockInputBlockID(rawValue: "unchecked")
        let checkedID = BlockInputBlockID(rawValue: "checked")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: uncheckedID, text: ""),
            BlockInputBlock(id: checkedID, text: "")
        ])

        let uncheckedShortcut = document.typingShortcut(
            for: uncheckedID,
            proposedText: "- [ ]",
            proposedUTF16Offset: 5
        )
        let checkedShortcut = document.typingShortcut(
            for: checkedID,
            proposedText: "- [x]",
            proposedUTF16Offset: 5
        )
        let uncheckedSelection = uncheckedShortcut.flatMap {
            document.applyTypingShortcut(blockID: uncheckedID, shortcut: $0)
        }
        let checkedSelection = checkedShortcut.flatMap {
            document.applyTypingShortcut(blockID: checkedID, shortcut: $0)
        }

        XCTAssertEqual(document.blocks[0].kind, .checklistItem(isChecked: false))
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(uncheckedSelection, .cursor(BlockInputCursor(blockID: uncheckedID, utf16Offset: 0)))
        XCTAssertEqual(document.blocks[1].kind, .checklistItem(isChecked: true))
        XCTAssertEqual(document.blocks[1].text, "")
        XCTAssertEqual(checkedSelection, .cursor(BlockInputCursor(blockID: checkedID, utf16Offset: 0)))
    }

    func testTypingShortcutUpgradesEmptyBulletMarkerIntoChecklistItem() {
        let blockID = BlockInputBlockID(rawValue: "check")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "", indentationLevel: 2)
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "[ ]",
            proposedUTF16Offset: 3
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .checklistItem(isChecked: false))
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.blocks[0].indentationLevel, 2)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testTypingShortcutUpgradesBulletMarkerIntoCheckedChecklistItemWithText() {
        let blockID = BlockInputBlockID(rawValue: "check")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "[x] Done",
            proposedUTF16Offset: 8
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .checklistItem(isChecked: true))
        XCTAssertEqual(document.blocks[0].text, "Done")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4)))
    }

    func testTypingShortcutDoesNotApplyHeadingShortcutInsideBulletItem() {
        let blockID = BlockInputBlockID(rawValue: "bullet")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "")
        ])

        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "# Heading",
            proposedUTF16Offset: 9
        )

        XCTAssertNil(shortcut)
    }

    func testTypingShortcutTurnsParagraphMarkerIntoBulletedListItem() {
        let blockID = BlockInputBlockID(rawValue: "bullet")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "- Bullet",
            proposedUTF16Offset: 8
        )

        _ = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .bulletedListItem)
        XCTAssertEqual(document.blocks[0].text, "Bullet")
    }

    func testTypingShortcutAcceptsAlternateBulletMarkers() {
        let asteriskID = BlockInputBlockID(rawValue: "asterisk")
        let plusID = BlockInputBlockID(rawValue: "plus")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: asteriskID, text: ""),
            BlockInputBlock(id: plusID, text: "")
        ])

        let asteriskShortcut = document.typingShortcut(
            for: asteriskID,
            proposedText: "* Asterisk",
            proposedUTF16Offset: 10
        )
        let plusShortcut = document.typingShortcut(
            for: plusID,
            proposedText: "+ Plus",
            proposedUTF16Offset: 6
        )
        _ = asteriskShortcut.flatMap { document.applyTypingShortcut(blockID: asteriskID, shortcut: $0) }
        _ = plusShortcut.flatMap { document.applyTypingShortcut(blockID: plusID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .bulletedListItem)
        XCTAssertEqual(document.blocks[0].text, "Asterisk")
        XCTAssertEqual(document.blocks[1].kind, .bulletedListItem)
        XCTAssertEqual(document.blocks[1].text, "Plus")
    }

    func testTypingShortcutTurnsParagraphMarkerIntoNumberedListItem() {
        let blockID = BlockInputBlockID(rawValue: "number")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "42. Number",
            proposedUTF16Offset: 10
        )

        _ = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .numberedListItem(start: 42))
        XCTAssertEqual(document.blocks[0].text, "Number")
    }

    func testTypingShortcutTurnsParagraphMarkerIntoHeading() {
        let blockID = BlockInputBlockID(rawValue: "heading")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "### Heading",
            proposedUTF16Offset: 11
        )

        _ = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .heading(level: 3))
        XCTAssertEqual(document.blocks[0].text, "Heading")
    }

    func testTypingShortcutChangesExistingHeadingLevel() {
        let blockID = BlockInputBlockID(rawValue: "heading")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "#### Heading",
            proposedUTF16Offset: 12
        )

        _ = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .heading(level: 4))
        XCTAssertEqual(document.blocks[0].text, "Heading")
    }

    func testTypingShortcutLeavesCodeFenceForReturnConversion() {
        let blockID = BlockInputBlockID(rawValue: "code")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])

        XCTAssertNil(document.typingShortcut(for: blockID, proposedText: "```", proposedUTF16Offset: 3))
        XCTAssertNil(document.typingShortcut(for: blockID, proposedText: "```swift", proposedUTF16Offset: 8))
    }

    func testTypingShortcutTurnsFirstEmptyBlockThreeDashesIntoFrontMatter() {
        let blockID = BlockInputBlockID(rawValue: "rule")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "---",
            proposedUTF16Offset: 3
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .frontMatter)
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testTypingShortcutTurnsFirstEmptyBlockThreeDashesAndSpaceIntoFrontMatter() {
        let blockID = BlockInputBlockID(rawValue: "rule")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "--- ",
            proposedUTF16Offset: 4
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .frontMatter)
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testTypingShortcutMovesTextAfterHorizontalRuleMarkerIntoParagraphBelow() {
        let blockID = BlockInputBlockID(rawValue: "rule")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Existing")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "--- Existing",
            proposedUTF16Offset: 4
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(document.blocks[1].text, "Existing")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingShortcutMovesHeadingTextAfterHorizontalRuleMarkerIntoHeadingBelow() {
        let blockID = BlockInputBlockID(rawValue: "heading")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "--- Heading",
            proposedUTF16Offset: 4
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.blocks[1].kind, .heading(level: 2))
        XCTAssertEqual(document.blocks[1].text, "Heading")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingShortcutTrimsLeadingSpacesFromTextMovedBelowHorizontalRule() {
        let blockID = BlockInputBlockID(rawValue: "rule")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Existing")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "---    Existing",
            proposedUTF16Offset: 15
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(document.blocks[1].text, "Existing")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 8)))
    }

    func testTypingShortcutTurnsNonFirstThreeDashesIntoHorizontalRule() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: secondID,
            proposedText: "---",
            proposedUTF16Offset: 3
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: secondID, shortcut: $0) }

        XCTAssertEqual(document.blocks.map(\.kind), [.paragraph, .horizontalRule, .paragraph])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[2].id, utf16Offset: 0)))
    }

    func testUnwrapListItemRevealsListMarkerForReformatting() {
        let blockID = BlockInputBlockID(rawValue: "bullet")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Bullet", indentationLevel: 2)
        ])

        let selection = document.unwrapBlockToParagraph(blockID: blockID)

        XCTAssertEqual(document.blocks[0].kind, .paragraph)
        XCTAssertEqual(document.blocks[0].text, "-Bullet")
        XCTAssertEqual(document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 1)))
    }

    func testUnwrapQuoteRevealsQuoteMarkerForReformatting() {
        let blockID = BlockInputBlockID(rawValue: "quote")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .quote, text: "Quoted")
        ])

        let selection = document.unwrapBlockToParagraph(blockID: blockID)

        XCTAssertEqual(document.blocks[0].kind, .paragraph)
        XCTAssertEqual(document.blocks[0].text, ">Quoted")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 1)))
    }

    func testUnwrapHeadingRevealsHashMarkerForReformatting() {
        let blockID = BlockInputBlockID(rawValue: "heading")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
        ])

        let selection = document.unwrapBlockToParagraph(blockID: blockID)

        XCTAssertEqual(document.blocks[0].kind, .paragraph)
        XCTAssertEqual(document.blocks[0].text, "##Heading")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)))
    }

    func testUnwrapHorizontalRuleRevealsDashMarkerForReformatting() {
        let blockID = BlockInputBlockID(rawValue: "rule")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .horizontalRule)
        ])

        let selection = document.unwrapBlockToParagraph(blockID: blockID)

        XCTAssertEqual(document.blocks[0].kind, .paragraph)
        XCTAssertEqual(document.blocks[0].text, "---")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 3)))
    }
}
