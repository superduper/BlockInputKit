import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class LargeDocCompletionPerformanceTests: XCTestCase {
    func testStoreBackedAcceptCompletionDoesNotReadFullDocumentSnapshot() {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: index == targetIndex ? "Hello @al" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store, undoController: BlockInputUndoController()))
        view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 6, length: 3)
        )), notify: false)
        store.resetCounts()

        let selection = view.acceptCompletionSuggestion(BlockInputCompletionSuggestion(
            id: "mention:alice",
            title: "Alice",
            insertionText: "@alice",
            trigger: .mention
        ))

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.block(withID: blockID)?.text, "Hello @alice")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 12)))
    }
}
