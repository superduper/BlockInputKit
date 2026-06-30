import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputDocumentTests: XCTestCase {
    func testDefaultDocumentStartsWithOneEmptyParagraph() {
        let document = BlockInputDocument()

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].kind, .paragraph)
        XCTAssertTrue(document.isEffectivelyEmpty)
    }

    func testDeleteEmptyBlockFocusesEndOfPreviousBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Before"),
            BlockInputBlock(id: secondID, text: "")
        ])

        let selection = document.deleteEmptyBlockForBackspaceOrDelete(blockID: secondID)

        XCTAssertEqual(document.blocks.map(\.id), [firstID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
    }

    func testDeleteEmptyFirstBlockFocusesNextRemainingBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: ""),
            BlockInputBlock(id: secondID, text: "After")
        ])

        let selection = document.deleteEmptyBlockForBackspaceOrDelete(blockID: firstID)

        XCTAssertEqual(document.blocks.map(\.id), [secondID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 0)))
    }

    func testDeleteOnlyBlockKeepsOneEmptyParagraphFocused() {
        let blockID = BlockInputBlockID(rawValue: "only")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .quote, text: "")
        ])

        let selection = document.deleteEmptyBlockForBackspaceOrDelete(blockID: blockID)

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].id, blockID)
        XCTAssertEqual(document.blocks[0].kind, .paragraph)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testDeleteSelectedBlocksFocusesPreviousRemainingBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let fourthID = BlockInputBlockID(rawValue: "fourth")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third"),
            BlockInputBlock(id: fourthID, text: "Fourth")
        ])

        let selection = document.deleteBlocks(blockIDs: [secondID, thirdID])

        XCTAssertEqual(document.blocks.map(\.id), [firstID, fourthID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))
    }

    func testDeleteLeadingSelectedBlocksFocusesNextRemainingBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])

        let selection = document.deleteBlocks(blockIDs: [firstID, secondID])

        XCTAssertEqual(document.blocks.map(\.id), [thirdID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: thirdID, utf16Offset: 0)))
    }

    func testDeleteAllSelectedBlocksLeavesOneEmptyParagraphFocused() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])

        let selection = document.deleteBlocks(blockIDs: [firstID, secondID])

        XCTAssertEqual(document.blocks, [BlockInputBlock(id: firstID, text: "")])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
    }

    func testHorizontalRuleIsNotEffectivelyEmptyContent() {
        let blockID = BlockInputBlockID(rawValue: "rule")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .horizontalRule)
        ])

        let selection = document.deleteEmptyBlockForBackspaceOrDelete(blockID: blockID)

        XCTAssertFalse(document.isEffectivelyEmpty)
        XCTAssertNil(selection)
        XCTAssertEqual(document.blocks[0].kind, .horizontalRule)
    }

    func testEmptyCodeBlocksAreNotEffectivelyEmptyContent() {
        let blocks = [
            BlockInputBlock(id: "empty", kind: .code(language: nil), text: ""),
            BlockInputBlock(id: "blank-lines", kind: .code(language: "swift"), text: "\n")
        ]

        for block in blocks {
            let document = BlockInputDocument(blocks: [block])

            XCTAssertFalse(document.isEffectivelyEmpty, "Expected empty code block to count as content")
            XCTAssertTrue(block.isEmpty, "Expected code block emptiness to keep editing semantics")
        }
    }

    func testHorizontalRuleBlocksNormalizeStoredText() throws {
        var block = BlockInputBlock(id: "rule", kind: .horizontalRule, text: "Hidden")

        XCTAssertEqual(block.text, "")
        XCTAssertEqual(block.utf16Length, 0)

        block.text = "Ignored"
        XCTAssertEqual(block.text, "")

        block.kind = .paragraph
        block.text = "Visible"
        block.kind = .horizontalRule
        XCTAssertEqual(block.text, "")

        let encoded = try JSONEncoder().encode(BlockInputBlock(id: "decoded", kind: .horizontalRule))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payload["text"] = "Hidden"
        let staleEncoded = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(BlockInputBlock.self, from: staleEncoded)
        XCTAssertEqual(decoded.text, "")
    }

    func testImageBlocksNormalizeStoredTextAndAreNotEmpty() throws {
        var block = BlockInputBlock(
            id: "image",
            kind: .image(BlockInputImage(source: "https://example.com/image.png", altText: "Example")),
            text: "Hidden"
        )

        XCTAssertEqual(block.text, "")
        XCTAssertFalse(block.isEmpty)

        block.text = "Ignored"
        XCTAssertEqual(block.text, "")

        let encoded = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(BlockInputBlock.self, from: encoded)
        XCTAssertEqual(decoded.kind, block.kind)
        XCTAssertEqual(decoded.text, "")
    }

    func testImageDimensionsNormalizeToPositiveValues() {
        var image = BlockInputImage(source: "image.png", width: -1, height: 0)

        XCTAssertNil(image.width)
        XCTAssertNil(image.height)

        image.width = 120
        image.height = -20
        XCTAssertEqual(image.width, 120)
        XCTAssertNil(image.height)
    }

    func testNonListBlocksNormalizeIndentation() throws {
        var block = BlockInputBlock(id: "quote", kind: .quote, text: "Quoted", indentationLevel: 2)

        XCTAssertEqual(block.indentationLevel, 0)

        block.kind = .bulletedListItem
        block.indentationLevel = 2
        XCTAssertEqual(block.indentationLevel, 2)

        block.kind = .heading(level: 2)
        XCTAssertEqual(block.indentationLevel, 0)

        let encoded = try JSONEncoder().encode(BlockInputBlock(
            id: "decoded",
            kind: .bulletedListItem,
            text: "Nested",
            indentationLevel: 3
        ))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payload["kind"] = ["quote": [:]]
        let staleEncoded = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(BlockInputBlock.self, from: staleEncoded)
        XCTAssertEqual(decoded.indentationLevel, 0)
    }

    func testChangingBlockKindToHorizontalRuleClearsText() {
        let blockID = BlockInputBlockID(rawValue: "rule")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Will be cleared", indentationLevel: 2)
        ])

        let selection = document.changeBlockKind(blockID: blockID, to: .horizontalRule)

        XCTAssertEqual(document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testReplacingTextUsesUTF16Offsets() {
        let blockID = BlockInputBlockID(rawValue: "emoji")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "a😀c")
        ])

        let selection = document.replaceText(
            in: blockID,
            range: NSRange(location: 1, length: 2),
            replacement: "b"
        )

        XCTAssertEqual(document.blocks[0].text, "abc")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)))
    }

    func testReplacingTextClampsSelectionToActualEditLocation() {
        let blockID = BlockInputBlockID(rawValue: "short")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "abc")
        ])

        let selection = document.replaceText(
            in: blockID,
            range: NSRange(location: 10, length: 5),
            replacement: "d"
        )

        XCTAssertEqual(document.blocks[0].text, "abcd")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4)))
    }

    func testReplacingListTextPreservesPerLineIndentationLevels() {
        let blockID = BlockInputBlockID(rawValue: "list")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(
                id: blockID,
                kind: .bulletedListItem,
                text: "One\nTwo",
                lineIndentationLevels: [0, 1]
            )
        ])

        let selection = document.replaceText(
            in: blockID,
            range: NSRange(location: 7, length: 0),
            replacement: "\nThree"
        )

        XCTAssertEqual(document.blocks[0].text, "One\nTwo\nThree")
        XCTAssertEqual(document.blocks[0].lineIndentationLevels, [0, 1, 1])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 13)))
    }

    func testReplacingAllListTextKeepsEmptyLineAtSelectionStartIndentation() {
        let blockID = BlockInputBlockID(rawValue: "list")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(
                id: blockID,
                kind: .bulletedListItem,
                text: "One\nTwo",
                lineIndentationLevels: [1, 3]
            )
        ])

        let selection = document.replaceText(
            in: blockID,
            range: NSRange(location: 0, length: 7),
            replacement: ""
        )

        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.blocks[0].lineIndentationLevels, [1])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testCRLFListTextDoesNotCreatePhantomLineIndentation() {
        let block = BlockInputBlock(
            kind: .bulletedListItem,
            text: "One\r\nTwo",
            lineIndentationLevels: [0, 1]
        )

        XCTAssertEqual(block.lineIndentationLevels, [0, 1])
    }

    func testReplacingTextInHorizontalRuleIsNoOp() {
        let blockID = BlockInputBlockID(rawValue: "rule")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .horizontalRule)
        ])

        let selection = document.replaceText(
            in: blockID,
            range: NSRange(location: 0, length: 0),
            replacement: "Hidden"
        )

        XCTAssertEqual(document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testMoveBlockUsesFinalTargetIndex() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])

        let selection = document.moveBlock(blockID: firstID, to: 2)

        XCTAssertEqual(document.blocks.map(\.id), [secondID, thirdID, firstID])
        XCTAssertEqual(selection, .blocks([firstID]))
    }

    func testMoveNumberedSubitemRenumbersAgainstNewListContext() {
        let firstParentID = BlockInputBlockID(rawValue: "first-parent")
        let firstChildID = BlockInputBlockID(rawValue: "first-child")
        let secondParentID = BlockInputBlockID(rawValue: "second-parent")
        let secondChildID = BlockInputBlockID(rawValue: "second-child")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstParentID, kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: firstChildID, kind: .numberedListItem(start: 1), text: "Child", indentationLevel: 1),
            BlockInputBlock(id: secondParentID, kind: .numberedListItem(start: 2), text: "Second"),
            BlockInputBlock(id: secondChildID, kind: .numberedListItem(start: 1), text: "Moved", indentationLevel: 1)
        ])

        let selection = document.moveBlock(blockID: secondChildID, to: 2)

        XCTAssertEqual(document.blocks.map(\.id), [firstParentID, firstChildID, secondChildID, secondParentID])
        XCTAssertEqual(document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 2)
        ])
        XCTAssertEqual(selection, .blocks([secondChildID]))
    }

    func testMoveTopLevelNumberedItemRenumbersAffectedSiblings() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three")
        ])

        let selection = document.moveBlock(blockID: secondID, to: 2)

        XCTAssertEqual(document.blocks.map(\.id), [firstID, thirdID, secondID])
        XCTAssertEqual(document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 3)
        ])
        XCTAssertEqual(selection, .blocks([secondID]))
    }

    func testMoveParagraphDoesNotRenumberUnrelatedNumberedList() {
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let firstListID = BlockInputBlockID(rawValue: "first-list")
        let childID = BlockInputBlockID(rawValue: "child")
        let secondListID = BlockInputBlockID(rawValue: "second-list")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: paragraphID, text: "Paragraph"),
            BlockInputBlock(id: firstListID, kind: .numberedListItem(start: 4), text: "Four"),
            BlockInputBlock(id: childID, kind: .numberedListItem(start: 7), text: "Seven", indentationLevel: 1),
            BlockInputBlock(id: secondListID, kind: .numberedListItem(start: 5), text: "Five")
        ])

        let selection = document.moveBlock(blockID: paragraphID, to: 3)

        XCTAssertEqual(document.blocks.map(\.id), [firstListID, childID, secondListID, paragraphID])
        XCTAssertEqual(document.blocks.map(\.kind), [
            .numberedListItem(start: 4),
            .numberedListItem(start: 7),
            .numberedListItem(start: 5),
            .paragraph
        ])
        XCTAssertEqual(selection, .blocks([paragraphID]))
    }

    func testMoveParagraphBeforeMergedNumberedRunsRenumbersSourceList() {
        let firstListID = BlockInputBlockID(rawValue: "first-list")
        let separatorID = BlockInputBlockID(rawValue: "separator")
        let secondListID = BlockInputBlockID(rawValue: "second-list")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstListID, kind: .numberedListItem(start: 4), text: "Four"),
            BlockInputBlock(id: separatorID, text: "Separator"),
            BlockInputBlock(id: secondListID, kind: .numberedListItem(start: 9), text: "Nine")
        ])

        let selection = document.moveBlock(blockID: separatorID, to: 0)

        XCTAssertEqual(document.blocks.map(\.id), [separatorID, firstListID, secondListID])
        XCTAssertEqual(document.blocks.map(\.kind), [
            .paragraph,
            .numberedListItem(start: 4),
            .numberedListItem(start: 5)
        ])
        XCTAssertEqual(selection, .blocks([separatorID]))
    }

    func testMoveBlockToSameIndexIsNoOp() {
        let blockID = BlockInputBlockID(rawValue: "only")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Only")
        ])

        let selection = document.moveBlock(blockID: blockID, to: 0)

        XCTAssertNil(selection)
        XCTAssertEqual(document.blocks.map(\.id), [blockID])
    }

    func testChangeBlockKindToExistingKindIsNoOp() {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .paragraph, text: "Same")
        ])

        let selection = document.changeBlockKind(blockID: blockID, to: .paragraph)

        XCTAssertNil(selection)
        XCTAssertEqual(document.blocks[0].kind, .paragraph)
    }

    func testToggleChecklistItemFlipsCheckedState() {
        let blockID = BlockInputBlockID(rawValue: "check")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: false), text: "Done")
        ])

        let selection = document.toggleChecklistItem(blockID: blockID)

        XCTAssertEqual(document.blocks[0].kind, .checklistItem(isChecked: true))
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4)))
    }

    func testToggleChecklistItemIgnoresNonChecklistBlocks() {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .paragraph, text: "Same")
        ])

        let selection = document.toggleChecklistItem(blockID: blockID)

        XCTAssertNil(selection)
        XCTAssertEqual(document.blocks[0].kind, .paragraph)
    }

}
