import AppKit

public extension BlockInputView {
    /// Toggles the active checklist item, or a specific checklist item by ID.
    ///
    /// The edit is recorded on the structural undo stack because it changes block
    /// metadata rather than the block's owned text.
    @discardableResult
    func toggleChecklistItem(blockID: BlockInputBlockID? = nil) -> BlockInputSelection? {
        guard isEditable,
              let targetBlockID = blockID ?? activeBlockID,
              let index = index(of: targetBlockID),
              let beforeBlock = block(at: index),
              case let .checklistItem(isChecked) = beforeBlock.kind else {
            return nil
        }
        let beforeSelection = selection
        var afterBlock = beforeBlock
        afterBlock.kind = .checklistItem(isChecked: !isChecked)
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: targetBlockID,
            utf16Offset: afterBlock.utf16Length
        ))

        syncDocumentStore(.replaceBlock(afterBlock))
        _ = replaceCachedBlock(afterBlock, at: index)
        applySelection(afterSelection, notify: true)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: "Toggle Checklist",
            beforeBlock: beforeBlock,
            afterBlock: afterBlock,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        if !reconfigureVisibleReplacement(afterBlock, at: index),
           !shouldDeferGranularCountLayout {
            collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
            collectionView.layoutSubtreeIfNeeded()
            restoreMountedSelection()
        }
        publishDocumentChange()
        return afterSelection
    }
}
