import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputStoreCompletionTests: XCTestCase {
    @MainActor
    func testCompletionSuggestionsValidateBlockThroughConfiguredStore() async {
        let blockID = BlockInputBlockID(rawValue: "first")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "@al")
        ]))
        let provider = StoreBackedCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            completionProvider: provider
        ))
        store.resetCounts()

        _ = await view.completionSuggestions(trigger: .mention, query: "al", blockID: blockID)

        XCTAssertEqual(store.indexReadIDs, [blockID])
    }

    @MainActor
    func testCompletionSuggestionsDoNotFallBackToStaleViewSnapshotWhenStoreMisses() async {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "@old")
        ]))
        let provider = StoreBackedCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            completionProvider: provider
        ))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "@new")
        ]))
        store.resetCounts()

        let suggestions = await view.completionSuggestions(trigger: .mention, query: "old", blockID: staleID)

        XCTAssertTrue(suggestions.isEmpty)
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(store.indexReadIDs, [staleID])
    }

    @MainActor
    func testCompletionSuggestionsFallBackToFirstStoreBlockWhenSelectionWasRemoved() async {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "@old")
        ]))
        let provider = StoreBackedCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            completionProvider: provider
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: staleID, utf16Offset: 0)), notify: false)
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "@new")
        ]))

        _ = await view.completionSuggestions(trigger: .mention, query: "new")

        XCTAssertEqual(provider.lastContext?.blockID, replacementID)
    }

    @MainActor
    func testCompletionSuggestionsUseFirstStillValidBlockFromPartiallyStaleBlockSelection() async {
        let staleID = BlockInputBlockID(rawValue: "stale")
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: staleID, text: "@old"),
            BlockInputBlock(id: firstID, text: "@first")
        ]))
        let provider = StoreBackedCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            completionProvider: provider
        ))
        view.applySelection(.blocks([staleID, secondID]), notify: false)
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "@first"),
            BlockInputBlock(id: secondID, text: "@second")
        ]))

        _ = await view.completionSuggestions(trigger: .mention, query: "second")

        XCTAssertEqual(provider.lastContext?.blockID, secondID)
    }

    @MainActor
    func testCompletionSuggestionsRefreshFromStoreBeforeBuildingContext() async {
        let blockID = BlockInputBlockID(rawValue: "first")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "@old")
        ]))
        let provider = StoreBackedCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            completionProvider: provider
        ))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "@new")
        ]))

        _ = await view.completionSuggestions(trigger: .mention, query: "new", blockID: blockID)

        XCTAssertEqual(provider.lastContext?.document.blocks.map(\.text), ["@new"])
    }

    @MainActor
    func testAcceptCompletionSuggestionUsesCurrentStoreBlockBeforeMutating() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Old @al")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "New @al")
        ]))
        store.resetCounts()

        let selection = view.acceptCompletionSuggestion(
            BlockInputCompletionSuggestion(
                id: "mention:alice",
                title: "Alice",
                insertionText: "@alice",
                trigger: .mention
            ),
            in: blockID,
            replacing: NSRange(location: 4, length: 3)
        )

        XCTAssertEqual(store.document.blocks.map(\.text), ["New @alice"])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [blockID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 10)))
    }

    @MainActor
    func testAcceptCompletionSuggestionUsesFirstStillValidBlockFromPartiallyStaleBlockSelection() {
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
            BlockInputBlock(id: secondID, text: "Second @al")
        ]))
        store.resetCounts()

        let selection = view.acceptCompletionSuggestion(BlockInputCompletionSuggestion(
            id: "mention:alice",
            title: "Alice",
            insertionText: "@alice",
            trigger: .mention
        ))

        XCTAssertEqual(store.document.blocks.map(\.text), ["First", "Second @al@alice"])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [secondID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 16)))
    }
}
