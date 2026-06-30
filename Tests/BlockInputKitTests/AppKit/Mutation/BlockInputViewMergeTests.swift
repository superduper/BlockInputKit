import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewMergeTests: XCTestCase {
    func testDeleteAtFrontOfParagraphMergesIntoPreviousEmptyNumberedListItem() throws {
        let listID = BlockInputBlockID(rawValue: "list")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: listID, kind: .numberedListItem(start: 1)),
            BlockInputBlock(id: paragraphID, text: "Toggle reordering from the toolbar")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[1],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(view.document.blocks.map(\.id), [listID])
        XCTAssertEqual(view.document.blocks[0].kind, .numberedListItem(start: 1))
        XCTAssertEqual(view.document.blocks[0].text, "Toggle reordering from the toolbar")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: listID, utf16Offset: 0)))
    }

    func testMergeParagraphIntoPreviousBlockPublishesGranularStoreOperations() {
        let listID = BlockInputBlockID(rawValue: "list")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: listID, kind: .numberedListItem(start: 1)),
            BlockInputBlock(id: paragraphID, text: "Toggle reordering from the toolbar")
        ]))
        let view = BlockInputView()
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: paragraphID, utf16Offset: 0)), notify: false)
        store.resetCounts()

        _ = view.mergeBlockIntoPrevious(blockID: paragraphID)

        XCTAssertEqual(store.document.blocks.map(\.id), [listID])
        XCTAssertEqual(store.document.blocks[0].text, "Toggle reordering from the toolbar")
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [listID])
        XCTAssertEqual(store.deletedBlockIDs, [[paragraphID]])
        XCTAssertEqual(mutations, [
            .replaceBlock(store.document.blocks[0]),
            .deleteBlocks([paragraphID])
        ])
    }

    func testMergeParagraphUndoRedoStaysGranular() {
        let listID = BlockInputBlockID(rawValue: "list")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: listID, kind: .numberedListItem(start: 1)),
            BlockInputBlock(id: paragraphID, text: "Toggle reordering from the toolbar")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController()
        ))
        _ = view.mergeBlockIntoPrevious(blockID: paragraphID)
        store.resetCounts()

        _ = view.undoStructuralEdit()

        XCTAssertEqual(store.document.blocks.map(\.id), [listID, paragraphID])
        XCTAssertEqual(store.document.blocks.map(\.text), ["", "Toggle reordering from the toolbar"])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [listID])
        XCTAssertEqual(store.insertedBlockBatches.map(\.index), [1])
        store.resetCounts()

        _ = view.redoStructuralEdit()

        XCTAssertEqual(store.document.blocks.map(\.id), [listID])
        XCTAssertEqual(store.document.blocks[0].text, "Toggle reordering from the toolbar")
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [listID])
        XCTAssertEqual(store.deletedBlockIDs, [[paragraphID]])
    }
}
