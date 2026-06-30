import Foundation

/// Document storage boundary used by the editor and host app.
///
/// The editor reads blocks by index and stable ID so hosts can keep large
/// documents outside of the view. Large host stores should keep these indexed
/// read methods cheap and override the granular mutation methods to avoid full
/// document replacement on common editor operations.
public protocol BlockInputDocumentStore: AnyObject {
    /// Number of blocks currently loaded and available to the editor.
    var loadedBlockCount: Int { get }
    /// Total block count when it is known without finishing the load.
    var totalBlockCount: Int? { get }
    /// Whether every block has been loaded.
    var isComplete: Bool { get }
    /// Whether the store is currently loading another block batch.
    var isLoading: Bool { get }

    /// Returns the block at an ordered index.
    func block(at index: Int) -> BlockInputBlock?
    /// Returns the block with a stable ID.
    func block(withID id: BlockInputBlockID) -> BlockInputBlock?
    /// Returns the ordered index for a stable block ID.
    func index(of id: BlockInputBlockID) -> Int?
    /// Registers a store observer. Release or cancel the returned token to stop observing changes.
    func observeChanges(_ observer: @escaping @MainActor (BlockInputDocumentStoreChange) -> Void) -> BlockInputDocumentStoreObservation
    /// Loads the next available block batch. `limit` is a target count of complete parsed blocks, not source lines.
    @MainActor
    func loadNextBlockBatch(limit: Int) async throws
    /// Loads all remaining blocks into the editor-visible loaded prefix in batches.
    @MainActor
    func loadAllRemainingBlocks(limit: Int) async throws
    /// Returns a complete document snapshot for save/export.
    ///
    /// Progressive stores may materialize this without publishing append changes
    /// or expanding `loadedBlockCount`; the default implementation loads all
    /// remaining blocks into the visible prefix first.
    @MainActor
    func completeDocumentSnapshot(limit: Int) async throws -> BlockInputDocument
    /// Replaces the full document after broad structural mutations.
    func replaceDocument(_ document: BlockInputDocument)
    /// Replaces one block after a text or formatting mutation.
    ///
    /// The default implementation calls `replaceDocument(_:)` only for complete
    /// stores when the block exists and changes the current document.
    func replaceBlock(_ block: BlockInputBlock)
    /// Inserts blocks at an ordered index.
    ///
    /// The default implementation calls `replaceDocument(_:)` only for complete
    /// stores when the insertion changes the current document. Stores should not
    /// insert blocks before existing leading frontmatter; direct array-backed
    /// stores can use `BlockInputDocument.insertionIndexPreservingLeadingFrontMatter`.
    func insertBlocks(_ blocks: [BlockInputBlock], at index: Int)
    /// Deletes blocks by stable ID.
    ///
    /// The default implementation calls `replaceDocument(_:)` only for complete
    /// stores when at least one block is removed.
    func deleteBlocks(withIDs ids: [BlockInputBlockID])
    /// Moves one block to a final ordered index.
    ///
    /// The default implementation calls `replaceDocument(_:)` only for complete
    /// stores when the block exists and its index changes. Direct array-backed
    /// stores can use `BlockInputDocument.canMovePreservingLeadingFrontMatter`
    /// before applying a move.
    func moveBlock(withID id: BlockInputBlockID, to index: Int)
}

/// In-memory store for simple editors and tests.
public final class BlockInputMemoryDocumentStore: BlockInputDocumentStore, BlockInputMarkerAdjustingStore, @unchecked Sendable {
    /// Current document snapshot.
    public var document: BlockInputDocument {
        lock.lock()
        defer { lock.unlock() }
        return effectiveDocument()
    }

    /// Number of blocks available to the editor.
    public var loadedBlockCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedDocument.blocks.count
    }

    /// Total block count.
    public var totalBlockCount: Int? {
        loadedBlockCount
    }

    private var storedDocument: BlockInputDocument
    private var indexesByID: [BlockInputBlockID: Int]
    private var markerTransactions: [BlockInputNumberedListMarkerTransaction] = []
    private let lock = NSLock()
    // Inserts and deletes leave suffix indexes stale; rebuild lazily only when
    // a later lookup asks for one, keeping 100k-demo mutations responsive.
    private var indexesNeedRebuild = false

    /// Creates a memory-backed store for a complete document.
    public init(document: BlockInputDocument = BlockInputDocument()) {
        storedDocument = document
        indexesByID = Self.indexesByID(for: document)
    }

    /// Returns a detached complete document snapshot.
    @MainActor
    public func completeDocumentSnapshot(limit: Int) async throws -> BlockInputDocument {
        document.detachedStorage()
    }

    /// Returns the effective block at `index`, including any pending marker overrides.
    public func block(at index: Int) -> BlockInputBlock? {
        lock.lock()
        defer { lock.unlock() }
        guard storedDocument.blocks.indices.contains(index) else {
            return nil
        }
        return effectiveBlock(storedDocument.blocks[index], at: index)
    }

    /// Replaces the complete in-memory document and clears pending marker overrides.
    public func replaceDocument(_ document: BlockInputDocument) {
        lock.lock()
        defer { lock.unlock() }
        storedDocument = document
        markerTransactions = []
        rebuildIndexes()
    }

    /// Returns the effective block with `id`, including any pending marker overrides.
    public func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = unlockedIndex(of: id) else {
            return nil
        }
        return effectiveBlock(storedDocument.blocks[index], at: index)
    }

    /// Returns the ordered index for a block ID.
    public func index(of id: BlockInputBlockID) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return unlockedIndex(of: id)
    }

    /// Replaces an existing block while preserving store indexes and marker state.
    public func replaceBlock(_ block: BlockInputBlock) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = unlockedIndex(of: block.id) else {
            return
        }
        storedDocument.blocks[index] = storedBlockForReplacement(block, at: index)
        removeMarkerOverride(for: block.id)
    }

    /// Inserts blocks at an ordered index while preserving leading frontmatter.
    public func insertBlocks(_ blocks: [BlockInputBlock], at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        let insertionIndex = BlockInputDocument.insertionIndexPreservingLeadingFrontMatter(index, in: storedDocument.blocks)
        guard storedDocument.insertBlocks(blocks, at: index) != nil else {
            return
        }
        shiftMarkerTransactionsForInsertion(at: insertionIndex, count: blocks.count)
        indexesNeedRebuild = true
        for (offset, block) in blocks.enumerated() {
            let insertedIndex = insertionIndex + offset
            if let previousIndex = indexesByID[block.id],
               previousIndex <= insertedIndex {
                continue
            } else {
                indexesByID[block.id] = insertedIndex
            }
        }
    }

    /// Deletes blocks by stable ID.
    public func deleteBlocks(withIDs ids: [BlockInputBlockID]) {
        lock.lock()
        defer { lock.unlock() }
        guard !ids.isEmpty else {
            return
        }
        if ids.count == 1,
           let id = ids.first,
           let index = unlockedIndex(of: id) {
            storedDocument.blocks.remove(at: index)
            removeMarkerOverride(for: id)
            shiftMarkerTransactionsForDeletion(at: index, count: 1)
            indexesByID[id] = nil
            indexesNeedRebuild = true
            return
        }
        let deletedIDs = Set(ids)
        let deletedIndexes = storedDocument.blocks.indices.filter { deletedIDs.contains(storedDocument.blocks[$0].id) }
        storedDocument.blocks.removeAll { deletedIDs.contains($0.id) }
        deletedIDs.forEach { removeMarkerOverride(for: $0) }
        for deletedIndex in deletedIndexes.reversed() {
            shiftMarkerTransactionsForDeletion(at: deletedIndex, count: 1)
        }
        deletedIDs.forEach { indexesByID[$0] = nil }
        indexesNeedRebuild = true
    }

    /// Moves a block and normalizes affected numbered-list markers.
    public func moveBlock(withID id: BlockInputBlockID, to index: Int) {
        lock.lock()
        defer { lock.unlock() }
        if !markerTransactions.isEmpty {
            compactMarkerTransactions()
        }
        if indexesNeedRebuild {
            rebuildIndexes()
        }
        guard let sourceIndex = unlockedIndex(of: id) else {
            return
        }
        let finalTargetIndex = min(max(index, 0), storedDocument.blocks.count - 1)
        guard finalTargetIndex != sourceIndex else {
            return
        }
        guard storedDocument.moveBlockWithChangedBlocks(sourceIndex: sourceIndex, to: finalTargetIndex) != nil else {
            return
        }
        updateIndexesAfterMove(from: sourceIndex, to: finalTargetIndex)
    }

    /// Moves a block without normalizing numbered-list markers.
    public func moveBlockWithoutNormalizing(withID id: BlockInputBlockID, to index: Int) {
        lock.lock()
        defer { lock.unlock() }
        if !markerTransactions.isEmpty {
            compactMarkerTransactions()
        }
        if indexesNeedRebuild {
            rebuildIndexes()
        }
        guard let sourceIndex = unlockedIndex(of: id) else {
            return
        }
        let finalTargetIndex = min(max(index, 0), storedDocument.blocks.count - 1)
        guard finalTargetIndex != sourceIndex else {
            return
        }
        guard BlockInputDocument.canMovePreservingLeadingFrontMatter(
            sourceIndex: sourceIndex,
            targetIndex: finalTargetIndex,
            in: storedDocument.blocks
        ) else {
            return
        }
        if abs(finalTargetIndex - sourceIndex) == 1 {
            storedDocument.blocks.swapAt(sourceIndex, finalTargetIndex)
            updateIndexesAfterMove(from: sourceIndex, to: finalTargetIndex)
            return
        }
        let block = storedDocument.blocks.remove(at: sourceIndex)
        storedDocument.blocks.insert(block, at: finalTargetIndex)
        updateIndexesAfterMove(from: sourceIndex, to: finalTargetIndex)
    }

    /// Applies deferred numbered-list marker adjustments to effective block reads.
    public func applyNumberedListMarkerTransaction(_ transaction: BlockInputNumberedListMarkerTransaction) {
        lock.lock()
        defer { lock.unlock() }
        guard !transaction.isEmpty else {
            return
        }
        markerTransactions.append(transaction)
        if markerTransactions.count > markerAdjustmentCompactionLimit {
            compactMarkerTransactions()
        }
    }

    private func unlockedIndex(of id: BlockInputBlockID) -> Int? {
        if let index = indexesByID[id],
           storedDocument.blocks.indices.contains(index),
           storedDocument.blocks[index].id == id {
            return index
        }
        guard indexesNeedRebuild else {
            return nil
        }
        rebuildIndexes()
        guard let index = indexesByID[id],
              storedDocument.blocks.indices.contains(index),
              storedDocument.blocks[index].id == id else {
            return nil
        }
        return index
    }

    private func updateIndexesAfterMove(from sourceIndex: Int, to targetIndex: Int) {
        // Reindex only the shifted run; duplicate IDs still need a full
        // first-occurrence rebuild to preserve stable lookup semantics.
        let affectedRange = min(sourceIndex, targetIndex)...max(sourceIndex, targetIndex)
        var affectedIDs = Set<BlockInputBlockID>()
        for index in affectedRange {
            let blockID = storedDocument.blocks[index].id
            guard affectedIDs.insert(blockID).inserted else {
                rebuildIndexes()
                return
            }
            if let existingIndex = indexesByID[blockID],
               !affectedRange.contains(existingIndex) {
                rebuildIndexes()
                return
            }
        }
        for index in affectedRange {
            indexesByID[storedDocument.blocks[index].id] = index
        }
        indexesNeedRebuild = false
    }

    private func rebuildIndexes() {
        indexesByID = Self.indexesByID(for: storedDocument)
        indexesNeedRebuild = false
    }

    private static func indexesByID(for document: BlockInputDocument) -> [BlockInputBlockID: Int] {
        var indexes: [BlockInputBlockID: Int] = [:]
        for (index, block) in document.blocks.enumerated() where indexes[block.id] == nil {
            indexes[block.id] = index
        }
        return indexes
    }

    private func effectiveDocument() -> BlockInputDocument {
        let resolvedTransactions = markerTransactions.resolvingListRunBounds(in: storedDocument.blocks)
        return BlockInputDocument(blocks: storedDocument.blocks.enumerated().map { index, block in
            effectiveBlock(block, at: index, applying: resolvedTransactions)
        })
    }

    private func effectiveBlock(_ block: BlockInputBlock, at index: Int) -> BlockInputBlock {
        effectiveBlock(block, at: index, applying: markerTransactions)
    }

    private func effectiveBlock(
        _ block: BlockInputBlock,
        at index: Int,
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
            for adjustment in transaction.adjustments where markerAdjustment(adjustment, appliesAt: index, to: block) {
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

    private func removeMarkerOverride(for blockID: BlockInputBlockID) {
        markerTransactions = markerTransactions.map { transaction in
            BlockInputNumberedListMarkerTransaction(
                adjustments: transaction.adjustments,
                overrides: transaction.overrides.filter { $0.blockID != blockID }
            )
        }.filter { !$0.isEmpty }
    }

    private func storedBlockForReplacement(_ block: BlockInputBlock, at index: Int) -> BlockInputBlock {
        guard case let .numberedListItem(start) = block.kind else {
            return block
        }
        let adjustmentDelta = markerTransactions.reduce(0) { delta, transaction in
            delta + transaction.adjustments.reduce(0) { adjustmentDelta, adjustment in
                guard markerAdjustment(adjustment, appliesAt: index, to: block) else {
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

    private func shiftMarkerTransactionsForInsertion(at index: Int, count: Int) {
        markerTransactions = markerTransactions.map { transaction in
            BlockInputNumberedListMarkerTransaction(
                adjustments: transaction.adjustments.map { $0.shiftedForInsertion(at: index, count: count) },
                overrides: transaction.overrides
            )
        }
    }

    private func shiftMarkerTransactionsForDeletion(at index: Int, count: Int) {
        markerTransactions = markerTransactions.map { transaction in
            BlockInputNumberedListMarkerTransaction(
                adjustments: transaction.adjustments.compactMap { $0.shiftedForDeletion(at: index, count: count) },
                overrides: transaction.overrides
            )
        }.filter { !$0.isEmpty }
    }

    private func compactMarkerTransactions() {
        storedDocument = effectiveDocument()
        markerTransactions = []
    }

    private func markerAdjustment(
        _ adjustment: BlockInputNumberedListMarkerAdjustment,
        appliesAt index: Int,
        to block: BlockInputBlock
    ) -> Bool {
        guard adjustment.contains(index: index, block: block) else {
            return false
        }
        return adjustment.isWithinListRunScope(at: index, in: storedDocument.blocks)
    }
}
