import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputEmptyDiagramRemoveOnCloseTests: XCTestCase {
    private func makeView(store: BlockInputMemoryDocumentStore) -> (view: BlockInputView, window: NSWindow) {
        var config = BlockInputConfiguration(documentStore: store)
        config.removesEmptyRenderableOnClose = true
        return makeMountedBlockInputView(configuration: config)
    }

    func testEmptyCreationClosedEmptyRemovesBlock() {
        let blockID = BlockInputBlockID(rawValue: "d1")
        // Two blocks so deleteBlock actually removes the target (single-block docs replace-with-paragraph instead).
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: "mermaid"), text: ""),
            BlockInputBlock(kind: .paragraph, text: "")
        ]))
        let (view, _) = makeView(store: store)
        view.presentInteractiveBlockContent(blockID: blockID, contentIdentifier: "code.mermaid",
                                            source: "", isEmptyCreation: true)
        view.dismissInteractiveBlockContent()  // commits; source still ""
        XCTAssertNil(store.index(of: blockID), "empty-creation closed empty removes the block")
    }

    func testEmptyCreationClosedWithContentKeepsBlock() {
        let blockID = BlockInputBlockID(rawValue: "d2")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: "mermaid"), text: ""),
            BlockInputBlock(kind: .paragraph, text: "")
        ]))
        let (view, _) = makeView(store: store)
        view.presentInteractiveBlockContent(blockID: blockID, contentIdentifier: "code.mermaid",
                                            source: "", isEmptyCreation: true)
        // Simulate the plugin committing a real diagram before close:
        view.commitInteractiveBlockContentSourceForTesting("graph TD\nA-->B")
        view.dismissInteractiveBlockContent()
        XCTAssertNotNil(store.index(of: blockID), "a created diagram is kept")
    }
}
