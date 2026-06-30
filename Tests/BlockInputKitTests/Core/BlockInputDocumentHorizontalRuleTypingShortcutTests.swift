import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputHorizontalRuleShortcutTests: XCTestCase {
    func testTypingShortcutMovesTextAfterNoSpaceHorizontalRuleMarkerIntoParagraphBelow() {
        let blockID = BlockInputBlockID(rawValue: "rule")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Existing")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "---Existing",
            proposedUTF16Offset: 3
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.blocks[1].kind, .paragraph)
        XCTAssertEqual(document.blocks[1].text, "Existing")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingShortcutMovesHeadingTextAfterNoSpaceHorizontalRuleMarkerIntoHeadingBelow() {
        let blockID = BlockInputBlockID(rawValue: "heading")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "---Heading",
            proposedUTF16Offset: 3
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.blocks[1].kind, .heading(level: 2))
        XCTAssertEqual(document.blocks[1].text, "Heading")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingShortcutTurnsEmptyHeadingThreeDashesIntoHorizontalRuleAndPreservesHeadingBelow() {
        let blockID = BlockInputBlockID(rawValue: "heading")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "---",
            proposedUTF16Offset: 3
        )

        let selection = shortcut.flatMap { document.applyTypingShortcut(blockID: blockID, shortcut: $0) }

        XCTAssertEqual(document.blocks.map(\.kind), [.horizontalRule, .heading(level: 2)])
        XCTAssertEqual(document.blocks[0].id, blockID)
        XCTAssertEqual(document.blocks[1].text, "")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingShortcutIgnoresThreeDashesAwayFromBlockStart() {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "abc")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "abc---",
            proposedUTF16Offset: 6
        )

        XCTAssertNil(shortcut)
    }

    func testTypingShortcutIgnoresHorizontalRuleMarkerBeforeLineBreak() {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "---\nExisting",
            proposedUTF16Offset: 3
        )

        XCTAssertNil(shortcut)
    }

    func testTypingShortcutIgnoresHorizontalRuleMarkerBeforeTab() {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "")
        ])
        let shortcut = document.typingShortcut(
            for: blockID,
            proposedText: "---\tExisting",
            proposedUTF16Offset: 3
        )

        XCTAssertNil(shortcut)
    }
}
