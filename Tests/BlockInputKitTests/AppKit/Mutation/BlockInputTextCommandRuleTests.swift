import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTextCommandRuleTests: XCTestCase {
    func testDeleteInHorizontalRuleTextViewRevealsDashMarker() throws {
        let blockID = BlockInputBlockID(rawValue: "rule")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .horizontalRule)
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[0].text, "---")
        XCTAssertEqual(textView.string, "---")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 3)))
    }

    func testSpaceAfterRevealedHorizontalRuleMarkerReformatsRuleAndFocusesBlockBelow() throws {
        let blockID = BlockInputBlockID(rawValue: "rule")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .horizontalRule)
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        textView.string = "--- "
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(view.document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(view.document.blocks[1].kind, .paragraph)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingFirstEmptyBlockThreeDashesCreatesFrontMatter() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: ""),
            BlockInputBlock(id: secondID, text: "Second")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "---"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks.map(\.kind), [.frontMatter, .paragraph])
        XCTAssertEqual(view.document.blocks[0].id, firstID)
        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(view.document.blocks[1].id, secondID)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
    }

    func testTypingNonFirstHorizontalRuleShortcutWithTrailingSpaceCreatesRule() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[1],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "--- "
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks.map(\.kind), [.paragraph, .horizontalRule, .paragraph])
        XCTAssertEqual(view.document.blocks[1].id, secondID)
        XCTAssertEqual(view.document.blocks[2].text, "")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[2].id, utf16Offset: 0)))
    }

    func testTypingNonFirstHorizontalRuleShortcutWithoutTrailingSpaceCreatesRule() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[1],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "---"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks.map(\.kind), [.paragraph, .horizontalRule, .paragraph])
        XCTAssertEqual(view.document.blocks[1].id, secondID)
        XCTAssertEqual(view.document.blocks[2].text, "")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[2].id, utf16Offset: 0)))
    }

    func testTypingHorizontalRuleShortcutInEmptyHeadingPreservesHeadingBelowRule() throws {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "---"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks.map(\.kind), [.horizontalRule, .heading(level: 2)])
        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(view.document.blocks[1].text, "")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingHorizontalRuleShortcutMovesExistingTextBelowRule() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Existing"),
            BlockInputBlock(id: secondID, text: "Second")
        ])))
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
        XCTAssertEqual(view.document.blocks[0].id, firstID)
        XCTAssertEqual(view.document.blocks[1].text, "Existing")
        XCTAssertEqual(view.document.blocks[2].id, secondID)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingNoSpaceHorizontalRuleShortcutMovesExistingTextBelowRule() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Existing"),
            BlockInputBlock(id: secondID, text: "Second")
        ])))
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
        XCTAssertEqual(view.document.blocks[0].id, firstID)
        XCTAssertEqual(view.document.blocks[1].text, "Existing")
        XCTAssertEqual(view.document.blocks[2].id, secondID)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingHorizontalRuleShortcutInHeadingPreservesHeadingBelowRule() throws {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
        ])))
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

        XCTAssertEqual(view.document.blocks.map(\.kind), [.horizontalRule, .heading(level: 2)])
        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(view.document.blocks[1].text, "Heading")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingNoSpaceHorizontalRuleShortcutInHeadingPreservesHeadingBelowRule() throws {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
        ])))
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

        XCTAssertEqual(view.document.blocks.map(\.kind), [.horizontalRule, .heading(level: 2)])
        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(view.document.blocks[1].text, "Heading")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testTypingHorizontalRuleShortcutTrimsLeadingSpacesFromMovedText() throws {
        let blockID = BlockInputBlockID(rawValue: "rule")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Existing")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "---    Existing"
        textView.setSelectedRange(NSRange(location: 15, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks.map(\.kind), [.horizontalRule, .paragraph])
        XCTAssertEqual(view.document.blocks[1].text, "Existing")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 8)))
    }

    func testDeleteInSelectedHorizontalRuleTextViewDeletesRule() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: ruleID, kind: .horizontalRule)
        ])))
        view.applySelection(.blocks([ruleID]), notify: false)
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[1],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(view.document.blocks.map(\.id), [firstID])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))
    }

    func testHorizontalRuleIgnoresProgrammaticTextChangesThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "rule")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .horizontalRule)
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "Hidden"
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks[0].kind, .horizontalRule)
        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(textView.string, "")
        XCTAssertFalse(textView.isEditable)
    }
}
