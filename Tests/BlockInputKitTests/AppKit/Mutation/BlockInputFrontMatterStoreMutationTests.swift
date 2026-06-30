import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputFrontMatterStoreMutationTests: XCTestCase {
    @MainActor
    func testBlockInsertionRedoResolvesFrontMatterPinnedInsertionIndex() {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let insertedBlock = BlockInputBlock(id: "inserted", text: "Inserted")
        let body = BlockInputBlock(id: "body", text: "Body")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [front, insertedBlock, body]))
        let undoController = BlockInputUndoController()
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store, undoController: undoController))
        undoController.registerBlockInsertionStructuralEdit(
            actionName: "Insert Block",
            insertedBlocks: [insertedBlock],
            insertionIndex: 0,
            selectionBefore: .cursor(BlockInputCursor(blockID: front.id, utf16Offset: front.utf16Length)),
            selectionAfter: .cursor(BlockInputCursor(blockID: insertedBlock.id, utf16Offset: 0))
        )

        _ = view.undoStructuralEdit()
        store.resetCounts()
        _ = view.redoStructuralEdit()

        XCTAssertEqual(store.document.blocks.map(\.id), [front.id, insertedBlock.id, body.id])
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].blocks, [insertedBlock])
    }

    @MainActor
    func testReplacementInsertionRedoResolvesFrontMatterPinnedInsertionIndex() {
        let beforeFront = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Old")
        let afterFront = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: New")
        let insertedBlock = BlockInputBlock(id: "inserted", text: "Inserted")
        let body = BlockInputBlock(id: "body", text: "Body")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [afterFront, insertedBlock, body]))
        let undoController = BlockInputUndoController()
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store, undoController: undoController))
        undoController.registerBlockReplacementInsertionStructuralEdit(BlockInputReplaceInsertEdit(
            actionName: "Exit Frontmatter",
            beforeBlock: beforeFront,
            afterBlock: afterFront,
            insertedBlocks: [insertedBlock],
            insertionIndex: 0,
            selectionBefore: .cursor(BlockInputCursor(blockID: beforeFront.id, utf16Offset: beforeFront.utf16Length)),
            selectionAfter: .cursor(BlockInputCursor(blockID: insertedBlock.id, utf16Offset: 0))
        ))

        _ = view.undoStructuralEdit()
        store.resetCounts()
        _ = view.redoStructuralEdit()

        XCTAssertEqual(store.document.blocks.map(\.id), [afterFront.id, insertedBlock.id, body.id])
        XCTAssertEqual(store.document.blocks[0].text, "title: New")
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].blocks, [insertedBlock])
    }
}
