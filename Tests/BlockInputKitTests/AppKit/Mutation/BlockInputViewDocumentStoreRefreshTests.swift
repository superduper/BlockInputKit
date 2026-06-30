import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputViewDocumentStoreRefreshTests: XCTestCase {
    @MainActor
    func testFocusRefreshesFromStoreBeforeResolvingBlock() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "Replacement")
        ]))

        view.focus(blockID: replacementID, utf16Offset: 99)

        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: replacementID, utf16Offset: 11)))
    }

    @MainActor
    func testConfigureClearsStaleSelectionAgainstConfiguredStore() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let staleStore = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let replacementStore = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "Replacement")
        ]))
        let view = BlockInputView()
        var publishedSelections: [BlockInputSelection?] = []
        view.configure(BlockInputConfiguration(
            documentStore: staleStore,
            onSelectionChange: { publishedSelections.append($0) }
        ))
        view.focus(blockID: staleID)

        view.configure(BlockInputConfiguration(
            documentStore: replacementStore,
            onSelectionChange: { publishedSelections.append($0) }
        ))

        XCTAssertNil(view.selection)
        guard let lastPublishedSelection = publishedSelections.last else {
            return XCTFail("Expected configure to publish a nil selection")
        }
        XCTAssertNil(lastPublishedSelection)
    }

    @MainActor
    func testFocusRefreshesMountedItemTextFromStoreBeforeSelecting() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Old")
        ]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertEqual(item.testingTextView?.string, "Old")
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "New text")
        ]))

        mounted.view.focus(blockID: blockID, utf16Offset: 99)

        XCTAssertEqual(item.testingTextView?.string, "New text")
        XCTAssertEqual(item.testingTextView?.selectedRange(), NSRange(location: 8, length: 0))
    }

    @MainActor
    func testFocusEditorRefreshesMountedItemTextFromStoreBeforeRestoringTextSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Old")
        ]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "New text")
        ]))
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 3)
        )), notify: false)

        mounted.view.focusEditor()

        XCTAssertEqual(item.testingTextView?.string, "New text")
        XCTAssertEqual(item.testingTextView?.selectedRange(), NSRange(location: 0, length: 3))
    }

    @MainActor
    func testFocusEditorUsesFirstStillValidBlockFromPartiallyStaleBlockSelection() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old"),
            BlockInputBlock(id: firstID, text: "First")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.blocks([staleID, secondID]), notify: false)
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]))

        view.focusEditor()

        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 6)))
    }

    @MainActor
    func testBeginEditingDoesNotPublishSelectionForBlockMissingFromStore() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "Replacement")
        ]))
        view.applySelection(nil, notify: false)

        view.blockItemDidBeginEditing(item, blockID: staleID)

        XCTAssertNil(view.selection)
    }

    @MainActor
    func testSelectionChangeDoesNotPublishSelectionForBlockMissingFromStore() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "Replacement")
        ]))
        view.applySelection(nil, notify: false)

        view.blockItem(item, didChangeSelectionIn: staleID, selectedRange: nil)

        XCTAssertNil(view.selection)
    }

    @MainActor
    func testReturnDoesNotInsertForBlockMissingFromStore() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "Replacement")
        ]))
        view.applySelection(nil, notify: false)

        _ = item.requestReturn()

        XCTAssertEqual(store.document.blocks.map(\.id), [replacementID])
        XCTAssertNil(view.selection)
    }

    @MainActor
    func testSelectAllDoesNotPublishSelectionForBlockMissingFromStore() {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "Replacement")
        ]))
        view.applySelection(nil, notify: false)

        item.requestSelectAll()

        XCTAssertNil(view.selection)
    }

    @MainActor
    func testSelectAllRefreshesMountedItemBeforeSelectingCurrentBlockText() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Old")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Replacement")
        ]))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)

        item.requestSelectAll()

        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertEqual(view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 11)
        )))
        XCTAssertEqual(textView.string, "Replacement")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 11))
    }

}
