import Foundation
import Darwin
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputLiveCompletionTests: XCTestCase {
    func testLiveCompletionSuggestionsDoNotRefreshSynchronizedStoreBeforeProviderContext() async {
        let blocks = (0..<20).map { index in
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\(index)"), text: "@al")
        }
        let store = ReadCountingLiveCompletionStore(blocks: blocks)
        let provider = CapturingLiveCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            completionProvider: provider
        ))
        store.resetReadCounts()

        _ = await view.completionSuggestions(
            trigger: .mention,
            query: "al",
            blockID: BlockInputBlockID(rawValue: "block-10"),
            refreshesDocumentFromStore: false
        )

        XCTAssertEqual(store.blockAtReadCount, 0)
        XCTAssertEqual(provider.lastContext?.document.blocks, blocks)
    }

    func testLiveCompletionSuggestionsDoNotRefreshUnsynchronizedStoreBeforeProviderContext() async {
        let blocks = (0..<20).map { index in
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\(index)"), text: "@al")
        }
        let store = ReadCountingLiveCompletionStore(blocks: blocks)
        let provider = CapturingLiveCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            completionProvider: provider
        ))
        view.markDocumentCacheUnsynchronized()
        store.resetReadCounts()

        _ = await view.completionSuggestions(
            trigger: .mention,
            query: "al",
            blockID: BlockInputBlockID(rawValue: "block-10"),
            refreshesDocumentFromStore: false
        )

        XCTAssertEqual(store.blockAtReadCount, 0)
        XCTAssertEqual(provider.lastContext?.document.blocks, blocks)
    }

    func testHeadlessCompletionSuggestionsRequestProviderOffMainThread() async {
        let provider = ThreadCapturingLiveCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "@al")
            ]),
            completionProvider: provider
        ))

        _ = await view.completionSuggestions(trigger: .mention, query: "al", blockID: "block")

        XCTAssertEqual(provider.requestRanOnMainThread, false)
    }
}

private final class CapturingLiveCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private(set) var lastContext: BlockInputCompletionContext?

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        lastContext = context
        return []
    }
}

private final class ThreadCapturingLiveCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private(set) var requestRanOnMainThread: Bool?

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        requestRanOnMainThread = pthread_main_np() == 1
        return []
    }
}

private final class ReadCountingLiveCompletionStore: BlockInputDocumentStore {
    private var blocks: [BlockInputBlock]
    private(set) var blockAtReadCount = 0

    var loadedBlockCount: Int {
        blocks.count
    }

    init(blocks: [BlockInputBlock]) {
        self.blocks = blocks
    }

    func resetReadCounts() {
        blockAtReadCount = 0
    }

    func block(at index: Int) -> BlockInputBlock? {
        blockAtReadCount += 1
        guard blocks.indices.contains(index) else {
            return nil
        }
        return blocks[index]
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        blocks.first { $0.id == id }
    }

    func index(of id: BlockInputBlockID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    func replaceDocument(_ document: BlockInputDocument) {
        blocks = document.blocks
    }
}
