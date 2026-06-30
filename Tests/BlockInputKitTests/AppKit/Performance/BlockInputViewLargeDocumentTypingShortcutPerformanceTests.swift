import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class LargeDocTypingShortcutPerformanceTests: XCTestCase {
    func testShortcutInInsertedLargeDocumentBlockUsesStoreBlockWithoutSnapshot() throws {
        let targetID = BlockInputBlockID(rawValue: "block-50000")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: index == 50_000 ? "Target" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController()
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: targetID, utf16Offset: 6)), notify: false)
        store.resetCounts()

        let insertionSelection = try XCTUnwrap(view.insertBlockBelowCurrentBlock())
        guard case let .cursor(insertedCursor) = insertionSelection else {
            return XCTFail("Expected inserted block cursor")
        }
        let insertedBlock = try XCTUnwrap(store.block(withID: insertedCursor.blockID))
        let item = BlockInputBlockItem.configuredForTesting(
            block: insertedBlock,
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "# Heading"
        textView.setSelectedRange(NSRange(location: 9, length: 0))

        view.blockItem(
            item,
            blockID: insertedCursor.blockID,
            didChangeText: "# Heading",
            selectionBefore: .cursor(insertedCursor)
        )

        let formattedBlock = try XCTUnwrap(store.block(withID: insertedCursor.blockID))
        XCTAssertEqual(formattedBlock.kind, .heading(level: 1))
        XCTAssertEqual(formattedBlock.text, "Heading")
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.replacedBlockIDs, [insertedCursor.blockID])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: insertedCursor.blockID, utf16Offset: 7)))
    }

    func testHorizontalRuleShortcutInLargeDocumentUsesGranularStoreOperations() throws {
        let blockID = BlockInputBlockID(rawValue: "block-50000")
        let (store, view) = makeLargeDocumentView(
            targetBlockID: blockID,
            targetText: "",
            undoController: BlockInputUndoController()
        )
        store.resetCounts()
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: blockID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "---"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        view.blockItem(
            item,
            blockID: blockID,
            didChangeText: "---",
            selectionBefore: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0))
        )

        XCTAssertEqual(store.block(withID: blockID)?.kind, .horizontalRule)
        XCTAssertEqual(store.block(withID: blockID)?.text, "")
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, 50_001)
        XCTAssertEqual(store.insertedBlockBatches[0].blocks[0].kind, .paragraph)
        XCTAssertEqual(store.document.blocks.count, 100_001)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(
            blockID: store.insertedBlockBatches[0].blocks[0].id,
            utf16Offset: 0
        )))

        let insertedBlockID = store.insertedBlockBatches[0].blocks[0].id
        store.resetCounts()
        _ = view.undoStructuralEdit()

        XCTAssertEqual(store.block(withID: blockID)?.kind, .paragraph)
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.deletedBlockIDs, [[insertedBlockID]])

        store.resetCounts()
        _ = view.redoStructuralEdit()

        XCTAssertEqual(store.block(withID: blockID)?.kind, .horizontalRule)
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
    }

    func testHorizontalRuleShortcutInLargeDocumentMovesTextIntoInsertedBlockGranularly() throws {
        let blockID = BlockInputBlockID(rawValue: "block-50000")
        let (store, view) = makeLargeDocumentView(
            targetBlockID: blockID,
            targetText: "Existing",
            undoController: BlockInputUndoController()
        )
        store.resetCounts()
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: blockID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "---    Existing"
        textView.setSelectedRange(NSRange(location: 15, length: 0))

        view.blockItem(
            item,
            blockID: blockID,
            didChangeText: "---    Existing",
            selectionBefore: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0))
        )

        XCTAssertEqual(store.block(withID: blockID)?.kind, .horizontalRule)
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].blocks[0].text, "Existing")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(
            blockID: store.insertedBlockBatches[0].blocks[0].id,
            utf16Offset: 8
        )))
    }

    func testNoSpaceHorizontalRuleShortcutInLargeDocumentMovesTextIntoInsertedBlockGranularly() throws {
        let blockID = BlockInputBlockID(rawValue: "block-50000")
        let (store, view) = makeLargeDocumentView(
            targetBlockID: blockID,
            targetText: "Existing",
            undoController: BlockInputUndoController()
        )
        store.resetCounts()
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: blockID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "---Existing"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        view.blockItem(
            item,
            blockID: blockID,
            didChangeText: "---Existing",
            selectionBefore: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0))
        )

        XCTAssertEqual(store.block(withID: blockID)?.kind, .horizontalRule)
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].blocks[0].text, "Existing")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(
            blockID: store.insertedBlockBatches[0].blocks[0].id,
            utf16Offset: 0
        )))
    }

    private func makeLargeDocumentView(
        targetBlockID: BlockInputBlockID,
        targetText: String,
        undoController: BlockInputUndoController? = nil
    ) -> (DocumentReadCountingStore, BlockInputView) {
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: index == 50_000 ? targetText : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: undoController
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: targetBlockID, utf16Offset: targetText.utf16.count)), notify: false)
        return (store, view)
    }
}
