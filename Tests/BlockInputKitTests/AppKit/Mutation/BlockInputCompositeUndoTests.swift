import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputCompositeUndoTests: XCTestCase {
    @MainActor
    func testCompositeUndoFallbackReplacesDocumentInsteadOfDroppingDeletion() {
        let quoteID = BlockInputBlockID(rawValue: "quote")
        let insertedID = BlockInputBlockID(rawValue: "inserted")
        let beforeBlock = BlockInputBlock(id: quoteID, kind: .quote, text: "Line 1\nLine 2\n")
        let afterBlock = BlockInputBlock(id: quoteID, kind: .quote, text: "Line 1\nLine 2")
        let insertedBlock = BlockInputBlock(id: insertedID)
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [afterBlock, insertedBlock]))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        view.document = BlockInputDocument(blocks: [beforeBlock])
        store.resetCounts()

        view.applyUndoResult(BlockInputUndoResult(
            selection: .cursor(BlockInputCursor(blockID: quoteID, utf16Offset: beforeBlock.utf16Length)),
            actionName: "Insert Block",
            replacedBlock: beforeBlock,
            deletedBlockIDs: [insertedID]
        ))

        XCTAssertEqual(store.replaceDocumentCount, 1)
        XCTAssertEqual(store.replaceBlockIDs, [])
        XCTAssertEqual(store.deletedBlockIDs, [])
        XCTAssertEqual(store.document.blocks, [beforeBlock])
    }

    @MainActor
    func testCompositeRedoFallbackReplacesDocumentInsteadOfDroppingInsertion() {
        let quoteID = BlockInputBlockID(rawValue: "quote")
        let insertedID = BlockInputBlockID(rawValue: "inserted")
        let beforeBlock = BlockInputBlock(id: quoteID, kind: .quote, text: "Line 1\nLine 2\n")
        let afterBlock = BlockInputBlock(id: quoteID, kind: .quote, text: "Line 1\nLine 2")
        let insertedBlock = BlockInputBlock(id: insertedID)
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [beforeBlock]))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        view.document = BlockInputDocument(blocks: [afterBlock, insertedBlock])
        store.resetCounts()

        view.applyUndoResult(BlockInputUndoResult(
            selection: .cursor(BlockInputCursor(blockID: insertedID, utf16Offset: 0)),
            actionName: "Insert Block",
            replacedBlock: afterBlock,
            insertedBlocks: [insertedBlock],
            insertionIndex: 1
        ))

        XCTAssertEqual(store.replaceDocumentCount, 1)
        XCTAssertEqual(store.replaceBlockIDs, [])
        XCTAssertEqual(store.insertedBlockBatches.count, 0)
        XCTAssertEqual(store.document.blocks, [afterBlock, insertedBlock])
    }
}
