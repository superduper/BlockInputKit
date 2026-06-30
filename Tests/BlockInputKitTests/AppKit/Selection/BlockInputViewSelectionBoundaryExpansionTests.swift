import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputBoundaryExpansionTests: XCTestCase {
    func testCommandDownFromEndOfBlockMovesCaretToDocumentEnd() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandDownEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 6)))
    }

    func testCommandDownToDocumentEndingImageMovesCaretAfterImage() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandDownEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
    }

    func testCommandUpFromStartOfBlockMovesCaretToDocumentStart() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandUpEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 0)))
    }

    func testShiftStyleUpFromStartOfBlockStartsSelectionWithPreviousBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID]))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testShiftStyleDownFromEndOfBlockStartsSelectionWithNextBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([secondID]))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testShiftDownFromAboveTableStartsWithHeaderRowThenPromotesAndDemotes() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let aboveItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(aboveItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .header, column: 1))
        )
        XCTAssertEqual(tableItem.testingTableCellViews.map(\.isCellSelectedForTesting), [
            true, true,
            false, false,
            false, false
        ])
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 2, length: 3))
        )))
        XCTAssertNil(tableItem.testingSelectedTableCellRange)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertNotEqual(mounted.view.selection, .blocks(["table"]))
    }

    func testShiftLeftFromBelowTableStartsWithLastRowThenPromotesAndDemotes() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(belowItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 1))
        )
        XCTAssertEqual(tableItem.testingTableCellViews.map(\.isCellSelectedForTesting), [
            false, false,
            false, false,
            true, true
        ])
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        XCTAssertNil(tableItem.testingSelectedTableCellRange)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertNotEqual(mounted.view.selection, .blocks(["table"]))
    }

    func testShiftLeftFromHeadingBelowScrolledWideTableStartsWithLastRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            Self.wideTableBlock(),
            BlockInputBlock(id: "below", kind: .heading(level: 1), text: "Images")
        ])
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(belowItem.testingTextView)
        tableItem.testingTableOverflowScrollView.contentView.scroll(to: NSPoint(x: 140, y: 0))
        tableItem.testingTableOverflowScrollView.reflectScrolledClipView(tableItem.testingTableOverflowScrollView.contentView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 3))
        )
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testEditorResponderShiftLeftFromCursorBelowTableStartsWithLastRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            Self.tableBlock(),
            BlockInputBlock(id: "below", kind: .heading(level: 1), text: "Images")
        ])
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: "below", utf16Offset: 0)), notify: true)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 1))
        )
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
    }

    func testMoveBackwardModifySelectionSelectorFromBelowTableStartsWithLastRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(belowItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSTextView.moveBackwardAndModifySelection(_:)))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 1))
        )
    }

    func testFocusEditorRestoresResponderWhileTableRowSelectionIsActive() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(belowItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)

        mounted.window.makeFirstResponder(textView)
        mounted.view.focusEditor()

        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 1))
        )
    }

    func testShiftRightFromEndOfBlockAboveTableStartsWithHeaderRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let aboveItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(aboveItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .header, column: 1))
        )
    }

    func testMoveForwardModifySelectionSelectorFromAboveTableStartsWithHeaderRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let aboveItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(aboveItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.doCommand(by: #selector(NSTextView.moveForwardAndModifySelection(_:)))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .header, column: 1))
        )
    }

    func testShiftUpFromBelowTableStartsWithLastRowAtCaretColumn() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(belowItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 1))
        )
    }

    func testSameDirectionAtDocumentEdgeKeepsPromotedTableDemotionState() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock()
        ])
        let aboveItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(aboveItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 2, length: 3))
        )))

        _ = mounted.view.performKeyEquivalent(with: try shiftDownEvent())
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(0), column: 1))
        )
    }

    func testShiftLeftOnlyStartsTableRowSelectionAtStartOfBlockBelowTable() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(belowItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertNil(tableItem.testingSelectedTableCellRange)
        XCTAssertNotEqual(mounted.view.selection, .blocks(["table"]))
    }

    func testShiftRightOnlyStartsTableRowSelectionAtEndOfBlockAboveTable() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let aboveItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(aboveItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertNil(tableItem.testingSelectedTableCellRange)
        XCTAssertNotEqual(mounted.view.selection, .blocks(["table"]))
    }

    func testMoveUpModifySelectionSelectorFromStartOfBlockStartsSelectionWithPreviousBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSTextView.moveUpAndModifySelection(_:)))

        XCTAssertEqual(mounted.view.selection, .blocks([firstID]))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testShiftDownInsideBlockStillSelectsCurrentLine() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First\nSecond")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 1, length: 5)
        )))
    }

    private static func tableBlock() -> BlockInputBlock {
        BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [["one", "two"], ["three", "four"]],
                alignments: [.left, .left]
            ).markdown
        )
    }

    private static func wideTableBlock() -> BlockInputBlock {
        BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["Feature area", "Renderer", "Editing behavior", "Notes for the demo"],
                bodyRows: [
                    ["Tables", "Structured", "Cell text, rows, columns, and selection", "Wide content scrolls horizontally inside the editor"],
                    ["Images", "Standalone", "Resize handles and Markdown export", "This demo uses a bundled local resource"]
                ],
                alignments: [.left, .left, .left, .left]
            ).markdown
        )
    }
}
