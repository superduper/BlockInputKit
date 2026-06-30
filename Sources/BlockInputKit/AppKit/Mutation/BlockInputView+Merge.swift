import AppKit

public extension BlockInputView {
    /// Merges a paragraph block into the previous block.
    @discardableResult
    func mergeBlockIntoPrevious(blockID: BlockInputBlockID) -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        refreshDocumentFromStore()
        guard let index = index(of: blockID),
              index > 0,
              let currentBlock = block(at: index),
              let previousBlock = block(at: index - 1),
              currentBlock.kind == .paragraph,
              previousBlock.kind.isSelectableStandaloneBlock == false,
              previousBlock.kind != .frontMatter else {
            return nil
        }
        let beforeSelection = selection
        var mergedPreviousBlock = previousBlock
        let cursorOffset = previousBlock.utf16Length
        mergedPreviousBlock.text += currentBlock.text
        syncDocumentStore(.replaceBlock(mergedPreviousBlock))
        syncDocumentStore(.deleteBlocks([blockID]))
        if canSynchronizeCacheForGranularDeletion(deletedBlockCount: 1),
           replaceCachedBlock(mergedPreviousBlock, at: index - 1) {
            document.blocks.remove(at: index)
        } else {
            markDocumentCacheUnsynchronized()
        }
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: previousBlock.id,
            utf16Offset: cursorOffset
        ))
        applySelection(afterSelection, notify: true)
        undoController?.registerBlockReplacementDeletionStructuralEdit(BlockInputReplaceDeleteEdit(
            actionName: "Merge Blocks",
            beforeBlock: previousBlock,
            afterBlock: mergedPreviousBlock,
            deletedBlocks: [currentBlock],
            deletionIndex: index,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        ))
        reloadDataKeepingFocus()
        publishDocumentChange()
        return afterSelection
    }
}
