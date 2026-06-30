import BlockInputKit
import Foundation

/// Demo-only progressive store that synthesizes large documents on demand.
///
/// The store mutates its own loaded block array for benchmark realism, so
/// granular insert and move paths call BlockInputDocument's shared frontmatter
/// helpers instead of duplicating document-leading metadata policy.
final class DemoGeneratedDocumentStore: BlockInputDocumentStore, @unchecked Sendable {
    var loadedBlockCount: Int {
        locked { loadedBlocks.count }
    }

    var totalBlockCount: Int? {
        locked { totalCount }
    }

    var isComplete: Bool {
        locked { nextGeneratedIndex >= generatedCount }
    }

    var isLoading: Bool {
        locked { loading }
    }

    private let generatedCount: Int
    private let blockProvider: @Sendable (Int) -> BlockInputBlock
    private var totalCount: Int
    private var nextGeneratedIndex: Int
    private var loadedBlocks: [BlockInputBlock]
    private var indexesByID: [BlockInputBlockID: Int]
    private var observers: [UUID: @MainActor (BlockInputDocumentStoreChange) -> Void] = [:]
    private var loadWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var loading = false
    private let lock = NSLock()

    init(
        count: Int,
        initialLimit: Int,
        blockProvider: @escaping @Sendable (Int) -> BlockInputBlock
    ) {
        generatedCount = max(count, 0)
        self.blockProvider = blockProvider
        let loadedCount = min(max(initialLimit, 1), generatedCount)
        loadedBlocks = (0..<loadedCount).map(blockProvider)
        if loadedBlocks.isEmpty {
            loadedBlocks = [BlockInputBlock.emptyParagraph()]
            totalCount = 1
            nextGeneratedIndex = generatedCount
        } else {
            totalCount = generatedCount
            nextGeneratedIndex = loadedCount
        }
        indexesByID = Self.indexesByID(for: loadedBlocks)
    }

    func observeChanges(_ observer: @escaping @MainActor (BlockInputDocumentStoreChange) -> Void) -> BlockInputDocumentStoreObservation {
        let id = UUID()
        locked {
            observers[id] = observer
        }
        return BlockInputDocumentStoreObservation { [weak self] in
            guard let self else {
                return
            }
            locked {
                observers[id] = nil
            }
        }
    }

    @MainActor
    func loadNextBlockBatch(limit: Int) async throws {
        let pendingLoad: PendingLoad
        loadLoop:
        while true {
            if isLoading {
                await waitForCurrentLoad()
                try Task.checkCancellation()
                continue
            }
            guard let startedLoad = beginLoad(limit: limit) else {
                return
            }
            pendingLoad = startedLoad
            break loadLoop
        }
        pendingLoad.observers.forEach { $0(.loadingStateChanged(isLoading: true)) }
        do {
            try Task.checkCancellation()
            let provider = blockProvider
            let sourceStartIndex = pendingLoad.sourceStartIndex
            let endIndex = pendingLoad.endIndex
            let newBlocks = await Task.detached(priority: .utility) {
                (sourceStartIndex..<endIndex).map(provider)
            }.value
            try Task.checkCancellation()
            let finishedLoad = finishLoad(pendingLoad, newBlocks: newBlocks)
            finishedLoad.waiters.forEach { $0.resume() }
            finishedLoad.observers.forEach { $0(.appendedBlocks(finishedLoad.batch)) }
            finishedLoad.observers.forEach { $0(.loadingStateChanged(isLoading: false)) }
        } catch is CancellationError {
            let cancelledLoad = finishCancelledLoad()
            cancelledLoad.waiters.forEach { $0.resume() }
            cancelledLoad.observers.forEach { $0(.loadingStateChanged(isLoading: false)) }
            throw CancellationError()
        } catch {
            let cancelledLoad = finishCancelledLoad()
            cancelledLoad.waiters.forEach { $0.resume() }
            cancelledLoad.observers.forEach { $0(.loadingStateChanged(isLoading: false)) }
            throw error
        }
    }

    @MainActor
    func loadAllRemainingBlocks(limit: Int) async throws {
        while !isComplete {
            try Task.checkCancellation()
            try await loadNextBlockBatch(limit: limit)
        }
    }

    @MainActor
    func completeDocumentSnapshot(limit: Int) async throws -> BlockInputDocument {
        let snapshot = snapshotRequest()
        let provider = blockProvider
        let remainingBlocks = await Task.detached(priority: .utility) {
            (snapshot.nextGeneratedIndex..<snapshot.generatedCount).map(provider)
        }.value
        return BlockInputDocument(blocks: (snapshot.loadedBlocks + remainingBlocks).map { $0 })
    }

    func block(at index: Int) -> BlockInputBlock? {
        locked {
            guard loadedBlocks.indices.contains(index) else {
                return nil
            }
            return loadedBlocks[index]
        }
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        locked {
            guard let index = indexesByID[id],
                  loadedBlocks.indices.contains(index),
                  loadedBlocks[index].id == id else {
                return nil
            }
            return loadedBlocks[index]
        }
    }

    func index(of id: BlockInputBlockID) -> Int? {
        locked { indexesByID[id] }
    }

    func replaceDocument(_ document: BlockInputDocument) {
        locked {
            loadedBlocks = document.blocks.isEmpty ? [BlockInputBlock.emptyParagraph()] : document.blocks
            totalCount = loadedBlocks.count
            nextGeneratedIndex = generatedCount
            indexesByID = Self.indexesByID(for: loadedBlocks)
        }
        emit(.replacedDocument)
    }

    func replaceBlock(_ block: BlockInputBlock) {
        locked {
            guard let index = indexesByID[block.id],
                  loadedBlocks.indices.contains(index) else {
                return
            }
            loadedBlocks[index] = block
        }
    }

    func insertBlocks(_ blocks: [BlockInputBlock], at index: Int) {
        locked {
            let insertionIndex = BlockInputDocument.insertionIndexPreservingLeadingFrontMatter(index, in: loadedBlocks)
            loadedBlocks.insert(contentsOf: blocks, at: insertionIndex)
            totalCount += blocks.count
            indexesByID = Self.indexesByID(for: loadedBlocks)
        }
    }

    func deleteBlocks(withIDs ids: [BlockInputBlockID]) {
        locked {
            let deletedIDs = Set(ids)
            let beforeCount = loadedBlocks.count
            loadedBlocks.removeAll { deletedIDs.contains($0.id) }
            totalCount -= beforeCount - loadedBlocks.count
            if loadedBlocks.isEmpty, totalCount == 0 {
                loadedBlocks = [BlockInputBlock.emptyParagraph()]
                totalCount = 1
                nextGeneratedIndex = generatedCount
            }
            indexesByID = Self.indexesByID(for: loadedBlocks)
        }
    }

    func moveBlock(withID id: BlockInputBlockID, to index: Int) {
        locked {
            guard let sourceIndex = indexesByID[id],
                  loadedBlocks.indices.contains(sourceIndex) else {
                return
            }
            let targetIndex = min(max(index, 0), loadedBlocks.count - 1)
            guard targetIndex != sourceIndex,
                  BlockInputDocument.canMovePreservingLeadingFrontMatter(
                    sourceIndex: sourceIndex,
                    targetIndex: targetIndex,
                    in: loadedBlocks
                  ) else {
                return
            }
            let block = loadedBlocks.remove(at: sourceIndex)
            loadedBlocks.insert(block, at: targetIndex)
            indexesByID = Self.indexesByID(for: loadedBlocks)
        }
    }

    private func beginLoad(limit: Int) -> PendingLoad? {
        locked {
            guard !loading,
                  nextGeneratedIndex < generatedCount else {
                return nil
            }
            loading = true
            let resolvedLimit = max(limit, 1)
            let sourceStartIndex = nextGeneratedIndex
            let endIndex = min(generatedCount, sourceStartIndex + resolvedLimit)
            return PendingLoad(
                sourceStartIndex: sourceStartIndex,
                endIndex: endIndex,
                isComplete: endIndex >= generatedCount,
                observers: Array(observers.values)
            )
        }
    }

    private func finishLoad(_ pendingLoad: PendingLoad, newBlocks: [BlockInputBlock]) -> FinishedLoad {
        locked {
            let startIndex = loadedBlocks.count
            loadedBlocks.append(contentsOf: newBlocks)
            nextGeneratedIndex = pendingLoad.endIndex
            totalCount = max(totalCount, loadedBlocks.count + (generatedCount - nextGeneratedIndex))
            for (offset, block) in newBlocks.enumerated() where indexesByID[block.id] == nil {
                indexesByID[block.id] = startIndex + offset
            }
            loading = false
            return FinishedLoad(
                batch: BlockInputDocumentStoreBatch(
                    startIndex: startIndex,
                    blocks: newBlocks,
                    isComplete: pendingLoad.isComplete
                ),
                observers: Array(observers.values),
                waiters: removeLoadWaiters()
            )
        }
    }

    private func finishCancelledLoad() -> FinishedLoadingStateChange {
        locked {
            loading = false
            return FinishedLoadingStateChange(
                observers: Array(observers.values),
                waiters: removeLoadWaiters()
            )
        }
    }

    private func snapshotRequest() -> SnapshotRequest {
        locked {
            SnapshotRequest(
                loadedBlocks: loadedBlocks,
                nextGeneratedIndex: nextGeneratedIndex,
                generatedCount: generatedCount
            )
        }
    }

    private func emit(_ change: BlockInputDocumentStoreChange) {
        let observers = locked { Array(self.observers.values) }
        Task { @MainActor in
            observers.forEach { $0(change) }
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func removeLoadWaiters() -> [CheckedContinuation<Void, Never>] {
        let waiters = Array(loadWaiters.values)
        loadWaiters.removeAll()
        return waiters
    }

    private func waitForCurrentLoad() async {
        await withCheckedContinuation { continuation in
            let shouldResume = locked {
                guard loading else {
                    return true
                }
                loadWaiters[UUID()] = continuation
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    private static func indexesByID(for blocks: [BlockInputBlock]) -> [BlockInputBlockID: Int] {
        var indexes: [BlockInputBlockID: Int] = [:]
        for (index, block) in blocks.enumerated() where indexes[block.id] == nil {
            indexes[block.id] = index
        }
        return indexes
    }
}

private struct FinishedLoad {
    var batch: BlockInputDocumentStoreBatch
    var observers: [@MainActor (BlockInputDocumentStoreChange) -> Void]
    var waiters: [CheckedContinuation<Void, Never>]
}

private struct FinishedLoadingStateChange {
    var observers: [@MainActor (BlockInputDocumentStoreChange) -> Void]
    var waiters: [CheckedContinuation<Void, Never>]
}

private struct PendingLoad {
    var sourceStartIndex: Int
    var endIndex: Int
    var isComplete: Bool
    var observers: [@MainActor (BlockInputDocumentStoreChange) -> Void]
}

private struct SnapshotRequest: Sendable {
    var loadedBlocks: [BlockInputBlock]
    var nextGeneratedIndex: Int
    var generatedCount: Int
}
