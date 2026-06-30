import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewWordMovementTests: XCTestCase {
    func testOptionRightInsideBlockUsesNativeWordMovement() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "Alpha beta")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.moveWordRight(_:)))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0))
    }

    func testOptionLeftInsideBlockUsesNativeWordMovement() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "Alpha beta")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 10, length: 0))

        textView.doCommand(by: #selector(NSResponder.moveWordLeft(_:)))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 0))
    }

    func testOptionRightAtBlockEndMovesToNextBlockFirstWordEnd() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma delta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 10, length: 0))

        textView.keyDown(with: try optionRightEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 5)))
        XCTAssertEqual(secondItem.testingTextView?.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, secondItem.testingTextView)
    }

    func testOptionLeftAtBlockStartMovesToPreviousBlockLastWordStart() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma delta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.keyDown(with: try optionLeftEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
        XCTAssertEqual(firstItem.testingTextView?.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, firstItem.testingTextView)
    }

    func testKeyDownOptionRightAtBlockEndMovesToNextBlockFirstWordEnd() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta gamma")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.keyDown(with: try optionRightEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 4)))
        XCTAssertEqual(secondItem.testingTextView?.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, secondItem.testingTextView)
    }

    func testKeyDownOptionLeftAtBlockStartMovesToPreviousBlockLastWordStart() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.keyDown(with: try optionLeftEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
        XCTAssertEqual(firstItem.testingTextView?.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, firstItem.testingTextView)
    }

    func testOptionRightAtDocumentEndLeavesCaretUnchanged() throws {
        let blockID = BlockInputBlockID(rawValue: "only")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Alpha")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.keyDown(with: try optionRightEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0))
    }

    func testOptionLeftAtDocumentStartLeavesCaretUnchanged() throws {
        let blockID = BlockInputBlockID(rawValue: "only")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Alpha")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.keyDown(with: try optionLeftEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testRepeatedOptionRightMovesThroughEmptyBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let emptyID = BlockInputBlockID(rawValue: "empty")
        let lastID = BlockInputBlockID(rawValue: "last")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: emptyID, text: ""),
            BlockInputBlock(id: lastID, text: "Last word")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let emptyItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let lastItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.keyDown(with: try optionRightEvent())
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: emptyID, utf16Offset: 0)))
        XCTAssertEqual(mounted.window.firstResponder, emptyItem.testingTextView)

        let emptyTextView = try XCTUnwrap(emptyItem.testingTextView)
        emptyTextView.keyDown(with: try optionRightEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: lastID, utf16Offset: 4)))
        XCTAssertEqual(lastItem.testingTextView?.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, lastItem.testingTextView)
    }

    func testRepeatedOptionLeftMovesThroughEmptyBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let emptyID = BlockInputBlockID(rawValue: "empty")
        let lastID = BlockInputBlockID(rawValue: "last")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First word"),
            BlockInputBlock(id: emptyID, text: ""),
            BlockInputBlock(id: lastID, text: "Last")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let emptyItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let lastItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let textView = try XCTUnwrap(lastItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.keyDown(with: try optionLeftEvent())
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: emptyID, utf16Offset: 0)))
        XCTAssertEqual(mounted.window.firstResponder, emptyItem.testingTextView)

        let emptyTextView = try XCTUnwrap(emptyItem.testingTextView)
        emptyTextView.keyDown(with: try optionLeftEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
        XCTAssertEqual(firstItem.testingTextView?.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, firstItem.testingTextView)
    }

    func testOptionRightSelectsHorizontalRuleAndContinuesToNextTextBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let lastID = BlockInputBlockID(rawValue: "last")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: ruleID, kind: .horizontalRule),
            BlockInputBlock(id: lastID, text: "Last word")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let lastItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.keyDown(with: try optionRightEvent())

        XCTAssertEqual(mounted.view.selection, .blocks([ruleID]))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionRightEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: lastID, utf16Offset: 4)))
        XCTAssertEqual(lastItem.testingTextView?.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, lastItem.testingTextView)
    }

    func testOptionLeftSelectsHorizontalRuleAndContinuesToPreviousTextBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let lastID = BlockInputBlockID(rawValue: "last")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First word"),
            BlockInputBlock(id: ruleID, kind: .horizontalRule),
            BlockInputBlock(id: lastID, text: "Last")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let lastItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let textView = try XCTUnwrap(lastItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.keyDown(with: try optionLeftEvent())

        XCTAssertEqual(mounted.view.selection, .blocks([ruleID]))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
        XCTAssertEqual(firstItem.testingTextView?.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, firstItem.testingTextView)
    }

    func testOptionLeftFromWholeBlockSelectionMovesToPreviousBlockLastWordStart() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.view.applySelection(.blocks([secondID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
        XCTAssertEqual(firstItem.testingTextView?.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, firstItem.testingTextView)
    }

    func testOptionRightFromWholeBlockSelectionMovesToNextBlockFirstWordEnd() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta gamma")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        mounted.view.applySelection(.blocks([firstID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionRightEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 4)))
        XCTAssertEqual(secondItem.testingTextView?.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, secondItem.testingTextView)
    }

    func testViewKeyDownOptionRightFromWholeBlockSelectionMovesToNextBlockFirstWordEnd() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta gamma")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        mounted.view.applySelection(.blocks([firstID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try optionRightEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 4)))
        XCTAssertEqual(secondItem.testingTextView?.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, secondItem.testingTextView)
    }

    func testOptionRightFromSingleBlockMixedSelectionUsesTrailingBoundary() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Alpha beta")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: blockID, range: NSRange(location: 0, length: 5))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionRightEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 10)))
        XCTAssertEqual(item.testingTextView?.selectedRange(), NSRange(location: 10, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, item.testingTextView)
    }

    func testOptionLeftFromSingleBlockMixedSelectionUsesLeadingBoundary() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Alpha beta")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: BlockInputTextRange(blockID: blockID, range: NSRange(location: 6, length: 4))
        )), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
        XCTAssertEqual(item.testingTextView?.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, item.testingTextView)
    }

    func testCommandSelectorRoutesWordMovementAcrossBlockBoundary() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma delta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 10, length: 0))

        textView.doCommand(by: #selector(NSResponder.moveWordRight(_:)))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 5)))
        XCTAssertEqual(secondItem.testingTextView?.selectedRange(), NSRange(location: 5, length: 0))
    }

    func testViewCommandSelectorRoutesWordMovementFromWholeBlockSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta gamma")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        mounted.view.applySelection(.blocks([firstID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.doCommand(by: #selector(NSResponder.moveWordRight(_:)))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 4)))
        XCTAssertEqual(secondItem.testingTextView?.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(mounted.window.firstResponder, secondItem.testingTextView)
    }

    func testCommandSelectorRoutesLeftWordMovementAcrossBlockBoundary() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma delta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.moveWordLeft(_:)))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
        XCTAssertEqual(firstItem.testingTextView?.selectedRange(), NSRange(location: 6, length: 0))
    }

    func testCommandSelectorAliasesRouteWordMovementAcrossBlockBoundaries() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma delta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let firstTextView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(firstTextView)
        firstTextView.setSelectedRange(NSRange(location: 10, length: 0))

        firstTextView.doCommand(by: #selector(NSResponder.moveWordForward(_:)))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 5)))
        XCTAssertEqual(secondItem.testingTextView?.selectedRange(), NSRange(location: 5, length: 0))

        let secondTextView = try XCTUnwrap(secondItem.testingTextView)
        secondTextView.setSelectedRange(NSRange(location: 0, length: 0))

        secondTextView.doCommand(by: #selector(NSResponder.moveWordBackward(_:)))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
        XCTAssertEqual(firstItem.testingTextView?.selectedRange(), NSRange(location: 6, length: 0))
    }

    func testOptionRightAllowsNumericPadArrowFlag() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.keyDown(with: try optionRightEvent(modifierFlags: [.option, .numericPad]))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 4)))
        XCTAssertEqual(secondItem.testingTextView?.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testOptionWordMovementWorksAcrossEditableBlockKinds() throws {
        let headingID = BlockInputBlockID(rawValue: "heading")
        let quoteID = BlockInputBlockID(rawValue: "quote")
        let listID = BlockInputBlockID(rawValue: "list")
        let codeID = BlockInputBlockID(rawValue: "code")
        let frontMatterID = BlockInputBlockID(rawValue: "front")
        let rawID = BlockInputBlockID(rawValue: "raw")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: headingID, kind: .heading(level: 2), text: "Heading text"),
            BlockInputBlock(id: quoteID, kind: .quote, text: "Quote text"),
            BlockInputBlock(id: listID, kind: .bulletedListItem, text: "List text"),
            BlockInputBlock(id: codeID, kind: .code(language: "swift"), text: "let value"),
            BlockInputBlock(id: frontMatterID, kind: .frontMatter, text: "title: Test"),
            BlockInputBlock(id: rawID, kind: .rawMarkdown, text: "<div>Raw</div>")
        ])
        let expectedTargets = [
            WordMovementTarget(index: 1, blockID: quoteID, offset: 5),
            WordMovementTarget(index: 2, blockID: listID, offset: 4),
            WordMovementTarget(index: 3, blockID: codeID, offset: 3),
            WordMovementTarget(index: 4, blockID: frontMatterID, offset: 5),
            WordMovementTarget(index: 5, blockID: rawID, offset: 1)
        ]

        for target in expectedTargets {
            let previousItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: target.index - 1))
            let previousTextView = try XCTUnwrap(previousItem.testingTextView)
            mounted.window.makeFirstResponder(previousTextView)
            previousTextView.setSelectedRange(NSRange(location: (previousTextView.string as NSString).length, length: 0))

            previousTextView.keyDown(with: try optionRightEvent())
            XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: target.blockID, utf16Offset: target.offset)))
        }
    }
}

private struct WordMovementTarget {
    let index: Int
    let blockID: BlockInputBlockID
    let offset: Int
}
