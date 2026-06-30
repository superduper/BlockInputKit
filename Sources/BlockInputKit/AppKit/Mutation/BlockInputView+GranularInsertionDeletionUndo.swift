import AppKit

extension BlockInputView {
    func applyGranularInsertionUndo(
        _ blocks: [BlockInputBlock],
        at insertionIndex: Int,
        changedBlocks: [BlockInputBlock] = [],
        markerTransaction: BlockInputNumberedListMarkerTransaction? = nil,
        selection: BlockInputSelection?
    ) -> Bool {
        let resolvedInsertionIndex = frontMatterPreservingInsertionIndex(insertionIndex)
        if canSynchronizeCacheForGranularInsertion(insertedBlockCount: blocks.count) {
            guard document.insertBlocks(blocks, at: resolvedInsertionIndex) != nil else {
                return false
            }
        } else {
            markDocumentCacheUnsynchronized()
        }
        syncDocumentStore(.insertBlocks(blocks, insertionIndex: resolvedInsertionIndex))
        applyChangedBlocks(changedBlocks, markerTransaction: markerTransaction)
        applySelection(validUndoSelection(selection), notify: true)
        if blocks.count == 1 {
            insertVisibleBlock(at: resolvedInsertionIndex)
        } else {
            reloadDataKeepingFocus()
        }
        publishDocumentChange()
        return true
    }

    func applyGranularDeletionUndo(
        _ blockIDs: [BlockInputBlockID],
        at deletionIndex: Int,
        changedBlocks: [BlockInputBlock] = [],
        markerTransaction: BlockInputNumberedListMarkerTransaction? = nil,
        selection: BlockInputSelection?
    ) -> Bool {
        applyChangedBlocks(changedBlocks, markerTransaction: markerTransaction)
        if canSynchronizeCacheForGranularDeletion(deletedBlockCount: blockIDs.count) {
            let deletedIDs = Set(blockIDs)
            document.blocks.removeAll { deletedIDs.contains($0.id) }
        } else {
            markDocumentCacheUnsynchronized()
        }
        syncDocumentStore(.deleteBlocks(blockIDs))
        applySelection(validUndoSelection(selection), notify: true)
        if blockIDs.count == 1 {
            deleteVisibleBlock(at: deletionIndex, deletedBlockIDs: blockIDs)
        } else {
            reloadDataKeepingFocus()
        }
        publishDocumentChange()
        return true
    }

    private func applyChangedBlocks(
        _ changedBlocks: [BlockInputBlock],
        markerTransaction: BlockInputNumberedListMarkerTransaction?
    ) {
        if let markerTransaction,
           documentStore is BlockInputMarkerAdjustingStore {
            syncDocumentStore(.numberedListMarkerTransaction(markerTransaction))
        } else {
            changedBlocks.forEach { syncDocumentStore(.replaceBlock($0)) }
        }
        for changedBlock in changedBlocks {
            if let changedIndex = index(of: changedBlock.id) {
                _ = replaceCachedBlock(changedBlock, at: changedIndex)
            }
        }
    }
}
