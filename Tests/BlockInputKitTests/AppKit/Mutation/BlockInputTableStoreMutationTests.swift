import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableStoreMutationTests: XCTestCase {
    func testStoreBackedTableRowAndColumnMutationsPublishReplaceBlockOnly() throws {
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])
        ]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))

        store.resetCounts()
        XCTAssertTrue(mounted.view.appendTableBodyRow(blockID: "table"))
        assertReplaceBlockOnly(store, blockID: "table")

        store.resetCounts()
        XCTAssertTrue(mounted.view.appendTableColumn(blockID: "table"))
        assertReplaceBlockOnly(store, blockID: "table")

        store.resetCounts()
        XCTAssertTrue(mounted.view.insertTableBodyRow(blockID: "table", position: .init(row: .body(0), column: 0)))
        assertReplaceBlockOnly(store, blockID: "table")

        store.resetCounts()
        XCTAssertTrue(mounted.view.insertTableColumn(blockID: "table", position: .init(row: .body(0), column: 0)))
        assertReplaceBlockOnly(store, blockID: "table")

        store.resetCounts()
        XCTAssertTrue(mounted.view.deleteTableBodyRow(
            blockID: "table",
            position: .init(row: .body(0), column: 0),
            keepsLastBodyRow: true
        ))
        assertReplaceBlockOnly(store, blockID: "table")

        store.resetCounts()
        XCTAssertTrue(mounted.view.deleteTableColumn(
            blockID: "table",
            position: .init(row: .body(0), column: 1)
        ))
        assertReplaceBlockOnly(store, blockID: "table")
    }

    func testStoreBackedInsertTableReplacesEmptyBlockOnly() throws {
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "empty", text: "")
        ]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))

        store.resetCounts()
        XCTAssertTrue(mounted.view.insertTable(after: "empty"))

        assertReplaceBlockOnly(store, blockID: "empty")
        XCTAssertEqual(mounted.view.document.blocks.count, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].id, "empty")
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .table)
    }

    func testStoreBackedTabFromFinalCellInsertsRowWithReplaceBlockOnly() throws {
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])
        ]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let finalCell = try bodyCell(in: item, row: 1, column: 1)
        XCTAssertTrue(mounted.window.makeFirstResponder(finalCell))

        store.resetCounts()
        finalCell.doCommand(by: #selector(NSResponder.insertTab(_:)))

        assertReplaceBlockOnly(store, blockID: "table")
        let table = try XCTUnwrap(BlockInputTable(markdown: store.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.map { $0.map(\.text) }, [["one", "two"], ["three", "four"], ["", ""]])
    }

    func testStoreBackedSelectedTableDeleteKeyUsesDeleteTableStoreActions() throws {
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            Self.tableBlock(bodyRows: [["one", "two"]]),
            BlockInputBlock(id: "second", text: "Second")
        ]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        mounted.view.applySelection(.blocks(["table"]), notify: false)

        store.resetCounts()
        mounted.view.keyDown(with: try keyDownEvent(keyCode: 117, characters: "\u{F728}"))

        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertTrue(store.replaceBlockIDs.isEmpty)
        XCTAssertTrue(store.insertedBlockBatches.isEmpty)
        XCTAssertEqual(store.deletedBlockIDs, [["table"]])
        XCTAssertEqual(store.document.blocks.map(\.id), ["first", "second"])
    }

    func testStoreBackedOnlySelectedTableDeleteKeyReplacesWithParagraph() throws {
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            Self.tableBlock(bodyRows: [["one", "two"]])
        ]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        mounted.view.applySelection(.blocks(["table"]), notify: false)

        store.resetCounts()
        mounted.view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        assertReplaceBlockOnly(store, blockID: "table")
        XCTAssertEqual(store.document.blocks.count, 1)
        XCTAssertEqual(store.document.blocks[0].id, "table")
        XCTAssertEqual(store.document.blocks[0].kind, .paragraph)
    }

    func testTableRowAndColumnMutationsRegisterStructuralUndo() throws {
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                Self.tableBlock(bodyRows: [["one", "two"], ["three", "four"]])
            ]),
            undoController: undoController
        )

        XCTAssertTrue(mounted.view.appendTableBodyRow(blockID: "table"))
        var table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.count, 3)

        let appendUndo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(appendUndo?.actionName, "Append Row")
        table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.count, 2)

        XCTAssertTrue(mounted.view.insertTableBodyRow(blockID: "table", position: .init(row: .body(0), column: 0)))
        table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.count, 3)

        let insertRowUndo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(insertRowUndo?.actionName, "Insert Row")
        table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.bodyRows.count, 2)

        XCTAssertTrue(mounted.view.insertTableColumn(blockID: "table", position: .init(row: .body(0), column: 0)))
        table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.columnCount, 3)

        let insertColumnUndo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(insertColumnUndo?.actionName, "Insert Column")
        table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.columnCount, 2)

        XCTAssertTrue(mounted.view.deleteTableColumn(
            blockID: "table",
            position: .init(row: .body(0), column: 1)
        ))
        table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.columnCount, 1)

        let deleteUndo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(deleteUndo?.actionName, "Delete Column")
        table = try XCTUnwrap(BlockInputTable(markdown: mounted.view.document.blocks[0].text))
        XCTAssertEqual(table.columnCount, 2)
    }

    private func assertReplaceBlockOnly(_ store: CountingDocumentStore, blockID: BlockInputBlockID) {
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [blockID])
        XCTAssertTrue(store.insertedBlockBatches.isEmpty)
        XCTAssertTrue(store.deletedBlockIDs.isEmpty)
    }

    private static func tableBlock(bodyRows: [[String]]) -> BlockInputBlock {
        BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: bodyRows,
                alignments: [.left, .left]
            ).markdown
        )
    }
}
