import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTablePromotionSelectionTests: XCTestCase {
    func testShiftRightAfterPromotedTableSelectsFirstCharacterOfNextBlock() throws {
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
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 2, length: 3))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 1))
        )))
        XCTAssertNil(tableItem.testingSelectedTableCellRange)
    }

    func testMoveForwardAfterPromotedTableSelectsFirstCharacterOfNextBlock() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let aboveItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(aboveItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 2, length: 3))
        )))

        mounted.view.doCommand(by: #selector(NSTextView.moveForwardAndModifySelection(_:)))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 1))
        )))
    }

    func testShiftLeftAfterPromotedTableSelectsLastCharacterOfPreviousBlock() throws {
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
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 4, length: 1))
        )))
        XCTAssertNil(tableItem.testingSelectedTableCellRange)
    }

    func testMoveBackwardAfterPromotedTableSelectsLastCharacterOfPreviousBlock() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        let belowItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let textView = try XCTUnwrap(belowItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))

        mounted.view.doCommand(by: #selector(NSTextView.moveBackwardAndModifySelection(_:)))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 4, length: 1))
        )))
    }

    func testShiftLeftContractsNextBlockTextThenDemotesRowsAfterSelectingFromAbove() throws {
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
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 2))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 1))
        )))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
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
    }

    func testMoveBackwardContractsNextBlockTextThenDemotesRowsAfterSelectingFromAbove() throws {
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
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        mounted.view.doCommand(by: #selector(NSTextView.moveForwardAndModifySelection(_:)))
        mounted.view.doCommand(by: #selector(NSTextView.moveForwardAndModifySelection(_:)))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 2))
        )))

        mounted.view.doCommand(by: #selector(NSTextView.moveBackwardAndModifySelection(_:)))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            trailingTextRange: BlockInputTextRange(blockID: "below", range: NSRange(location: 0, length: 1))
        )))
        mounted.view.doCommand(by: #selector(NSTextView.moveBackwardAndModifySelection(_:)))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        XCTAssertNil(tableItem.testingSelectedTableCellRange)

        mounted.view.doCommand(by: #selector(NSTextView.moveBackwardAndModifySelection(_:)))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(0), column: 1))
        )
    }

    func testShiftRightContractsPreviousBlockTextThenDemotesRowsAfterSelectingFromBelow() throws {
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
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 3, length: 2))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 4, length: 1))
        )))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftRightEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
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
    }

    func testMoveForwardContractsPreviousBlockTextThenDemotesRowsAfterSelectingFromBelow() throws {
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
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftLeftEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        mounted.view.doCommand(by: #selector(NSTextView.moveBackwardAndModifySelection(_:)))
        mounted.view.doCommand(by: #selector(NSTextView.moveBackwardAndModifySelection(_:)))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 3, length: 2))
        )))

        mounted.view.doCommand(by: #selector(NSTextView.moveForwardAndModifySelection(_:)))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: ["table"],
            leadingTextRange: BlockInputTextRange(blockID: "above", range: NSRange(location: 4, length: 1))
        )))
        mounted.view.doCommand(by: #selector(NSTextView.moveForwardAndModifySelection(_:)))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        XCTAssertNil(tableItem.testingSelectedTableCellRange)

        mounted.view.doCommand(by: #selector(NSTextView.moveForwardAndModifySelection(_:)))

        XCTAssertEqual(
            tableItem.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .body(1), column: 0), focus: .init(row: .body(0), column: 1))
        )
    }

    func testPlainUpFromWholeSelectedTableMovesCaretToEndOfPreviousBlock() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        mounted.view.applySelection(.blocks(["table"]), notify: true)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try plainUpEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "above", utf16Offset: 5)))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
    }

    func testPlainUpKeyEquivalentFromWholeSelectedTableMovesCaretToEndOfPreviousBlock() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        mounted.view.applySelection(.blocks(["table"]), notify: true)
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try plainUpEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "above", utf16Offset: 5)))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
    }

    func testMoveUpCommandFromWholeSelectedTableMovesCaretToEndOfPreviousBlock() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        mounted.view.applySelection(.blocks(["table"]), notify: true)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.doCommand(by: #selector(NSResponder.moveUp(_:)))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "above", utf16Offset: 5)))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
    }

    func testPlainUpFromPromotedCellWholeTableSelectionMovesCaretToEndOfPreviousBlock() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        _ = try promoteWholeTableSelectionFromLastBodyCell(in: mounted, itemIndex: 1)

        mounted.view.keyDown(with: try plainUpEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "above", utf16Offset: 5)))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
    }

    func testPlainUpKeyEquivalentFromPromotedWholeTableSelectionMovesCaretToEndOfPreviousBlock() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        _ = try promoteWholeTableSelectionFromLastBodyCell(in: mounted, itemIndex: 1)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try plainUpEvent()))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "above", utf16Offset: 5)))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
        XCTAssertNil(mounted.view.tableKeyboardRowSelection)
    }

    func testPlainUpFromTopPromotedWholeTableSelectionConsumesWithoutClearingRowState() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            Self.tableBlock(),
            BlockInputBlock(id: "below", text: "Below")
        ])
        _ = try promoteWholeTableSelectionFromLastBodyCell(in: mounted, itemIndex: 0)
        mounted.view.tableKeyboardRowSelection = Self.promotedTableRowState()

        mounted.view.keyDown(with: try plainUpEvent())

        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        XCTAssertNotNil(mounted.view.tableKeyboardRowSelection)
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
    }

    func testPlainUpFromPromotedWholeTableSelectionClearsRowStateAfterSuccessfulMove() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "above", text: "Above"),
            Self.tableBlock()
        ])
        _ = try promoteWholeTableSelectionFromLastBodyCell(in: mounted, itemIndex: 1)
        mounted.view.tableKeyboardRowSelection = Self.promotedTableRowState()
        XCTAssertNotNil(mounted.view.tableKeyboardRowSelection)

        mounted.view.keyDown(with: try plainUpEvent())

        XCTAssertNil(mounted.view.tableKeyboardRowSelection)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "above", utf16Offset: 5)))
    }
}

extension BlockInputTablePromotionSelectionTests {
    @discardableResult
    private func promoteWholeTableSelectionFromLastBodyCell(
        in mounted: (view: BlockInputView, window: NSWindow),
        itemIndex: Int
    ) throws -> BlockInputBlockItem {
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: itemIndex))
        let cell = try bodyCell(in: item, row: 1, column: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.keyDown(with: try shiftUpEvent())
        cell.keyDown(with: try shiftUpEvent())
        cell.keyDown(with: try shiftUpEvent())

        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        return item
    }

    private static func promotedTableRowState() -> BlockInputTableKeyboardRowSelection {
        BlockInputTableKeyboardRowSelection(
            tableBlockID: "table",
            originCursor: BlockInputCursor(blockID: "table", utf16Offset: 0),
            originSelection: nil,
            outsideTableSelection: nil,
            anchorDisplayRow: 0,
            focusDisplayRow: 0,
            direction: .upward,
            isPromotedToWholeTable: true
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
