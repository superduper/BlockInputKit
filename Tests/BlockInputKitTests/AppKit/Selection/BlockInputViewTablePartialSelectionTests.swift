import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTablePartialSelectionTests: XCTestCase {
    func testShiftLeftFromPartialSelectionBelowTableStartsWithLastRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(belowItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 2))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 1))
        )
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 2))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 2))
        )))
        XCTAssertNil(tableItem.testingSelectedTableCellRange)
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 1))
        )
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 2))
        )))
    }

    func testShiftLeftExtendsPartialSelectionToStartBeforeSelectingRowsFromBelow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(belowItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 1, length: 1))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertNil(tableItem.testingSelectedTableCellRange)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 2))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 1))
        )
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 2))
        )))
    }

    func testShiftRightFromPartialSelectionAboveTableStartsWithHeaderRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let aboveItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(aboveItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 2))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .header, column: 1))
        )
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 3, length: 2))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 3, length: 2))
        )))
        XCTAssertNil(tableItem.testingSelectedTableCellRange)
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .header, column: 1))
        )
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 3, length: 2))
        )))
    }

    func testShiftRightExtendsPartialSelectionToEndBeforeSelectingRowsFromAbove() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let aboveItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(aboveItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 1))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertNil(tableItem.testingSelectedTableCellRange)
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 3, length: 2))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .header, column: 1))
        )
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 3, length: 2))
        )))
    }

    func testShiftDownFromCaretAboveTableSelectsTextAfterCaretAndHeaderRow() throws {
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
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 2, length: 3))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "above", utf16Offset: 2)))
        XCTAssertNil(tableItem.testingSelectedTableCellRange)
    }

    func testShiftDownFromPartialSelectionAboveTableStartsWithHeaderRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let aboveItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(aboveItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 2))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .header, column: 1))
        )
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 3, length: 2))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .header, column: 1))
        )
    }

    func testShiftUpFromCaretBelowTableSelectsTextBeforeCaretAndLastRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Images")
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
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 3))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "below", utf16Offset: 3)))
        XCTAssertNil(tableItem.testingSelectedTableCellRange)
    }

    func testShiftUpFromPartialSelectionBelowTableStartsWithLastRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(belowItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 2))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 1))
        )
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 2))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(0), column: 1))
        )
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(1), column: 1))
        )
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
}
