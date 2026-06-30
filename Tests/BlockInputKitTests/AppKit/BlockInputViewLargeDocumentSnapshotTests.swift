import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewLargeDocumentSnapshotTests: XCTestCase {
    func testLargeDocumentChangeSnapshotIsDeferredToCompleteSnapshotStore() async {
        let targetIndex = 50_000
        let (blockID, document) = largeListDocument(targetIndex: targetIndex)
        let store = CompleteSnapshotCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        let snapshotPublished = expectation(description: "Deferred snapshot published")
        var publishedDocument: BlockInputDocument?
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: { document in
                publishedDocument = document
                snapshotPublished.fulfill()
            },
            documentChangeSnapshotDelay: 0.01
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertNil(publishedDocument)
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.completeSnapshotCount, 0)

        await fulfillment(of: [snapshotPublished], timeout: 1)
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.completeSnapshotCount, 1)
        XCTAssertEqual(publishedDocument?.blocks.count, 100_001)
    }

    func testLargeDocumentChangeSnapshotsAreCoalesced() async {
        let (_, document) = largeListDocument(targetIndex: 50_000)
        let store = CompleteSnapshotCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        let snapshotPublished = expectation(description: "Deferred snapshot published once")
        snapshotPublished.assertForOverFulfill = true
        var publishCount = 0
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: { _ in
                publishCount += 1
                snapshotPublished.fulfill()
            },
            documentChangeSnapshotDelay: 0.01
        ))
        store.resetCounts()

        view.publishDocumentChange()
        view.publishDocumentChange()

        await fulfillment(of: [snapshotPublished], timeout: 1)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(publishCount, 1)
        XCTAssertEqual(store.completeSnapshotCount, 1)
    }

    func testIncompleteProgressiveStorePublishesCompleteSnapshotWithoutAppendingRows() async {
        let blocks = (0..<20).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 2)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        let snapshotPublished = expectation(description: "Complete snapshot published")
        var publishedCounts: [Int] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: {
                publishedCounts.append($0.blocks.count)
                snapshotPublished.fulfill()
            },
            documentChangeSnapshotDelay: 0.01
        ))

        view.publishDocumentChange()

        XCTAssertNotNil(view.pendingDocumentSnapshotWorkItem)
        await fulfillment(of: [snapshotPublished], timeout: 1)
        XCTAssertEqual(publishedCounts, [20])
        XCTAssertEqual(store.loadedBlockCount, 2)
        XCTAssertFalse(store.isComplete)
        XCTAssertEqual(view.collectionView(view.collectionView, numberOfItemsInSection: 0), 3)
    }

    func testDeferredProgressiveSnapshotUsesCompleteSnapshotWithoutCompletingStore() async throws {
        let blocks = (0..<5).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 2)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        let snapshotPublished = expectation(description: "Deferred snapshot published from complete snapshot")
        var publishedCounts: [Int] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: { document in
                publishedCounts.append(document.blocks.count)
                snapshotPublished.fulfill()
            },
            documentChangeSnapshotDelay: 0.01
        ))

        view.publishDocumentChange()

        await fulfillment(of: [snapshotPublished], timeout: 1)
        XCTAssertEqual(publishedCounts, [5])
        XCTAssertFalse(store.isComplete)
        XCTAssertEqual(store.loadedBlockCount, 2)
        XCTAssertNil(view.pendingDocumentSnapshotWorkItem)
    }

    func testFailedDeferredCompleteSnapshotClearsPendingWorkItem() async {
        let store = FailingCompleteSnapshotStore()
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        let snapshotRequested = expectation(description: "Deferred complete snapshot requested")
        store.onCompleteSnapshot = {
            snapshotRequested.fulfill()
        }
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: { _ in XCTFail("Failing snapshots should not publish document changes") },
            documentChangeSnapshotDelay: 0.01
        ))

        view.publishDocumentChange()

        await fulfillment(of: [snapshotRequested], timeout: 1)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(view.pendingDocumentSnapshotWorkItem)
    }

    func testSameStoreReconfigureKeepsDeferredProgressiveSnapshotPending() async throws {
        let blocks = (0..<5).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 2)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        let snapshotPublished = expectation(description: "Deferred snapshot survives same-store reconfigure")
        var publishedCounts: [Int] = []
        let configuration = BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: { document in
                publishedCounts.append(document.blocks.count)
                snapshotPublished.fulfill()
            },
            documentChangeSnapshotDelay: 0.01
        )
        view.configure(configuration)

        view.publishDocumentChange()
        view.configure(configuration)

        XCTAssertNotNil(view.pendingDocumentSnapshotWorkItem)

        await fulfillment(of: [snapshotPublished], timeout: 1)
        XCTAssertEqual(publishedCounts, [5])
        XCTAssertNil(view.pendingDocumentSnapshotWorkItem)
    }

    func testReplacingIncompleteProgressiveStoreDoesNotPublishDuplicateDeferredSnapshot() async throws {
        let blocks = (0..<5).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 2)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        let snapshotPublished = expectation(description: "Deferred snapshot publishes once after store replacement")
        snapshotPublished.assertForOverFulfill = true
        var publishedCounts: [Int] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: { document in
                publishedCounts.append(document.blocks.count)
                snapshotPublished.fulfill()
            },
            documentChangeSnapshotDelay: 0.01
        ))

        view.publishDocumentChange()
        XCTAssertNotNil(view.pendingDocumentSnapshotWorkItem)
        store.replaceDocument(BlockInputDocument(blocks: blocks))

        await fulfillment(of: [snapshotPublished], timeout: 1)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(publishedCounts, [5])
        XCTAssertNil(view.pendingDocumentSnapshotWorkItem)
    }

    func testCompletedSmallProgressiveStorePublishesCompleteLoadedSnapshot() async throws {
        let blocks = (0..<5).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 2)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        var publishedCounts: [Int] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: { document in
                publishedCounts.append(document.blocks.count)
            },
            documentChangeSnapshotDelay: 0.01
        ))

        try await store.loadAllRemainingBlocks(limit: 2)
        view.publishDocumentChange()

        XCTAssertEqual(view.document.blocks.map(\.id), blocks.map(\.id))
        XCTAssertEqual(publishedCounts, [5])
    }

    func testReconfigureCancelsDeferredDocumentChangeSnapshot() async {
        let (_, document) = largeListDocument(targetIndex: 50_000)
        let store = CompleteSnapshotCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        var stalePublishCount = 0
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: { _ in stalePublishCount += 1 },
            documentChangeSnapshotDelay: 0.05
        ))

        view.publishDocumentChange()
        XCTAssertNotNil(view.pendingDocumentSnapshotWorkItem)
        view.configure(BlockInputConfiguration(documentStore: store))

        XCTAssertNil(view.pendingDocumentSnapshotWorkItem)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(stalePublishCount, 0)
        XCTAssertEqual(store.completeSnapshotCount, 0)
    }

    func testDroppingBelowLargeDocumentLimitPublishesFreshSnapshotOnce() async throws {
        let firstDeletedID = BlockInputBlockID(rawValue: "block-10001")
        let secondDeletedID = BlockInputBlockID(rawValue: "block-10000")
        let document = BlockInputDocument(blocks: (0..<10_002).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: index >= 10_000 ? "" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        var publishedCounts: [Int] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: { publishedCounts.append($0.blocks.count) },
            documentChangeSnapshotDelay: 0.01
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: firstDeletedID, utf16Offset: 0)), notify: false)
        store.resetCounts()

        _ = view.deleteCurrentEmptyBlockForBackspaceOrDelete()
        XCTAssertNotNil(view.pendingDocumentSnapshotWorkItem)
        view.applySelection(.cursor(BlockInputCursor(blockID: secondDeletedID, utf16Offset: 0)), notify: false)
        _ = view.deleteCurrentEmptyBlockForBackspaceOrDelete()

        XCTAssertEqual(publishedCounts, [10_000])
        XCTAssertNil(view.pendingDocumentSnapshotWorkItem)
        XCTAssertEqual(store.documentReadCount, 0)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(publishedCounts, [10_000])
    }

    private func largeListDocument(targetIndex: Int) -> (BlockInputBlockID, BlockInputDocument) {
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                kind: index == targetIndex ? .bulletedListItem : .paragraph,
                text: index == targetIndex ? "List item" : "Block \(index)"
            )
        })
        return (blockID, document)
    }
}

private enum FailingCompleteSnapshotStoreError: Error {
    case failed
}

private final class FailingCompleteSnapshotStore: BlockInputDocumentStore {
    var onCompleteSnapshot: (() -> Void)?
    private let block = BlockInputBlock(id: "first", text: "First")

    var loadedBlockCount: Int {
        1
    }

    var isComplete: Bool {
        false
    }

    func block(at index: Int) -> BlockInputBlock? {
        index == 0 ? block : nil
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        id == block.id ? block : nil
    }

    func index(of id: BlockInputBlockID) -> Int? {
        id == block.id ? 0 : nil
    }

    @MainActor
    func completeDocumentSnapshot(limit: Int) async throws -> BlockInputDocument {
        onCompleteSnapshot?()
        throw FailingCompleteSnapshotStoreError.failed
    }

    func replaceDocument(_ document: BlockInputDocument) {}
}
