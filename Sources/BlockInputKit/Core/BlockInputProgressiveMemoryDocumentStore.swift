import Foundation

/// In-memory progressive store for already parsed block sources.
///
/// The editor sees only the loaded prefix until callers request more batches.
/// Complete snapshots are materialized from the full source without appending
/// hidden rows to the editor-visible prefix.
public final class BlockInputProgressiveMemoryDocumentStore: BlockInputDocumentStore,
    BlockInputMarkerAdjustingStore,
    @unchecked Sendable {
    /// Number of source blocks currently visible to the editor.
    public var loadedBlockCount: Int {
        locked { loadedBlocks.count }
    }

    /// Total source block count.
    public var totalBlockCount: Int? {
        locked { sourceBlocks.count }
    }

    /// Whether every source block has been appended to the editor-visible prefix.
    public var isComplete: Bool {
        locked { nextSourceIndex >= sourceBlocks.count }
    }

    /// Whether a batch load is currently appending to the visible prefix.
    public private(set) var isLoading: Bool {
        get {
            locked { loading }
        }
        set {
            locked {
                loading = newValue
            }
        }
    }

    private var sourceBlocks: [BlockInputBlock]
    private var loadedBlocks: [BlockInputBlock]
    private var nextSourceIndex: Int
    private var indexesByID: [BlockInputBlockID: Int]
    private var observers: [UUID: @MainActor (BlockInputDocumentStoreChange) -> Void] = [:]
    private var loadWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private let lock = NSLock()
    private var loading = false
    private var markerTransactions: [BlockInputNumberedListMarkerTransaction] = []

    /// Creates a progressive store with an initial loaded prefix.
    ///
    /// Empty sources are normalized to a single editable paragraph. `initialLimit`
    /// is clamped to at least one block and at most the normalized source count.
    public init(blocks: [BlockInputBlock], initialLimit: Int) {
        let normalizedBlocks = blocks.isEmpty ? [BlockInputBlock.emptyParagraph()] : blocks
        let loadedCount = min(max(initialLimit, 1), normalizedBlocks.count)
        sourceBlocks = normalizedBlocks
        loadedBlocks = Array(normalizedBlocks.prefix(loadedCount))
        nextSourceIndex = loadedCount
        indexesByID = Self.indexesByID(for: loadedBlocks)
    }

    /// Registers for progressive append, replacement, and loading failure changes.
    public func observeChanges(_ observer: @escaping @MainActor (BlockInputDocumentStoreChange) -> Void) -> BlockInputDocumentStoreObservation {
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

    /// Appends the next unloaded source blocks to the editor-visible prefix.
    @MainActor
    public func loadNextBlockBatch(limit: Int) async throws {
        let loadingObservers: [@MainActor (BlockInputDocumentStoreChange) -> Void]
        loadLoop:
        while true {
            switch beginLoadIfPossible() {
            case .started(let observers):
                loadingObservers = observers
                break loadLoop
            case .wait:
                await waitForCurrentLoad()
                try Task.checkCancellation()
                continue
            case .finished:
                return
            }
        }
        loadingObservers.forEach { $0(.loadingStateChanged(isLoading: true)) }

        do {
            try Task.checkCancellation()
            emitFinishedLoad(finishLoad(limit: limit))
        } catch is CancellationError {
            emitCancelledLoad(finishFailedLoad())
            throw CancellationError()
        } catch {
            emitFailedLoad(finishFailedLoad(), error: error)
            throw error
        }
    }

    /// Appends every remaining source block to the editor-visible prefix.
    @MainActor
    public func loadAllRemainingBlocks(limit: Int) async throws {
        while !isComplete {
            try Task.checkCancellation()
            try await loadNextBlockBatch(limit: limit)
        }
    }

    /// Returns a complete source snapshot without changing the visible prefix.
    @MainActor
    public func completeDocumentSnapshot(limit: Int) async throws -> BlockInputDocument {
        locked {
            let resolvedTransactions = markerTransactions.resolvingListRunBounds(in: sourceBlocks)
            return BlockInputDocument(blocks: sourceBlocks.enumerated().map { index, block in
                effectiveBlock(block, at: index, in: sourceBlocks, applying: resolvedTransactions)
            })
        }.detachedStorage()
    }

    /// Returns the loaded block at `index`, or nil when the index has not been loaded.
    public func block(at index: Int) -> BlockInputBlock? {
        locked {
            guard loadedBlocks.indices.contains(index) else {
                return nil
            }
            return effectiveBlock(loadedBlocks[index], at: index, in: loadedBlocks)
        }
    }

    /// Returns a loaded block by ID.
    public func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        locked {
            guard let index = indexesByID[id],
                  loadedBlocks.indices.contains(index),
                  loadedBlocks[index].id == id else {
                return nil
            }
            return effectiveBlock(loadedBlocks[index], at: index, in: loadedBlocks)
        }
    }

    /// Returns the loaded index for a block ID.
    public func index(of id: BlockInputBlockID) -> Int? {
        locked { indexesByID[id] }
    }

    /// Replaces the entire source and loaded prefix.
    public func replaceDocument(_ document: BlockInputDocument) {
        locked {
            loadedBlocks = document.blocks
            sourceBlocks = document.blocks
            nextSourceIndex = document.blocks.count
            indexesByID = Self.indexesByID(for: loadedBlocks)
            markerTransactions = []
        }
        emit(.replacedDocument)
    }

    /// Replaces a loaded block and its matching source block.
    public func replaceBlock(_ block: BlockInputBlock) {
        locked {
            guard let index = indexesByID[block.id], loadedBlocks.indices.contains(index) else {
                return
            }
            loadedBlocks[index] = storedBlockForReplacement(block, at: index, in: loadedBlocks)
            if let sourceIndex = sourceBlocks.firstIndex(where: { $0.id == block.id }) {
                sourceBlocks[sourceIndex] = storedBlockForReplacement(block, at: sourceIndex, in: sourceBlocks)
            }
            removeMarkerOverride(for: block.id)
        }
    }

    /// Inserts loaded blocks into both the visible prefix and full source.
    public func insertBlocks(_ blocks: [BlockInputBlock], at index: Int) {
        locked {
            let insertionIndex = BlockInputDocument.insertionIndexPreservingLeadingFrontMatter(index, in: loadedBlocks)
            loadedBlocks.insert(contentsOf: blocks, at: insertionIndex)
            sourceBlocks.insert(contentsOf: blocks, at: insertionIndex)
            nextSourceIndex += blocks.count
            indexesByID = Self.indexesByID(for: loadedBlocks)
            shiftMarkerTransactionsForInsertion(at: insertionIndex, count: blocks.count)
        }
    }

    /// Deletes matching loaded and unloaded source blocks.
    public func deleteBlocks(withIDs ids: [BlockInputBlockID]) {
        locked {
            let deletedIDs = Set(ids)
            let loadedDeleteCount = loadedBlocks.reduce(0) { count, block in
                count + (deletedIDs.contains(block.id) ? 1 : 0)
            }
            let sourceDeletedIndexes = sourceBlocks.indices.filter { deletedIDs.contains(sourceBlocks[$0].id) }
            loadedBlocks.removeAll { deletedIDs.contains($0.id) }
            sourceBlocks.removeAll { deletedIDs.contains($0.id) }
            nextSourceIndex = max(0, nextSourceIndex - loadedDeleteCount)
            nextSourceIndex = min(nextSourceIndex, sourceBlocks.count)
            indexesByID = Self.indexesByID(for: loadedBlocks)
            deletedIDs.forEach { removeMarkerOverride(for: $0) }
            for deletedIndex in sourceDeletedIndexes.reversed() {
                shiftMarkerTransactionsForDeletion(at: deletedIndex, count: 1)
            }
        }
    }

    /// Moves a loaded block in both the visible prefix and full source.
    public func moveBlock(withID id: BlockInputBlockID, to index: Int) {
        locked {
            if !markerTransactions.isEmpty {
                compactMarkerTransactions()
            }
            guard let sourceIndex = indexesByID[id], loadedBlocks.indices.contains(sourceIndex) else {
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
            if let sourceBlockIndex = sourceBlocks.firstIndex(where: { $0.id == id }) {
                let sourceBlock = sourceBlocks.remove(at: sourceBlockIndex)
                sourceBlocks.insert(sourceBlock, at: min(targetIndex, sourceBlocks.count))
            }
            indexesByID = Self.indexesByID(for: loadedBlocks)
        }
    }

    /// Moves a loaded block without normalizing numbered-list markers.
    public func moveBlockWithoutNormalizing(withID id: BlockInputBlockID, to index: Int) {
        locked {
            if !markerTransactions.isEmpty {
                compactMarkerTransactions()
            }
        }
        moveBlock(withID: id, to: index)
    }

    /// Applies deferred numbered-list marker adjustments to effective block reads.
    public func applyNumberedListMarkerTransaction(_ transaction: BlockInputNumberedListMarkerTransaction) {
        locked {
            guard !transaction.isEmpty else {
                return
            }
            markerTransactions.append(transaction)
            if markerTransactions.count > markerAdjustmentCompactionLimit {
                compactMarkerTransactions()
            }
        }
    }

    private func emit(_ change: BlockInputDocumentStoreChange) {
        let observers = locked { Array(self.observers.values) }
        Task { @MainActor in
            observers.forEach { $0(change) }
        }
    }

    private func beginLoadIfPossible() -> BlockInputProgressiveMemoryLoadStart {
        locked {
            if loading {
                return .wait
            }
            guard nextSourceIndex < sourceBlocks.count else {
                return .finished
            }
            loading = true
            return .started(Array(observers.values))
        }
    }

    private func finishLoad(limit: Int) -> BlockInputProgressiveMemoryFinishedLoad {
        locked {
            let resolvedLimit = max(limit, 1)
            let startIndex = loadedBlocks.count
            let endIndex = min(sourceBlocks.count, nextSourceIndex + resolvedLimit)
            let newBlocks = Array(sourceBlocks[nextSourceIndex..<endIndex])
            loadedBlocks.append(contentsOf: newBlocks)
            nextSourceIndex = endIndex
            let effectiveNewBlocks = newBlocks.enumerated().map { offset, block in
                effectiveBlock(block, at: startIndex + offset, in: sourceBlocks)
            }
            for (offset, block) in newBlocks.enumerated() where indexesByID[block.id] == nil {
                indexesByID[block.id] = startIndex + offset
            }
            loading = false
            return BlockInputProgressiveMemoryFinishedLoad(
                batch: BlockInputDocumentStoreBatch(
                    startIndex: startIndex,
                    blocks: effectiveNewBlocks,
                    isComplete: nextSourceIndex >= sourceBlocks.count
                ),
                observers: Array(observers.values),
                waiters: removeLoadWaiters()
            )
        }
    }

    private func finishFailedLoad() -> BlockInputProgressiveMemoryFailedLoad {
        locked {
            loading = false
            return BlockInputProgressiveMemoryFailedLoad(observers: Array(observers.values), waiters: removeLoadWaiters())
        }
    }

    @MainActor
    private func emitFinishedLoad(_ finishedLoad: BlockInputProgressiveMemoryFinishedLoad) {
        finishedLoad.waiters.forEach { $0.resume() }
        finishedLoad.observers.forEach { $0(.appendedBlocks(finishedLoad.batch)) }
        finishedLoad.observers.forEach { $0(.loadingStateChanged(isLoading: false)) }
    }

    @MainActor
    private func emitCancelledLoad(_ cancelledLoad: BlockInputProgressiveMemoryFailedLoad) {
        cancelledLoad.waiters.forEach { $0.resume() }
        cancelledLoad.observers.forEach { $0(.loadingStateChanged(isLoading: false)) }
    }

    @MainActor
    private func emitFailedLoad(_ failedLoad: BlockInputProgressiveMemoryFailedLoad, error: Error) {
        failedLoad.waiters.forEach { $0.resume() }
        failedLoad.observers.forEach { $0(.loadingStateChanged(isLoading: false)) }
        failedLoad.observers.forEach { $0(.failed(error.localizedDescription)) }
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

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func indexesByID(for blocks: [BlockInputBlock]) -> [BlockInputBlockID: Int] {
        var indexes: [BlockInputBlockID: Int] = [:]
        for (index, block) in blocks.enumerated() where indexes[block.id] == nil {
            indexes[block.id] = index
        }
        return indexes
    }
}

private extension BlockInputProgressiveMemoryDocumentStore {
    func effectiveBlock(_ block: BlockInputBlock, at index: Int, in blocks: [BlockInputBlock]) -> BlockInputBlock {
        effectiveBlock(block, at: index, in: blocks, applying: markerTransactions)
    }

    func effectiveBlock(
        _ block: BlockInputBlock,
        at index: Int,
        in blocks: [BlockInputBlock],
        applying transactions: [BlockInputNumberedListMarkerTransaction]
    ) -> BlockInputBlock {
        guard case let .numberedListItem(start) = block.kind else {
            return block
        }
        var resolvedStart = start
        for transaction in transactions {
            for override in transaction.overrides where override.blockID == block.id {
                resolvedStart = override.start
            }
            for adjustment in transaction.adjustments where markerAdjustment(adjustment, appliesAt: index, to: block, in: blocks) {
                resolvedStart += adjustment.delta
            }
        }
        guard resolvedStart != start else {
            return block
        }
        var resolvedBlock = block
        resolvedBlock.kind = .numberedListItem(start: resolvedStart)
        return resolvedBlock
    }

    func removeMarkerOverride(for blockID: BlockInputBlockID) {
        markerTransactions = markerTransactions.map { transaction in
            BlockInputNumberedListMarkerTransaction(
                adjustments: transaction.adjustments,
                overrides: transaction.overrides.filter { $0.blockID != blockID }
            )
        }.filter { !$0.isEmpty }
    }

    func storedBlockForReplacement(
        _ block: BlockInputBlock,
        at index: Int,
        in blocks: [BlockInputBlock]
    ) -> BlockInputBlock {
        guard case let .numberedListItem(start) = block.kind else {
            return block
        }
        let adjustmentDelta = markerTransactions.reduce(0) { delta, transaction in
            delta + transaction.adjustments.reduce(0) { adjustmentDelta, adjustment in
                guard markerAdjustment(adjustment, appliesAt: index, to: block, in: blocks) else {
                    return adjustmentDelta
                }
                return adjustmentDelta + adjustment.delta
            }
        }
        guard adjustmentDelta != 0 else {
            return block
        }
        var storedBlock = block
        storedBlock.kind = .numberedListItem(start: start - adjustmentDelta)
        return storedBlock
    }

    func shiftMarkerTransactionsForInsertion(at index: Int, count: Int) {
        markerTransactions = markerTransactions.map { transaction in
            BlockInputNumberedListMarkerTransaction(
                adjustments: transaction.adjustments.map { $0.shiftedForInsertion(at: index, count: count) },
                overrides: transaction.overrides
            )
        }
    }

    func shiftMarkerTransactionsForDeletion(at index: Int, count: Int) {
        markerTransactions = markerTransactions.map { transaction in
            BlockInputNumberedListMarkerTransaction(
                adjustments: transaction.adjustments.compactMap { $0.shiftedForDeletion(at: index, count: count) },
                overrides: transaction.overrides
            )
        }.filter { !$0.isEmpty }
    }

    func compactMarkerTransactions() {
        let sourceTransactions = markerTransactions.resolvingListRunBounds(in: sourceBlocks)
        let loadedTransactions = markerTransactions.resolvingListRunBounds(in: loadedBlocks)
        sourceBlocks = sourceBlocks.enumerated().map { index, block in
            effectiveBlock(block, at: index, in: sourceBlocks, applying: sourceTransactions)
        }
        loadedBlocks = loadedBlocks.enumerated().map { index, block in
            effectiveBlock(block, at: index, in: loadedBlocks, applying: loadedTransactions)
        }
        markerTransactions = []
    }

    func markerAdjustment(
        _ adjustment: BlockInputNumberedListMarkerAdjustment,
        appliesAt index: Int,
        to block: BlockInputBlock,
        in blocks: [BlockInputBlock]
    ) -> Bool {
        guard adjustment.contains(index: index, block: block) else {
            return false
        }
        return adjustment.isWithinListRunScope(at: index, in: blocks)
    }
}
