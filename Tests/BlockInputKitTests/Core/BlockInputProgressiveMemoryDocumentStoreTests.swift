import Foundation
import XCTest
@testable import BlockInputKit

final class ProgressiveMemoryDocumentStoreTests: XCTestCase {
    @MainActor
    func testProgressiveMemoryStoreNormalizesEmptySourceToEmptyParagraph() async throws {
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [], initialLimit: 1)
        let snapshot = try await store.completeDocumentSnapshot(limit: 10)

        XCTAssertEqual(store.loadedBlockCount, 1)
        XCTAssertEqual(store.totalBlockCount, 1)
        XCTAssertTrue(store.isComplete)
        XCTAssertEqual(snapshot.blocks.count, 1)
        XCTAssertEqual(snapshot.blocks[0].kind, .paragraph)
        XCTAssertEqual(snapshot.blocks[0].text, "")
    }

    @MainActor
    func testCompleteSnapshotPreservesFrontMatterKindAndRawBody() async throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo\n  nested: true\n")
        let body = BlockInputBlock(id: "body", text: "Body")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [front, body], initialLimit: 1)

        let snapshot = try await store.completeDocumentSnapshot(limit: 10)

        XCTAssertEqual(snapshot.blocks, [front, body])
    }

    @MainActor
    func testProgressiveMemoryStoreKeepsFrontMatterPinnedDuringMoves() async throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let body = BlockInputBlock(id: "body", text: "Body")
        let tail = BlockInputBlock(id: "tail", text: "Tail")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [front, body, tail], initialLimit: 3)

        store.moveBlock(withID: front.id, to: 1)
        store.moveBlock(withID: body.id, to: 0)
        let snapshot = try await store.completeDocumentSnapshot(limit: 10)

        XCTAssertEqual(snapshot.blocks, [front, body, tail])
        XCTAssertEqual(store.index(of: front.id), 0)
        XCTAssertEqual(store.index(of: body.id), 1)
    }

    @MainActor
    func testProgressiveMemoryStoreCanRepairNonLeadingFrontMatter() async throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let body = BlockInputBlock(id: "body", text: "Body")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [body, front], initialLimit: 2)

        store.moveBlock(withID: front.id, to: 0)
        let snapshot = try await store.completeDocumentSnapshot(limit: 10)

        XCTAssertEqual(snapshot.blocks, [front, body])
        XCTAssertEqual(store.index(of: front.id), 0)
        XCTAssertEqual(store.index(of: body.id), 1)
    }

    @MainActor
    func testProgressiveMemoryStoreDoesNotMoveDuplicateFrontMatterBeforeLeadingFrontMatter() async throws {
        let leading = BlockInputBlock(id: "leading", kind: .frontMatter, text: "title: Leading")
        let body = BlockInputBlock(id: "body", text: "Body")
        let duplicate = BlockInputBlock(id: "duplicate", kind: .frontMatter, text: "title: Duplicate")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [leading, body, duplicate], initialLimit: 3)

        store.moveBlock(withID: duplicate.id, to: 0)
        let snapshot = try await store.completeDocumentSnapshot(limit: 10)

        XCTAssertEqual(snapshot.blocks, [leading, body, duplicate])
        XCTAssertEqual(store.index(of: leading.id), 0)
        XCTAssertEqual(store.index(of: duplicate.id), 2)
    }

    @MainActor
    func testProgressiveMemoryStoreInsertionAtStartKeepsLeadingFrontMatterPinned() async throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let inserted = BlockInputBlock(id: "inserted", text: "Inserted")
        let body = BlockInputBlock(id: "body", text: "Body")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [front, body], initialLimit: 2)

        store.insertBlocks([inserted], at: 0)
        let snapshot = try await store.completeDocumentSnapshot(limit: 10)

        XCTAssertEqual(snapshot.blocks, [front, inserted, body])
        XCTAssertEqual(store.index(of: front.id), 0)
        XCTAssertEqual(store.index(of: inserted.id), 1)
    }

    @MainActor
    func testProgressiveMemoryStoreLoadsBatchesAndEmitsUpdates() async throws {
        let blocks = (0..<5).map { index in
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\(index)"), text: "Block \(index)")
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 2)
        var changes: [BlockInputDocumentStoreChange] = []
        let observation = store.observeChanges { change in
            changes.append(change)
        }

        XCTAssertEqual(store.loadedBlockCount, 2)
        XCTAssertEqual(store.totalBlockCount, 5)
        XCTAssertFalse(store.isComplete)
        XCTAssertEqual(store.block(at: 1)?.text, "Block 1")
        XCTAssertNil(store.block(at: 2))

        try await store.loadNextBlockBatch(limit: 2)

        XCTAssertEqual(store.loadedBlockCount, 4)
        XCTAssertEqual(store.index(of: "block-3"), 3)
        guard case .appendedBlocks(let batch) = changes.first(where: {
            if case .appendedBlocks = $0 { return true }
            return false
        }) else {
            XCTFail("Expected appended batch change")
            observation.cancel()
            return
        }
        XCTAssertEqual(batch.startIndex, 2)
        XCTAssertEqual(batch.blocks.map(\.text), ["Block 2", "Block 3"])
        XCTAssertFalse(batch.isComplete)

        observation.cancel()
    }

    @MainActor
    func testProgressiveMemoryStoreCancelledObservationStopsBatchUpdates() async throws {
        let blocks = (0..<5).map { index in
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\(index)"), text: "Block \(index)")
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 1)
        var changeCount = 0
        let observation = store.observeChanges { _ in
            changeCount += 1
        }

        observation.cancel()
        try await store.loadNextBlockBatch(limit: 2)

        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(store.loadedBlockCount, 3)
    }

    @MainActor
    func testProgressiveMemoryStoreCompleteSnapshotDoesNotPublishOrAppendRemainingChunks() async throws {
        let blocks = (0..<5).map { index in
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\(index)"), text: "Block \(index)")
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 1)
        var appendedStarts: [Int] = []
        let observation = store.observeChanges { change in
            if case .appendedBlocks(let batch) = change {
                appendedStarts.append(batch.startIndex)
            }
        }

        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertEqual(snapshot.blocks.map(\.text), blocks.map(\.text))
        XCTAssertEqual(appendedStarts, [])
        XCTAssertEqual(store.loadedBlockCount, 1)
        XCTAssertFalse(store.isComplete)
        observation.cancel()
    }

    @MainActor
    func testProgressiveMemoryStoreLoadAllRemainingBlocksAppendsBatches() async throws {
        let blocks = (0..<5).map { index in
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\(index)"), text: "Block \(index)")
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 1)
        var appendedStarts: [Int] = []
        let observation = store.observeChanges { change in
            if case .appendedBlocks(let batch) = change {
                appendedStarts.append(batch.startIndex)
            }
        }

        try await store.loadAllRemainingBlocks(limit: 2)

        XCTAssertEqual(appendedStarts, [1, 3])
        XCTAssertEqual(store.loadedBlockCount, 5)
        XCTAssertTrue(store.isComplete)
        observation.cancel()
    }

    @MainActor
    func testProgressiveMemoryStoreCancellationDoesNotEmitFailure() async throws {
        let blocks = (0..<5).map { index in
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\(index)"), text: "Block \(index)")
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 1)
        var changes: [BlockInputDocumentStoreChange] = []
        let observation = store.observeChanges { change in
            changes.append(change)
        }
        let loadTask = Task { @MainActor in
            try await store.loadNextBlockBatch(limit: 2)
        }

        loadTask.cancel()
        do {
            try await loadTask.value
            XCTFail("Expected cancelled progressive load to throw")
        } catch is CancellationError {
        }

        XCTAssertFalse(changes.contains {
            if case .failed = $0 {
                return true
            }
            return false
        })
        XCTAssertEqual(store.loadedBlockCount, 1)
        XCTAssertFalse(store.isLoading)
        observation.cancel()
    }

    @MainActor
    func testProgressiveMemoryStoreCompleteSnapshotCombinesLoadedEditsWithUnloadedSource() async throws {
        let blocks = (0..<6).map { index in
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\(index)"), text: "Block \(index)")
        }
        let inserted = BlockInputBlock(id: BlockInputBlockID(rawValue: "inserted"), text: "Inserted")
        let edited = BlockInputBlock(id: blocks[1].id, text: "Edited 1")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 3)

        store.replaceBlock(edited)
        store.insertBlocks([inserted], at: 1)
        store.moveBlock(withID: blocks[2].id, to: 0)
        store.deleteBlocks(withIDs: [blocks[0].id])
        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertEqual(store.loadedBlockCount, 3)
        XCTAssertFalse(store.isComplete)
        XCTAssertEqual(snapshot.blocks.map(\.text), [
            "Block 2",
            "Inserted",
            "Edited 1",
            "Block 3",
            "Block 4",
            "Block 5"
        ])
    }

    @MainActor
    func testProgressiveMemoryStoreKeepsTotalCountCurrentAfterCompleteMutations() async throws {
        let blocks = (0..<3).map { index in
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\(index)"), text: "Block \(index)")
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 1)
        try await store.loadAllRemainingBlocks(limit: 10)

        store.insertBlocks([
            BlockInputBlock(id: "inserted-0", text: "Inserted 0"),
            BlockInputBlock(id: "inserted-1", text: "Inserted 1")
        ], at: 1)
        store.deleteBlocks(withIDs: [blocks[0].id])

        let snapshot = try await store.completeDocumentSnapshot(limit: 10)
        XCTAssertEqual(store.loadedBlockCount, 4)
        XCTAssertEqual(store.totalBlockCount, 4)
        XCTAssertEqual(snapshot.blocks.map(\.text), [
            "Inserted 0",
            "Inserted 1",
            "Block 1",
            "Block 2"
        ])
    }

    @MainActor
    func testProgressiveMemoryStoreDeletesUnloadedSourceBlocksBeforeCompletion() async throws {
        let blocks = (0..<5).map { index in
            BlockInputBlock(id: BlockInputBlockID(rawValue: "block-\(index)"), text: "Block \(index)")
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 2)

        store.deleteBlocks(withIDs: [blocks[3].id])
        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertEqual(store.loadedBlockCount, 2)
        XCTAssertEqual(store.totalBlockCount, 4)
        XCTAssertEqual(snapshot.blocks.map(\.text), [
            "Block 0",
            "Block 1",
            "Block 2",
            "Block 4"
        ])
    }

    @MainActor
    func testDefaultProgressiveLoaderThrowsWhenBatchMakesNoProgress() async throws {
        let store = StalledProgressiveDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "First")
        ]))

        do {
            _ = try await store.completeDocumentSnapshot(limit: 10)
            XCTFail("Expected stalled progressive load to throw")
        } catch let error as BlockInputDocumentStoreError {
            XCTAssertEqual(error, .progressiveLoadMadeNoProgress)
        }
    }

    func testDefaultGranularMutationsDoNotReplaceIncompleteProgressiveStoreWithLoadedPrefix() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let fallbackStore = StalledProgressiveDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First")
        ]))

        fallbackStore.replaceBlock(BlockInputBlock(id: firstID, text: "Updated"))
        fallbackStore.insertBlocks([BlockInputBlock(id: secondID, text: "Second")], at: 1)
        fallbackStore.moveBlock(withID: firstID, to: 1)
        fallbackStore.deleteBlocks(withIDs: [firstID])

        XCTAssertEqual(fallbackStore.document.blocks.map(\.id), [firstID])
        XCTAssertEqual(fallbackStore.document.blocks.map(\.text), ["First"])
        XCTAssertEqual(fallbackStore.replaceDocumentCount, 0)
    }
}

private final class StalledProgressiveDocumentStore: BlockInputDocumentStore {
    private(set) var document: BlockInputDocument
    private(set) var replaceDocumentCount = 0

    init(document: BlockInputDocument) {
        self.document = document
    }

    var loadedBlockCount: Int {
        document.blocks.count
    }

    var isComplete: Bool {
        false
    }

    func block(at index: Int) -> BlockInputBlock? {
        guard document.blocks.indices.contains(index) else {
            return nil
        }
        return document.blocks[index]
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        document.block(withID: id)
    }

    func index(of id: BlockInputBlockID) -> Int? {
        document.index(of: id)
    }

    func replaceDocument(_ document: BlockInputDocument) {
        replaceDocumentCount += 1
        self.document = document
    }
}
