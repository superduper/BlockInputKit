import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewWordSelectionTests: XCTestCase {
    func testOptionShiftRightInsideBlockUsesNativeWordSelectionAndSyncsEditorSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Alpha beta")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try optionShiftRightEvent()))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 5))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 5)
        )))
    }

    func testOptionShiftRightAtBlockEndExtendsIntoNextBlockByWord() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma delta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 10, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try optionShiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 5))
        )))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testRepeatedOptionShiftRightExtendsSelectionByWordsInNextBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta gamma")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try optionShiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionShiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([secondID]))
    }

    func testOptionShiftLeftAtBlockStartExtendsIntoPreviousBlockByWord() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try optionShiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 6, length: 4))
        )))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testRepeatedOptionShiftLeftExtendsSelectionByWordsInPreviousBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha beta"),
            BlockInputBlock(id: secondID, text: "Gamma")
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(secondItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try optionShiftLeftEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionShiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID]))
    }

    func testOptionShiftLeftContractsRightwardCrossBlockWordSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta gamma")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try optionShiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionShiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))
    }

    func testOptionShiftRightThroughHorizontalRuleSelectsRuleThenNextWord() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let lastID = BlockInputBlockID(rawValue: "last")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: ruleID, kind: .horizontalRule),
            BlockInputBlock(id: lastID, text: "Last word")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try optionShiftRightEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks([ruleID]))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionShiftRightEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [ruleID],
            trailingTextRange: BlockInputTextRange(blockID: lastID, range: NSRange(location: 0, length: 4))
        )))
    }

    func testOptionShiftRightThroughEmptyBlockSelectsEmptyThenNextWord() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let emptyID = BlockInputBlockID(rawValue: "empty")
        let lastID = BlockInputBlockID(rawValue: "last")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: emptyID, text: ""),
            BlockInputBlock(id: lastID, text: "Last word")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try optionShiftRightEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks([emptyID]))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try optionShiftRightEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [emptyID],
            trailingTextRange: BlockInputTextRange(blockID: lastID, range: NSRange(location: 0, length: 4))
        )))
    }

    func testOptionShiftRightAllowsNumericPadArrowFlag() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try optionShiftRightEvent(modifierFlags: [.option, .shift, .numericPad])))

        XCTAssertEqual(mounted.view.selection, .blocks([secondID]))
    }

    func testOptionShiftWordSelectionCopyUsesMixedSelectionSpan() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let blocks = [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta gamma")
        ]
        let optionCopy = try copiedStringAfterOptionShiftSelection(blocks: blocks)
        let manualCopy = try copiedStringAfterManualSelection(
            blocks: blocks,
            selection: .mixed(BlockInputMixedSelection(
                blockIDs: [],
                trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 4))
            ))
        )

        XCTAssertEqual(optionCopy, "Beta")
        XCTAssertEqual(optionCopy, manualCopy)
    }

    func testOptionShiftWordSelectionStaysInsideTableCell() throws {
        let tableBlock = BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [["Alpha beta", "two"]],
                alignments: [.left, .left]
            ).markdown
        )
        let mounted = makeMountedBlockInputView(blocks: [tableBlock])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let table = try XCTUnwrap(BlockInputTable(markdown: tableBlock.text))
        mounted.window.makeFirstResponder(cell)
        cell.setSelectedRange(NSRange(location: 0, length: 0))

        cell.doCommand(by: #selector(NSResponder.moveWordRightAndModifySelection(_:)))

        XCTAssertEqual(cell.selectedRange(), NSRange(location: 0, length: 5))
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(blockID: "table", position: .init(row: .body(0), column: 0), localRange: NSRange(location: 0, length: 5))
        )
    }

    func testShiftRightAtTableCellLinkSourceBoundaryStaysInsideCell() throws {
        let cellText = "Open [docs](https://example.com)"
        let tableBlock = BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [[cellText, "two"]],
                alignments: [.left, .left]
            ).markdown
        )
        let mounted = makeMountedBlockInputView(blocks: [tableBlock])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let table = try XCTUnwrap(BlockInputTable(markdown: tableBlock.text))
        let linkRange = try XCTUnwrap(inlineLinkRange(in: cellText))
        mounted.window.makeFirstResponder(cell)
        cell.setSelectedRange(NSRange(location: linkRange.fullRange.location, length: 0))

        cell.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))

        let selectedRange = NSRange(location: linkRange.contentRange.location, length: 1)
        XCTAssertEqual(cell.selectedRange(), selectedRange)
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(blockID: "table", position: .init(row: .body(0), column: 0), localRange: selectedRange)
        )
    }

    func testShiftRightKeyEquivalentAtTableCellLinkSourceBoundaryStaysInsideCell() throws {
        let cellText = "Open [docs](https://example.com)"
        let tableBlock = BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [[cellText, "two"]],
                alignments: [.left, .left]
            ).markdown
        )
        let mounted = makeMountedBlockInputView(blocks: [tableBlock])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let table = try XCTUnwrap(BlockInputTable(markdown: tableBlock.text))
        let linkRange = try XCTUnwrap(inlineLinkRange(in: cellText))
        mounted.window.makeFirstResponder(cell)
        cell.setSelectedRange(NSRange(location: linkRange.fullRange.location, length: 0))

        XCTAssertTrue(cell.performKeyEquivalent(with: try shiftRightEvent()))

        let selectedRange = NSRange(location: linkRange.contentRange.location, length: 1)
        XCTAssertEqual(cell.selectedRange(), selectedRange)
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(blockID: "table", position: .init(row: .body(0), column: 0), localRange: selectedRange)
        )
    }

    private func copiedStringAfterOptionShiftSelection(blocks: [BlockInputBlock]) throws -> String? {
        let mounted = makeMountedBlockInputView(blocks: blocks)
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: blocks[0].utf16Length, length: 0))
        XCTAssertTrue(textView.performKeyEquivalent(with: try optionShiftRightEvent()))
        return try copiedString(from: mounted.view)
    }

    private func copiedStringAfterManualSelection(blocks: [BlockInputBlock], selection: BlockInputSelection) throws -> String? {
        let mounted = makeMountedBlockInputView(blocks: blocks)
        mounted.view.applySelection(selection, notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        return try copiedString(from: mounted.view)
    }

    private func copiedString(from view: BlockInputView) throws -> String? {
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
        XCTAssertTrue(view.performKeyEquivalent(with: try commandCEvent()))
        return pasteboard.string(forType: .string)
    }

    private func inlineLinkRange(in text: String) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        )
        .first { $0.style == .link }
    }
}
