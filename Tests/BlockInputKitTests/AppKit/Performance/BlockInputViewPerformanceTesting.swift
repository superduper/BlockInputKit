@testable import BlockInputKit

final class DocumentReadCountingStore: BlockInputDocumentStore, BlockInputMarkerAdjustingStore {
    private var storedDocument: BlockInputDocument
    private(set) var documentReadCount = 0
    private(set) var indexLookupCount = 0
    private(set) var replaceDocumentCount = 0
    private(set) var replacedBlockIDs: [BlockInputBlockID] = []
    private(set) var insertedBlockBatches: [(blocks: [BlockInputBlock], index: Int)] = []
    private(set) var deletedBlockIDs: [[BlockInputBlockID]] = []
    private(set) var movedBlocks: [(id: BlockInputBlockID, index: Int)] = []
    private(set) var markerTransactions: [BlockInputNumberedListMarkerTransaction] = []
    private(set) var markerCompactionCount = 0
    private var appliedMarkerTransactions: [BlockInputNumberedListMarkerTransaction] = []

    var document: BlockInputDocument {
        documentReadCount += 1
        return effectiveDocument()
    }

    var loadedBlockCount: Int {
        storedDocument.blocks.count
    }

    init(document: BlockInputDocument) {
        storedDocument = document
    }

    func resetCounts() {
        documentReadCount = 0
        indexLookupCount = 0
        replaceDocumentCount = 0
        replacedBlockIDs = []
        insertedBlockBatches = []
        deletedBlockIDs = []
        movedBlocks = []
        markerTransactions = []
        markerCompactionCount = 0
    }

    func block(at index: Int) -> BlockInputBlock? {
        guard storedDocument.blocks.indices.contains(index) else {
            return nil
        }
        return effectiveBlock(storedDocument.blocks[index], at: index)
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        guard let index = storedDocument.index(of: id) else {
            return nil
        }
        return effectiveBlock(storedDocument.blocks[index], at: index)
    }

    func index(of id: BlockInputBlockID) -> Int? {
        indexLookupCount += 1
        return storedDocument.index(of: id)
    }

    @MainActor
    func completeDocumentSnapshot(limit: Int) async throws -> BlockInputDocument {
        document
    }

    func replaceDocument(_ document: BlockInputDocument) {
        replaceDocumentCount += 1
        storedDocument = document
        markerTransactions = []
        appliedMarkerTransactions = []
    }

    func replaceBlock(_ block: BlockInputBlock) {
        replacedBlockIDs.append(block.id)
        guard let index = storedDocument.index(of: block.id) else {
            return
        }
        storedDocument.blocks[index] = storedBlockForReplacement(block, at: index)
        removeMarkerOverride(for: block.id)
    }

    func insertBlocks(_ blocks: [BlockInputBlock], at index: Int) {
        insertedBlockBatches.append((blocks, index))
        let insertionIndex = BlockInputDocument.insertionIndexPreservingLeadingFrontMatter(index, in: storedDocument.blocks)
        storedDocument.insertBlocks(blocks, at: index)
        shiftMarkerTransactionsForInsertion(at: insertionIndex, count: blocks.count)
    }

    func deleteBlocks(withIDs ids: [BlockInputBlockID]) {
        deletedBlockIDs.append(ids)
        let deletedIDs = Set(ids)
        let deletedIndexes = storedDocument.blocks.indices.filter { deletedIDs.contains(storedDocument.blocks[$0].id) }
        storedDocument.blocks.removeAll { deletedIDs.contains($0.id) }
        deletedIDs.forEach { removeMarkerOverride(for: $0) }
        for deletedIndex in deletedIndexes.reversed() {
            shiftMarkerTransactionsForDeletion(at: deletedIndex, count: 1)
        }
    }

    func moveBlock(withID id: BlockInputBlockID, to index: Int) {
        movedBlocks.append((id, index))
        if !appliedMarkerTransactions.isEmpty {
            compactMarkerTransactions()
        }
        storedDocument.moveBlock(blockID: id, to: index)
    }

    func moveBlockWithoutNormalizing(withID id: BlockInputBlockID, to index: Int) {
        movedBlocks.append((id, index))
        if !appliedMarkerTransactions.isEmpty {
            compactMarkerTransactions()
        }
        guard let sourceIndex = storedDocument.index(of: id),
              BlockInputDocument.canMovePreservingLeadingFrontMatter(
                sourceIndex: sourceIndex,
                targetIndex: index,
                in: storedDocument.blocks
              ) else {
            return
        }
        let finalTargetIndex = min(max(index, 0), storedDocument.blocks.count - 1)
        let block = storedDocument.blocks.remove(at: sourceIndex)
        storedDocument.blocks.insert(block, at: finalTargetIndex)
    }

    func applyNumberedListMarkerTransaction(_ transaction: BlockInputNumberedListMarkerTransaction) {
        markerTransactions.append(transaction)
        appliedMarkerTransactions.append(transaction)
    }

    private func shiftMarkerTransactionsForInsertion(at index: Int, count: Int) {
        appliedMarkerTransactions = appliedMarkerTransactions.map { transaction in
            BlockInputNumberedListMarkerTransaction(
                adjustments: transaction.adjustments.map { $0.shiftedForInsertion(at: index, count: count) },
                overrides: transaction.overrides
            )
        }
    }

    private func shiftMarkerTransactionsForDeletion(at index: Int, count: Int) {
        appliedMarkerTransactions = appliedMarkerTransactions.map { transaction in
            BlockInputNumberedListMarkerTransaction(
                adjustments: transaction.adjustments.compactMap { $0.shiftedForDeletion(at: index, count: count) },
                overrides: transaction.overrides
            )
        }.filter { !$0.isEmpty }
    }

    private func compactMarkerTransactions() {
        markerCompactionCount += 1
        storedDocument = effectiveDocument()
        appliedMarkerTransactions = []
    }

    private func effectiveDocument() -> BlockInputDocument {
        let resolvedTransactions = appliedMarkerTransactions.resolvingListRunBounds(in: storedDocument.blocks)
        return BlockInputDocument(blocks: storedDocument.blocks.enumerated().map { index, block in
            effectiveBlock(block, at: index, applying: resolvedTransactions)
        })
    }

    private func removeMarkerOverride(for blockID: BlockInputBlockID) {
        appliedMarkerTransactions = appliedMarkerTransactions.map { transaction in
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
        let adjustmentDelta = appliedMarkerTransactions.reduce(0) { delta, transaction in
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

    private func effectiveBlock(_ block: BlockInputBlock, at index: Int) -> BlockInputBlock {
        effectiveBlock(block, at: index, applying: appliedMarkerTransactions)
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
        var resolvedBlock = block
        resolvedBlock.kind = .numberedListItem(start: resolvedStart)
        return resolvedBlock
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
