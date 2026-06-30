import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputViewProgressiveStoreTests: XCTestCase {
    @MainActor
    func testCollectionDataSourceExposesOnlyLoadedProgressiveBlocksAndLoadingRow() {
        let blocks = (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 1_000)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(documentStore: store))

        let itemCount = view.collectionView(view.collectionView, numberOfItemsInSection: 0)
        let loadingRowSize = view.collectionView(
            view.collectionView,
            layout: view.collectionView.collectionViewLayout ?? NSCollectionViewFlowLayout(),
            sizeForItemAt: IndexPath(item: 1_000, section: 0)
        )

        XCTAssertEqual(store.loadedBlockCount, 1_000)
        XCTAssertEqual(store.totalBlockCount, 100_000)
        XCTAssertEqual(itemCount, 1_001)
        XCTAssertEqual(loadingRowSize.height, 56)
    }

    @MainActor
    func testHundredThousandBlockProgressiveLoadsRemainContiguous() async throws {
        let blocks = (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 1_000)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(documentStore: store))

        try assertLoadedPrefixMatchesSource(blocks, store: store, view: view)
        while !store.isComplete {
            try await store.loadNextBlockBatch(limit: 5_000)
            try assertLoadedPrefixMatchesSource(blocks, store: store, view: view)
        }

        XCTAssertEqual(store.loadedBlockCount, 100_000)
        XCTAssertEqual(view.collectionView(view.collectionView, numberOfItemsInSection: 0), 100_000)
    }

    @MainActor
    func testProgressiveEmptySourceStillExposesEditableEmptyBlock() {
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [], initialLimit: 1)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(documentStore: store))

        XCTAssertEqual(store.loadedBlockCount, 1)
        XCTAssertEqual(view.collectionView(view.collectionView, numberOfItemsInSection: 0), 1)
        XCTAssertEqual(view.collectionView.numberOfItems(inSection: 0), 1)
        XCTAssertEqual(view.document.blocks.count, 1)
    }

    @MainActor
    func testProgressiveLoadingRowAppendsNextBatchWhenRequested() async throws {
        let blocks = (0..<7).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 1)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.progressiveLoadBatchLimit = 2
        view.configure(BlockInputConfiguration(documentStore: store))
        let appended = expectation(description: "Progressive batch appended")
        let observation = store.observeChanges { change in
            if case .appendedBlocks = change {
                appended.fulfill()
            }
        }

        _ = view.collectionView(
            view.collectionView,
            itemForRepresentedObjectAt: IndexPath(item: 1, section: 0)
        )
        await fulfillment(of: [appended], timeout: 1)
        while view.progressiveLoadTask != nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(store.isComplete)
        XCTAssertEqual(store.loadedBlockCount, 3)
        XCTAssertEqual(view.collectionView(view.collectionView, numberOfItemsInSection: 0), 4)
        observation.cancel()
    }

    @MainActor
    func testVisibleProgressiveLoadingRowRequestsNextBatchAfterPreviousTaskCompletes() async throws {
        let blocks = (0..<4).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 1)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.progressiveLoadBatchLimit = 1
        let completed = expectation(description: "Visible progressive loading row continues loading")
        completed.assertForOverFulfill = true
        let observation = store.observeChanges { change in
            if case .appendedBlocks(let batch) = change,
               batch.isComplete {
                completed.fulfill()
            }
        }
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.configure(BlockInputConfiguration(documentStore: store))

        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()

        await fulfillment(of: [completed], timeout: 1)
        while view.progressiveLoadTask != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.isComplete)
        XCTAssertEqual(store.loadedBlockCount, 4)
        XCTAssertEqual(view.collectionView(view.collectionView, numberOfItemsInSection: 0), 4)
        observation.cancel()
    }

    @MainActor
    func testVisibleProgressiveLoadingRowDoesNotRetryWhenLoadMakesNoProgress() async throws {
        let store = NoProgressProgressiveStore()
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        let loaded = expectation(description: "Progressive load requested")
        store.onLoad = {
            loaded.fulfill()
        }
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.configure(BlockInputConfiguration(documentStore: store))

        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()

        await fulfillment(of: [loaded], timeout: 1)
        while view.progressiveLoadTask != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.loadCount, 1)
        XCTAssertFalse(store.isComplete)
        XCTAssertEqual(view.collectionView(view.collectionView, numberOfItemsInSection: 0), 2)
    }

    @MainActor
    func testProgressiveLoadingUsesFiveThousandBlockBatchesByDefault() async {
        let store = RecordingProgressiveLimitStore()
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(documentStore: store))
        let loaded = expectation(description: "Progressive batch requested")
        store.onLoad = {
            loaded.fulfill()
        }

        _ = view.collectionView(
            view.collectionView,
            itemForRepresentedObjectAt: IndexPath(item: 1, section: 0)
        )
        await fulfillment(of: [loaded], timeout: 1)

        XCTAssertEqual(store.requestedLimits, [5_000])
    }

    @MainActor
    func testProgressiveLoadTaskIgnoresFailureAfterStoreReconfigure() async {
        let oldStore = DelayedFailingProgressiveStore()
        let newID = BlockInputBlockID(rawValue: "new")
        let newStore = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: newID, text: "New")
        ]))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        let loadStarted = expectation(description: "Old progressive load started")
        oldStore.onLoadStarted = {
            loadStarted.fulfill()
        }
        view.configure(BlockInputConfiguration(documentStore: oldStore))

        view.requestNextProgressiveBatchIfNeeded()
        await fulfillment(of: [loadStarted], timeout: 1)
        view.configure(BlockInputConfiguration(documentStore: newStore))

        oldStore.resumeLoad()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(view.progressiveStoreError)
        XCTAssertNil(view.progressiveLoadTask)
        XCTAssertEqual(view.document.blocks.map(\.id), [newID])
    }

    @MainActor
    func testStaleProgressiveStoreObservationIsIgnoredAfterReconfigure() {
        let oldStore = DelayedFailingProgressiveStore()
        let newID = BlockInputBlockID(rawValue: "new")
        let newStore = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: newID, text: "New")
        ]))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(documentStore: oldStore))
        oldStore.captureObservers()

        view.configure(BlockInputConfiguration(documentStore: newStore))
        oldStore.emitCapturedFailure()

        XCTAssertNil(view.progressiveStoreError)
        XCTAssertEqual(view.document.blocks.map(\.id), [newID])
    }

    @MainActor
    func testExternalCompleteSnapshotMaterializationDoesNotAppendBatchesThroughEditorObservation() async throws {
        let blocks = (0..<7).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 1)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(documentStore: store))

        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertEqual(snapshot.blocks.map(\.id), blocks.map(\.id))
        XCTAssertEqual(store.loadedBlockCount, 1)
        XCTAssertEqual(view.document.blocks.map(\.id), [blocks[0].id])
        XCTAssertEqual(view.collectionView(view.collectionView, numberOfItemsInSection: 0), 2)
        XCTAssertEqual(view.collectionView.numberOfItems(inSection: 0), 2)
    }

    @MainActor
    func testLargeProgressiveAppendMarksDocumentCacheUnsynchronized() async throws {
        let blocks = (0..<10_001).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: "Block \(index)"
            )
        }
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 2)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(documentStore: store))

        try await store.loadNextBlockBatch(limit: largeDocumentCacheMutationLimit)

        XCTAssertEqual(store.loadedBlockCount, 10_001)
        XCTAssertFalse(view.isDocumentCacheSynchronized)
        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertFalse(view.canSynchronizeCacheForGranularInsertion(insertedBlockCount: 1))
    }

    @MainActor
    func testFullDocumentStructuralEditDoesNotReplaceIncompleteProgressiveStoreWithLoadedPrefix() async throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [
            BlockInputBlock(id: firstID, text: ""),
            BlockInputBlock(id: secondID, text: "Second")
        ], initialLimit: 1)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(documentStore: store))

        let selection = view.insertMarkdown("Inserted")
        let snapshot = try await store.completeDocumentSnapshot(limit: 10)

        XCTAssertNil(selection)
        XCTAssertEqual(snapshot.blocks.map(\.id), [firstID, secondID])
        XCTAssertEqual(snapshot.blocks.map(\.text), ["", "Second"])
    }

    @MainActor
    private func assertLoadedPrefixMatchesSource(
        _ blocks: [BlockInputBlock],
        store: BlockInputProgressiveMemoryDocumentStore,
        view: BlockInputView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let loadedCount = store.loadedBlockCount
        let expectedItemCount = loadedCount + (store.isComplete ? 0 : 1)
        let itemCount = view.collectionView(view.collectionView, numberOfItemsInSection: 0)
        XCTAssertEqual(itemCount, expectedItemCount, file: file, line: line)
        for index in 0..<loadedCount {
            let expectedBlock = blocks[index]
            let loadedBlock = try XCTUnwrap(store.block(at: index), "Missing store block at index \(index)", file: file, line: line)
            let viewBlock = try XCTUnwrap(view.block(at: index), "Missing view block at index \(index)", file: file, line: line)
            let viewIndex = view.index(of: expectedBlock.id)
            XCTAssertEqual(loadedBlock.id, expectedBlock.id, file: file, line: line)
            XCTAssertEqual(viewBlock.id, expectedBlock.id, file: file, line: line)
            XCTAssertEqual(store.index(of: expectedBlock.id), index, file: file, line: line)
            XCTAssertEqual(viewIndex, index, file: file, line: line)
        }
        let unloadedViewBlock = view.block(at: loadedCount)
        XCTAssertNil(store.block(at: loadedCount), "Loaded prefix should stop at \(loadedCount)", file: file, line: line)
        XCTAssertNil(unloadedViewBlock, "View prefix should stop at \(loadedCount)", file: file, line: line)
    }
}

private enum DelayedProgressiveStoreError: Error {
    case failed
}

private final class NoProgressProgressiveStore: BlockInputDocumentStore {
    var onLoad: (() -> Void)?
    private(set) var loadCount = 0
    private let block = BlockInputBlock(id: "initial", text: "Initial")

    var loadedBlockCount: Int {
        1
    }

    var isComplete: Bool {
        false
    }

    @MainActor
    func loadNextBlockBatch(limit: Int) async throws {
        loadCount += 1
        onLoad?()
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

    func replaceDocument(_ document: BlockInputDocument) {}
}

private final class RecordingProgressiveLimitStore: BlockInputDocumentStore, @unchecked Sendable {
    var onLoad: (() -> Void)?
    private(set) var requestedLimits: [Int] = []
    private var blocks = [
        BlockInputBlock(id: BlockInputBlockID(rawValue: "initial"), text: "Initial")
    ]
    private var observers: [UUID: @MainActor (BlockInputDocumentStoreChange) -> Void] = [:]
    private var complete = false

    var loadedBlockCount: Int {
        blocks.count
    }

    var isComplete: Bool {
        complete
    }

    @MainActor
    func loadNextBlockBatch(limit: Int) async throws {
        requestedLimits.append(limit)
        let block = BlockInputBlock(id: BlockInputBlockID(rawValue: "loaded"), text: "Loaded")
        blocks.append(block)
        complete = true
        observers.values.forEach {
            $0(.appendedBlocks(BlockInputDocumentStoreBatch(startIndex: 1, blocks: [block], isComplete: true)))
        }
        onLoad?()
    }

    func observeChanges(_ observer: @escaping @MainActor (BlockInputDocumentStoreChange) -> Void) -> BlockInputDocumentStoreObservation {
        let id = UUID()
        observers[id] = observer
        return BlockInputDocumentStoreObservation { [weak self] in
            self?.observers[id] = nil
        }
    }

    func block(at index: Int) -> BlockInputBlock? {
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

    func replaceDocument(_ document: BlockInputDocument) {}
}

private final class DelayedFailingProgressiveStore: BlockInputDocumentStore, @unchecked Sendable {
    var onLoadStarted: (() -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    private let block = BlockInputBlock(id: "old", text: "Old")
    private var observers: [UUID: @MainActor (BlockInputDocumentStoreChange) -> Void] = [:]
    private var capturedObservers: [@MainActor (BlockInputDocumentStoreChange) -> Void] = []

    var loadedBlockCount: Int {
        1
    }

    var isComplete: Bool {
        false
    }

    var isLoading: Bool {
        continuation != nil
    }

    @MainActor
    func loadNextBlockBatch(limit: Int) async throws {
        onLoadStarted?()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        throw DelayedProgressiveStoreError.failed
    }

    func observeChanges(_ observer: @escaping @MainActor (BlockInputDocumentStoreChange) -> Void) -> BlockInputDocumentStoreObservation {
        let id = UUID()
        observers[id] = observer
        return BlockInputDocumentStoreObservation { [weak self] in
            self?.observers[id] = nil
        }
    }

    func captureObservers() {
        capturedObservers = Array(observers.values)
    }

    @MainActor
    func emitCapturedFailure() {
        capturedObservers.forEach { $0(.failed("Old failed")) }
    }

    func resumeLoad() {
        continuation?.resume()
        continuation = nil
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

    func replaceDocument(_ document: BlockInputDocument) {}
}
