import AppKit

struct ReplacementInsertionUndoContext {
    var replacement: BlockInputBlock
    var replacementIndex: Int
    var insertedBlocks: [BlockInputBlock]
    var insertionIndex: Int
    var changedBlocks: [BlockInputBlock]
    var markerTransaction: BlockInputNumberedListMarkerTransaction?
}

struct ReplacementDeletionUndoContext {
    var replacement: BlockInputBlock
    var replacementIndex: Int
    var deletedBlockIDs: [BlockInputBlockID]
    var deletionIndex: Int
    var changedBlocks: [BlockInputBlock]
    var markerTransaction: BlockInputNumberedListMarkerTransaction?
}

extension BlockInputView {
    func applyGranularReplacementInsertionUndo(
        _ context: ReplacementInsertionUndoContext,
        selection: BlockInputSelection?
    ) -> Bool {
        guard isEditable else {
            return false
        }
        let resolvedInsertionIndex = frontMatterPreservingInsertionIndex(
            context.insertionIndex,
            afterReplacing: context.replacement,
            at: context.replacementIndex
        )
        syncDocumentStore(.replaceBlock(context.replacement))
        syncDocumentStore(.insertBlocks(context.insertedBlocks, insertionIndex: resolvedInsertionIndex))
        let canApplyMarkerTransaction = context.markerTransaction != nil && documentStore is BlockInputMarkerAdjustingStore
        if let markerTransaction = context.markerTransaction,
           canApplyMarkerTransaction {
            syncDocumentStore(.numberedListMarkerTransaction(markerTransaction))
        }
        _ = replaceCachedBlock(context.replacement, at: context.replacementIndex)
        if canSynchronizeCacheForGranularInsertion(insertedBlockCount: context.insertedBlocks.count) {
            guard document.insertBlocks(context.insertedBlocks, at: resolvedInsertionIndex) != nil else {
                return false
            }
        } else {
            markDocumentCacheUnsynchronized()
        }
        if !canApplyMarkerTransaction {
            context.changedBlocks.forEach { syncDocumentStore(.replaceBlock($0)) }
        }
        for changedBlock in context.changedBlocks {
            if let changedIndex = index(of: changedBlock.id) {
                _ = replaceCachedBlock(changedBlock, at: changedIndex)
            }
        }
        applySelection(validUndoSelection(selection), notify: true)
        guard shouldDeferGranularCountLayout else {
            reloadDataKeepingFocus()
            publishDocumentChange()
            return true
        }
        if !reconfigureVisibleReplacement(context.replacement, at: context.replacementIndex) {
            collectionView.reloadItems(at: [IndexPath(item: context.replacementIndex, section: 0)])
            collectionView.layoutSubtreeIfNeeded()
        }
        if context.insertedBlocks.count == 1 {
            insertVisibleBlock(at: resolvedInsertionIndex)
        } else {
            reloadDataKeepingFocus()
        }
        publishDocumentChange()
        return true
    }

    func applyGranularReplacementDeletionUndo(
        _ context: ReplacementDeletionUndoContext,
        selection: BlockInputSelection?
    ) -> Bool {
        guard isEditable else {
            return false
        }
        syncDocumentStore(.replaceBlock(context.replacement))
        if let markerTransaction = context.markerTransaction,
           documentStore is BlockInputMarkerAdjustingStore {
            syncDocumentStore(.numberedListMarkerTransaction(markerTransaction))
        } else {
            context.changedBlocks.forEach { syncDocumentStore(.replaceBlock($0)) }
        }
        syncDocumentStore(.deleteBlocks(context.deletedBlockIDs))
        _ = replaceCachedBlock(context.replacement, at: context.replacementIndex)
        for changedBlock in context.changedBlocks {
            if let changedIndex = index(of: changedBlock.id) {
                _ = replaceCachedBlock(changedBlock, at: changedIndex)
            }
        }
        if canSynchronizeCacheForGranularDeletion(deletedBlockCount: context.deletedBlockIDs.count) {
            let deletedIDs = Set(context.deletedBlockIDs)
            document.blocks.removeAll { deletedIDs.contains($0.id) }
        } else {
            markDocumentCacheUnsynchronized()
        }
        applySelection(validUndoSelection(selection), notify: true)
        guard shouldDeferGranularCountLayout else {
            reloadDataKeepingFocus()
            publishDocumentChange()
            return true
        }
        if !reconfigureVisibleReplacement(context.replacement, at: context.replacementIndex) {
            collectionView.reloadItems(at: [IndexPath(item: context.replacementIndex, section: 0)])
            collectionView.layoutSubtreeIfNeeded()
        }
        if context.deletedBlockIDs.count == 1 {
            deleteVisibleBlock(at: context.deletionIndex, deletedBlockIDs: context.deletedBlockIDs)
        } else {
            reloadDataKeepingFocus()
        }
        publishDocumentChange()
        return true
    }
}
