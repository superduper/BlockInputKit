import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class LargeDocUndoPerformanceTests: XCTestCase {
    func testStoreBackedTextUndoRedoDoesNotReadFullDocumentSnapshot() {
        let context = makeTextUndoView()
        context.store.resetCounts()

        XCTAssertTrue(context.view.performUndoShortcut(.undo))

        assertTextUndoStoreState(context.store, blockID: context.blockID, text: "Original")
        context.store.resetCounts()

        XCTAssertTrue(context.view.performUndoShortcut(.redo))

        assertTextUndoStoreState(context.store, blockID: context.blockID, text: "Edited")
    }

    func testPublicTextUndoRedoDoesNotReadFullDocumentSnapshot() {
        let context = makeTextUndoView()
        context.store.resetCounts()

        XCTAssertNotNil(context.view.undoTextEditInActiveBlock())

        assertTextUndoStoreState(context.store, blockID: context.blockID, text: "Original")
        context.store.resetCounts()

        XCTAssertNotNil(context.view.redoTextEditInActiveBlock())

        assertTextUndoStoreState(context.store, blockID: context.blockID, text: "Edited")
    }

    private func makeTextUndoView() -> TextUndoContext {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: index == targetIndex ? "Edited" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let undoController = BlockInputUndoController()
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store, undoController: undoController))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)), notify: false)
        undoController.registerTextEdit(
            blockID: blockID,
            beforeText: "Original",
            afterText: "Edited",
            selectionBefore: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 8)),
            selectionAfter: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6))
        )
        return TextUndoContext(view: view, store: store, blockID: blockID)
    }

    private func assertTextUndoStoreState(
        _ store: DocumentReadCountingStore,
        blockID: BlockInputBlockID,
        text: String
    ) {
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.block(withID: blockID)?.text, text)
    }
}

private struct TextUndoContext {
    var view: BlockInputView
    var store: DocumentReadCountingStore
    var blockID: BlockInputBlockID
}
