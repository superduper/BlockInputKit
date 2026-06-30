import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableCellEditingTests: XCTestCase {
    func testMountedCellEditingUpdatesTableMarkdownAndSourceSelection() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.setSelectedRange(NSRange(location: 3, length: 0))
        cell.insertText("X", replacementRange: cell.selectedRange())

        let expectedTable = BlockInputTable.normalized(
            header: ["H1", "H2"],
            bodyRows: [["oneX", "two"]],
            alignments: [.left, .left]
        )
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedTable.markdown)
        XCTAssertEqual(
            mounted.view.selection,
            expectedTable.selection(blockID: "table", position: .init(row: .body(0), column: 0), localRange: NSRange(location: 4, length: 0))
        )
        XCTAssertTrue(mounted.window.firstResponder === cell)
        XCTAssertTrue(item.testingTableCellTextViews.contains { $0 === cell })
    }

    func testFormattingShortcutAppliesInsideTableCellThroughSharedMutationPath() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.setSelectedRange(NSRange(location: 0, length: 3))
        XCTAssertTrue(cell.performKeyEquivalent(with: try commandBEvent()))

        let expectedTable = BlockInputTable.normalized(
            header: ["H1", "H2"],
            bodyRows: [["**one**", "two"]],
            alignments: [.left, .left]
        )
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedTable.markdown)
        XCTAssertEqual(
            mounted.view.selection,
            expectedTable.selection(blockID: "table", position: .init(row: .body(0), column: 0), localRange: NSRange(location: 2, length: 3))
        )
    }

    func testURLPasteInTableCellUsesSharedLinkMutationPath() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        cell.setSelectedRange(NSRange(location: 0, length: 3))

        withCleanTableCellPasteboard { pasteboard in
            pasteboard.setString("https://example.com", forType: .string)
            cell.paste(nil)
        }

        let expectedTable = BlockInputTable.normalized(
            header: ["H1", "H2"],
            bodyRows: [["[one](https://example.com)", "two"]],
            alignments: [.left, .left]
        )
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedTable.markdown)
    }

    func testStoreBackedCellEditPublishesReplaceBlockOnly() throws {
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [Self.tableBlock()]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        store.resetCounts()

        cell.setSelectedRange(NSRange(location: 3, length: 0))
        cell.insertText("X", replacementRange: cell.selectedRange())

        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, ["table"])
        XCTAssertEqual(store.document.blocks[0].text, mounted.view.document.blocks[0].text)
    }

    func testCellTextUndoRestoresTableBlock() throws {
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [Self.tableBlock()]),
            undoController: undoController
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        let beforeText = mounted.view.document.blocks[0].text

        cell.setSelectedRange(NSRange(location: 3, length: 0))
        cell.insertText("X", replacementRange: cell.selectedRange())
        XCTAssertTrue(cell.performKeyEquivalent(with: try commandZEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, beforeText)
    }

    func testTableCellsUseNativeMouseSelectionInsteadOfBlockDragTracking() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)

        XCTAssertFalse(cell.shouldTrackBlockSelectionDrag(for: try mouseDownEvent(windowNumber: mounted.window.windowNumber)))
    }

    func testTabMovesLeftToRightThroughTableCells() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstHeaderCell = try tableCell(in: item, row: 0, column: 0, columnCount: 2)
        let secondHeaderCell = try tableCell(in: item, row: 0, column: 1, columnCount: 2)
        XCTAssertTrue(mounted.window.makeFirstResponder(firstHeaderCell))

        firstHeaderCell.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertTrue(mounted.window.firstResponder === secondHeaderCell)
    }

    func testShiftTabAndReturnMoveBetweenTableCells() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstHeaderCell = try tableCell(in: item, row: 0, column: 0, columnCount: 2)
        let secondHeaderCell = try tableCell(in: item, row: 0, column: 1, columnCount: 2)
        let firstBodyCell = try bodyCell(in: item, row: 0, column: 0)
        let secondBodyRowCell = try bodyCell(in: item, row: 1, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(secondHeaderCell))

        secondHeaderCell.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        XCTAssertTrue(mounted.window.firstResponder === firstHeaderCell)

        firstHeaderCell.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(mounted.window.firstResponder === firstBodyCell)

        XCTAssertTrue(mounted.window.makeFirstResponder(secondBodyRowCell))
        secondBodyRowCell.doCommand(by: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
        XCTAssertTrue(mounted.window.firstResponder === firstBodyCell)
    }

    func testShiftArrowCommandInsideCellRoutesToTableCellSelection() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            Self.tableBlock(),
            BlockInputBlock(id: "after", text: "After")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.setSelectedRange(NSRange(location: 0, length: 0))
        cell.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))

        XCTAssertEqual(
            item.testingSelectedTableCellRange,
            BlockInputTableCellSelection(anchor: .init(row: .header, column: 0), focus: .init(row: .body(0), column: 0))
        )
        XCTAssertNotEqual(mounted.view.selection, .blocks(["table"]))

        cell.doCommand(by: #selector(NSResponder.moveDown(_:)))

        XCTAssertTrue(mounted.window.firstResponder === cell)
    }

    func testDeleteInEmptyBodyCellSelectsThenDeletesRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["", "two"], ["next", "row"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        XCTAssertEqual(item.testingSelectedTableRow, .body(0))

        cell.doCommand(by: #selector(NSResponder.deleteForward(_:)))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["next", "row"]])
        let focusedCell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.firstResponder === focusedCell)
    }

    func testDeleteInNonemptyCellUsesNativeTextDeletion() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.setSelectedRange(NSRange(location: 3, length: 0))
        cell.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows[0][0].text, "on")
    }

    func testPastedNewlinesInCellCollapseToSingleLineText() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["", "two"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.insertText("line 1\nline 2", replacementRange: cell.selectedRange())

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(cell.string, "line 1 line 2")
        XCTAssertEqual(table.bodyRows[0][0].text, "line 1 line 2")
    }

    func testDeletingOnlyBodyRowLeavesEmptyBodyRow() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["", "two"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        cell.doCommand(by: #selector(NSResponder.deleteForward(_:)))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["", ""]])
    }

    func testCellFocusClearsPendingRowSelection() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["", "two"], ["next", "row"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let emptyCell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(emptyCell))

        emptyCell.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        XCTAssertEqual(item.testingSelectedTableRow, .body(0))

        let otherCell = try bodyCell(in: item, row: 1, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(otherCell))
        otherCell.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertNil(item.testingSelectedTableRow)
    }

    func testDeleteInEmptyHeaderCellSelectsHeaderWithoutDeletingIt() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(header: ["", "H2"])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try tableCell(in: item, row: 0, column: 0, columnCount: 2)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        cell.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.header.map(\.text), ["", "H2"])
        XCTAssertEqual(item.testingSelectedTableRow, .header)
    }

    func testReturnAtTableBoundariesInsertsParagraphs() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let bodyCell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(bodyCell))

        bodyCell.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.table, .paragraph])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: mounted.view.document.blocks[1].id, utf16Offset: 0)))

        let tableItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let headerCell = try tableCell(in: tableItem, row: 0, column: 0, columnCount: 2)
        XCTAssertTrue(mounted.window.makeFirstResponder(headerCell))
        headerCell.doCommand(by: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.paragraph, .table, .paragraph])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: mounted.view.document.blocks[0].id, utf16Offset: 0)))
    }

    func testContextMenuShowsTableItemsBelowInsertLink() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        let menu = try XCTUnwrap(cell.menu(for: try rightMouseDownEvent(
            location: cell.convert(NSPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: nil),
            windowNumber: mounted.window.windowNumber
        )))
        let insertLinkIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Insert Link" })

        XCTAssertEqual(menu.items[insertLinkIndex + 1].title, "Insert Row")
        XCTAssertEqual(menu.items[insertLinkIndex + 2].title, "Insert Column")
        XCTAssertEqual(menu.items[insertLinkIndex + 3].title, "Delete Row")
        XCTAssertEqual(menu.items[insertLinkIndex + 4].title, "Delete Column")
        XCTAssertEqual(menu.items[insertLinkIndex + 5].title, "Delete Table")
        XCTAssertEqual(menu.items[insertLinkIndex + 3].accessibilityLabel(), "Delete Row")
    }

    func testContextMenuOmitsUnavailableTableActions() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(header: ["H1"], bodyRows: [["one"]])])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try tableCell(in: item, row: 1, column: 0, columnCount: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        let menu = try XCTUnwrap(cell.menu(for: try rightMouseDownEvent(
            location: cell.convert(NSPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: nil),
            windowNumber: mounted.window.windowNumber
        )))

        XCTAssertNil(menu.item(withTitle: "Delete Row"))
        XCTAssertNil(menu.item(withTitle: "Delete Column"))
        XCTAssertNotNil(menu.item(withTitle: "Insert Row"))
        XCTAssertNotNil(menu.item(withTitle: "Insert Column"))
        XCTAssertNotNil(menu.item(withTitle: "Delete Table"))
    }

    func testContextMenuTableActionsMutateTable() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let firstCell = try bodyCell(in: firstItem, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(firstCell))

        try performTableCellMenuItem(titled: "Delete Row", in: tableCellMenu(for: firstCell, windowNumber: mounted.window.windowNumber))
        var table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["three", "four"]])

        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondCell = try bodyCell(in: secondItem, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(secondCell))
        try performTableCellMenuItem(titled: "Delete Column", in: tableCellMenu(for: secondCell, windowNumber: mounted.window.windowNumber))
        table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.columnCount, 1)

        let thirdItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let thirdCell = try tableCell(in: thirdItem, row: 1, column: 0, columnCount: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(thirdCell))
        try performTableCellMenuItem(titled: "Delete Table", in: tableCellMenu(for: thirdCell, windowNumber: mounted.window.windowNumber))
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.paragraph])
    }

    func testInsertTableContextMenuInsertsTableBelowApplicableBlockAndFocusesHeader() throws {
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "paragraph", text: "Start")])
        let textView = try tableEditingTextView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let menu = try XCTUnwrap(textView.menu(for: try rightMouseDownEvent(windowNumber: mounted.window.windowNumber)))
        let insertLinkIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Insert Link" })

        XCTAssertEqual(menu.items[insertLinkIndex + 1].title, "Insert Image")
        XCTAssertEqual(menu.items[insertLinkIndex + 2].title, "Insert Table")

        try performTableCellMenuItem(titled: "Insert Table", in: menu)

        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.paragraph, .table])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let firstHeaderCell = try tableCell(in: item, row: 0, column: 0, columnCount: 2)
        XCTAssertTrue(mounted.window.firstResponder === firstHeaderCell)
        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[1].text))
        XCTAssertEqual(table.header.count, 2)
        XCTAssertEqual(table.bodyRows.count, 1)
    }

    func testInsertTableContextMenuVisibilityMatchesApplicableBlockKinds() throws {
        let applicableKinds: [BlockInputBlockKind] = [
            .paragraph,
            .heading(level: 2),
            .quote,
            .bulletedListItem,
            .numberedListItem(start: 1),
            .checklistItem(isChecked: false)
        ]
        for kind in applicableKinds {
            let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", kind: kind, text: "Start")])
            let textView = try tableEditingTextView(in: mounted.view)
            textView.setSelectedRange(NSRange(location: 0, length: 0))

            let menu = try XCTUnwrap(textView.menu(for: try rightMouseDownEvent(windowNumber: mounted.window.windowNumber)))

            XCTAssertNotNil(menu.item(withTitle: "Insert Table"), "Expected Insert Table for \(kind)")
        }

        let unsupportedBlocks = [
            BlockInputBlock(id: "code", kind: .code(language: nil), text: "let value = 1"),
            BlockInputBlock(id: "frontMatter", kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "raw", kind: .rawMarkdown, text: "<div>Raw</div>")
        ]
        for block in unsupportedBlocks {
            let mounted = makeMountedBlockInputView(blocks: [block])
            let textView = try tableEditingTextView(in: mounted.view)
            textView.setSelectedRange(NSRange(location: 0, length: 0))

            let menu = try XCTUnwrap(textView.menu(for: try rightMouseDownEvent(windowNumber: mounted.window.windowNumber)))

            XCTAssertNil(menu.item(withTitle: "Insert Table"), "Did not expect Insert Table for \(block.kind)")
        }

        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let menu = try tableCellMenu(for: cell, windowNumber: mounted.window.windowNumber)

        XCTAssertNil(menu.item(withTitle: "Insert Table"))
    }

    func testSelectAllEscalatesFromCellToTableToDocument() throws {
        let paragraph = BlockInputBlock(id: "paragraph", text: "Start")
        let mounted = makeMountedBlockInputView(blocks: [paragraph, Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        let table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[1].text))
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.doCommand(by: #selector(NSResponder.selectAll(_:)))
        XCTAssertEqual(
            mounted.view.selection,
            table.selection(blockID: "table", position: .init(row: .body(0), column: 0), localRange: NSRange(location: 0, length: 3))
        )

        cell.doCommand(by: #selector(NSResponder.selectAll(_:)))
        XCTAssertEqual(mounted.view.selection, .blocks(["table"]))

        cell.doCommand(by: #selector(NSResponder.selectAll(_:)))
        XCTAssertEqual(mounted.view.selection, .blocks(["paragraph", "table"]))
    }

    func testWholeTableCopyFromFocusedCellUsesMarkdown() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        mounted.view.applySelection(.blocks(["table"]), notify: true)

        withCleanTableCellPasteboard { pasteboard in
            cell.copy(nil)
            XCTAssertEqual(pasteboard.string(forType: .string), mounted.view.document.blocks[0].text)
        }
    }

    func testAppendControlsAddRowsAndColumns() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.tableBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        item.testingAppendTableRowButton.performClick(nil)
        var table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.count, 2)

        item.testingAppendTableColumnButton.performClick(nil)
        table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.columnCount, 3)
    }

    func testTableCellsRejectCompletionAndFileDrops() throws {
        let provider = PopupCompletionProvider(suggestions: [
            .slashCommand(title: "Table", uri: "host-app://commands/table", label: "table")
        ])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [Self.tableBlock(bodyRows: [["/tab", "two"]])]),
            completionProvider: provider,
            slashCommandAvailability: .anywhere
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))

        cell.setSelectedRange(NSRange(location: 4, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: "table")

        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(provider.lastContext)

        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/Table.md")],
            location: cell.convert(NSPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: nil)
        )
        XCTAssertTrue(cell.draggingEntered(draggingInfo).isEmpty)
        XCTAssertFalse(cell.performDragOperation(draggingInfo))
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .table)
    }

    func bodyCell(in item: BlockInputBlockItem, row: Int, column: Int) throws -> BlockInputTableCellTextView {
        try tableCell(in: item, row: row + 1, column: column, columnCount: 2)
    }

    func tableCell(in item: BlockInputBlockItem, row: Int, column: Int, columnCount: Int) throws -> BlockInputTableCellTextView {
        let index = row * columnCount + column
        return try XCTUnwrap(item.testingTableCellTextViews.indices.contains(index) ? item.testingTableCellTextViews[index] : nil)
    }

    static func tableBlock(
        header: [String] = ["H1", "H2"],
        bodyRows: [[String]] = [["one", "two"]]
    ) -> BlockInputBlock {
        let columnCount = max(header.count, bodyRows.map(\.count).max() ?? 0)
        return BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: header,
                bodyRows: bodyRows,
                alignments: Array(repeating: .left, count: columnCount)
            ).markdown
        )
    }
}
