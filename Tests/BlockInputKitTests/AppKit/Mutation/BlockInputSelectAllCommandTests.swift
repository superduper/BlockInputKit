import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputSelectAllCommandTests: XCTestCase {
    func testCommandASelectsCurrentBlockThenAllBlocksFromTextFocus() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 5)
        )))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 5))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
    }

    func testCommandASelectsAllBlocksImmediatelyFromEmptyTextFocus() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: ""),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
    }

    func testCommandAWithDocumentBehaviorSelectsAllBlocksFromTextFocus() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            selectAllBehavior: .document
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
    }

    func testCommandAWithDocumentBehaviorCollapsesSingleEmptyPlaceholderDocumentFromTextFocus() throws {
        let blockID = BlockInputBlockID(rawValue: "empty")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "")
            ]),
            placeholder: "Ask anything",
            selectAllBehavior: .document
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))

        assertSingleEmptyPlaceholderSelectAllCollapsed(mounted: mounted, item: item, textView: textView, blockID: blockID)
        XCTAssertTrue(mounted.window.firstResponder === textView)
    }

    func testCommandAWithDocumentBehaviorSelectsWhitespaceOnlyText() throws {
        let blockID = BlockInputBlockID(rawValue: "spaces")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "   ")
            ]),
            placeholder: "Ask anything",
            selectAllBehavior: .document
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "   ")
        XCTAssertEqual(mounted.view.selection, .blocks([blockID]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        XCTAssertTrue(mounted.view.placeholderLabel.isHidden)
    }

    func testCommandAWithDocumentBehaviorCollapsesSingleEmptyPlaceholderDocumentFromEditorFocus() throws {
        let blockID = BlockInputBlockID(rawValue: "empty")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "")
            ]),
            placeholder: "Ask anything",
            selectAllBehavior: .document
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandAEvent()))

        assertSingleEmptyPlaceholderSelectAllCollapsed(mounted: mounted, item: item, textView: textView, blockID: blockID)
    }

    func testCommandAWithDocumentBehaviorSelectsSingleEmptyCodeBlock() throws {
        let blockID = BlockInputBlockID(rawValue: "code")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .code(language: nil))
            ]),
            placeholder: "Ask anything",
            selectAllBehavior: .document
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([blockID]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        XCTAssertTrue(mounted.view.placeholderLabel.isHidden)
    }

    func testSelectAllActionWithDocumentBehaviorCollapsesSingleEmptyPlaceholderDocument() throws {
        let blockID = BlockInputBlockID(rawValue: "empty")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "")
            ]),
            placeholder: "Ask anything",
            selectAllBehavior: .document
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        textView.selectAll(nil)

        assertSingleEmptyPlaceholderSelectAllCollapsed(mounted: mounted, item: item, textView: textView, blockID: blockID)
    }

    func testEditorSelectAllActionWithDocumentBehaviorCollapsesSingleEmptyPlaceholderDocument() throws {
        let blockID = BlockInputBlockID(rawValue: "empty")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "")
            ]),
            placeholder: "Ask anything",
            selectAllBehavior: .document
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        mounted.view.selectAll(nil)

        assertSingleEmptyPlaceholderSelectAllCollapsed(mounted: mounted, item: item, textView: textView, blockID: blockID)
    }

    func testSelectAllActionSelectsCurrentBlockThenAllBlocksFromTextFocus() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        textView.selectAll(nil)

        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 5)
        )))

        textView.selectAll(nil)

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testCommandASelectsAllBlocksFromBlockSelectionFocus() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([secondID]), notify: false)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: secondID,
            range: NSRange(location: 0, length: 6)
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testCommandAWithDocumentBehaviorSelectsAllBlocksFromBlockSelectionFocus() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            selectAllBehavior: .document
        ))
        mounted.view.applySelection(.blocks([secondID]), notify: false)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testSelectAllActionSelectsAllBlocksFromBlockSelectionFocus() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([secondID]), notify: false)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        mounted.view.selectAll(nil)

        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: secondID,
            range: NSRange(location: 0, length: 6)
        )))

        mounted.view.selectAll(nil)

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testCommandASelectsAllBlocksFromSelectedHorizontalRule() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: ruleID, kind: .horizontalRule)
        ])
        mounted.view.applySelection(.blocks([ruleID]), notify: false)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, ruleID]))
    }

    func testCommandAAllBlocksSelectionIsVisibleAndDeleteClearsDocument() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: ruleID, kind: .horizontalRule),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstTextView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(firstTextView)

        XCTAssertTrue(firstTextView.performKeyEquivalent(with: try commandAEvent()))
        XCTAssertTrue(firstTextView.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID, ruleID, secondID]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        XCTAssertFalse(try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)).testingSelectionBackgroundView.isHidden)
        XCTAssertFalse(try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1)).testingSelectionBackgroundView.isHidden)
        XCTAssertFalse(try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2)).testingSelectionBackgroundView.isHidden)

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        XCTAssertEqual(mounted.view.document.blocks, [BlockInputBlock(id: firstID, text: "")])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
    }
}

@MainActor
private func assertSingleEmptyPlaceholderSelectAllCollapsed(
    mounted: (view: BlockInputView, window: NSWindow),
    item: BlockInputBlockItem,
    textView: BlockInputTextView,
    blockID: BlockInputBlockID,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(
        mounted.view.selection,
        .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)),
        file: file,
        line: line
    )
    XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0), file: file, line: line)
    XCTAssertTrue(item.testingSelectionBackgroundView.isHidden, file: file, line: line)
    XCTAssertFalse(mounted.view.placeholderLabel.isHidden, file: file, line: line)
    XCTAssertEqual(mounted.view.placeholderLabel.stringValue, "Ask anything", file: file, line: line)
}
