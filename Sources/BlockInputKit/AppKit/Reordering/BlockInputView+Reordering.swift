import Foundation

extension BlockInputView {
    func moveStoreBackedLargeListBlock(
        blockID: BlockInputBlockID,
        to targetIndex: Int
    ) -> BlockInputSelection? {
        guard isEditable,
              documentStore != nil,
              blockCount > largeDocumentCacheMutationLimit,
              let sourceIndex = index(of: blockID) else {
            return nil
        }
        let finalTargetIndex = min(max(targetIndex, 0), blockCount - 1)
        guard finalTargetIndex != sourceIndex else {
            return nil
        }
        guard let move = boundedListMove(
            blockID: blockID,
            sourceIndex: sourceIndex,
            targetIndex: finalTargetIndex
        ) else {
            return nil
        }

        let selectionBefore = selection
        let selectionAfter = move.result.selection
        let markerTransaction = numberedListMoveMarkerTransaction(
            sourceIndex: sourceIndex,
            targetIndex: finalTargetIndex
        )
        syncLargeListMove(blockID: blockID, targetIndex: finalTargetIndex, move: move, markerTransaction: markerTransaction)
        markDocumentCacheUnsynchronized()
        applySelection(selectionAfter, notify: true)
        registerLargeListMoveUndo(
            LargeListMoveUndoContext(
                blockID: blockID,
                sourceIndex: sourceIndex,
                targetIndex: finalTargetIndex,
                move: move,
                markerTransaction: markerTransaction,
                selectionBefore: selectionBefore,
                selectionAfter: selectionAfter
            )
        )
        applyGranularMoveLayout(
            sourceIndex: sourceIndex,
            targetIndex: finalTargetIndex,
            changedBlocks: move.afterChangedBlocks
        )
        publishDocumentChange()
        return selectionAfter
    }

    private func syncLargeListMove(
        blockID: BlockInputBlockID,
        targetIndex: Int,
        move: BoundedListMove,
        markerTransaction: BlockInputNumberedListMarkerTransaction?
    ) {
        if let markerTransaction,
           documentStore is BlockInputMarkerAdjustingStore {
            syncDocumentStore(.moveBlockAndApplyMarkerTransaction(
                blockID,
                targetIndex: targetIndex,
                transaction: markerTransaction
            ))
            return
        }
        syncDocumentStore(.moveBlockAndReplaceChangedBlocks(
            blockID,
            targetIndex: targetIndex,
            changedBlocks: move.afterChangedBlocks
        ))
    }

    private func registerLargeListMoveUndo(_ context: LargeListMoveUndoContext) {
        let beforeMarkerTransaction = context.markerTransaction.flatMap { _ in
            numberedListUndoMoveMarkerTransaction(
                blockID: context.blockID,
                sourceIndex: context.sourceIndex,
                targetIndex: context.targetIndex
            )
        }
        undoController?.registerBlockMoveStructuralEdit(BlockInputMoveEdit(
            actionName: "Move Block",
            blockID: context.blockID,
            beforeIndex: context.sourceIndex,
            afterIndex: context.targetIndex,
            beforeChangedBlocks: context.move.beforeChangedBlocks,
            afterChangedBlocks: context.move.afterChangedBlocks,
            beforeMarkerTransaction: beforeMarkerTransaction,
            afterMarkerTransaction: context.markerTransaction,
            selectionBefore: context.selectionBefore,
            selectionAfter: context.selectionAfter
        ))
    }
}

private struct LargeListMoveUndoContext {
    var blockID: BlockInputBlockID
    var sourceIndex: Int
    var targetIndex: Int
    var move: BoundedListMove
    var markerTransaction: BlockInputNumberedListMarkerTransaction?
    var selectionBefore: BlockInputSelection?
    var selectionAfter: BlockInputSelection
}

extension BlockInputView {
    func applyGranularMoveUndo(
        blockID: BlockInputBlockID,
        to targetIndex: Int,
        changedBlocks: [BlockInputBlock],
        markerTransaction: BlockInputNumberedListMarkerTransaction? = nil,
        selection: BlockInputSelection?
    ) -> Bool {
        guard let sourceIndex = index(of: blockID) else {
            return false
        }
        if let markerTransaction,
           documentStore is BlockInputMarkerAdjustingStore {
            syncDocumentStore(.moveBlockAndApplyMarkerTransaction(
                blockID,
                targetIndex: targetIndex,
                transaction: markerTransaction
            ))
        } else {
            syncDocumentStore(.moveBlockAndReplaceChangedBlocks(
                blockID,
                targetIndex: targetIndex,
                changedBlocks: changedBlocks
            ))
        }
        if documentStore != nil {
            markDocumentCacheUnsynchronized()
        } else {
            _ = document.moveBlock(blockID: blockID, to: targetIndex)
            for block in changedBlocks {
                if let index = document.index(of: block.id) {
                    document.blocks[index] = block
                }
            }
        }
        applySelection(validUndoSelection(selection), notify: true)
        applyGranularMoveLayout(
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            changedBlocks: changedBlocks
        )
        publishDocumentChange()
        return true
    }

    private func applyGranularMoveLayout(
        sourceIndex: Int,
        targetIndex: Int,
        changedBlocks: [BlockInputBlock]
    ) {
        guard shouldDeferGranularCountLayout else {
            reloadDataKeepingFocus()
            return
        }
        reconfigureMountedBlocksAfterGranularMove(
            sourceIndex: sourceIndex,
            targetIndex: targetIndex
        )
        for block in changedBlocks {
            if let index = index(of: block.id) {
                _ = reconfigureVisibleReplacement(block, at: index)
            }
        }
        restoreMountedSelection()
    }

    private func reconfigureMountedBlocksAfterGranularMove(
        sourceIndex: Int,
        targetIndex: Int
    ) {
        let affectedRange = min(sourceIndex, targetIndex)...max(sourceIndex, targetIndex)
        let indexedItems = collectionView.visibleItems().compactMap { item -> (index: Int, item: BlockInputBlockItem)? in
            guard let blockItem = item as? BlockInputBlockItem,
                  let itemIndex = collectionView.indexPath(for: item)?.item,
                  affectedRange.contains(itemIndex),
                  let block = block(at: itemIndex) else {
                return nil
            }
            blockItem.configure(
                block: block,
                allowsReordering: allowsBlockReordering,
                editorHorizontalInset: editorHorizontalInset,
                accentColor: dropIndicatorColor,
                style: style,
                imageLoadingContext: imageLoadingContext,
                fileBaseURL: fileBaseURL,
                isEditable: isEditable,
                disabledCursor: disabledCursor,
                showsInlineLinkOpenIcon: showsInlineLinkOpenButton,
                isSelected: isBlockSelected(block.id),
                delegate: self
            )
            resizeVisibleItem(blockItem, for: block)
            return (itemIndex, blockItem)
        }.sorted { $0.index < $1.index }
        guard let first = indexedItems.first else {
            return
        }
        reflowVisibleItemsAfterHeightChange(startingAt: first.index)
    }

    private func boundedListMove(
        blockID: BlockInputBlockID,
        sourceIndex: Int,
        targetIndex: Int
    ) -> BoundedListMove? {
        let lowerBound = min(sourceIndex, targetIndex)
        let upperBound = max(sourceIndex, targetIndex)
        guard let sourceBlock = block(at: sourceIndex),
              sourceBlock.id == blockID,
              sourceBlock.kind.isListItem else {
            return nil
        }
        for index in lowerBound...upperBound {
            guard block(at: index)?.kind.isListItem == true else {
                return nil
            }
        }

        let windowStart = previousListSeedIndex(before: lowerBound) ?? lowerBound
        let windowBlocks = (windowStart...upperBound).compactMap { block(at: $0) }
        guard windowBlocks.count == upperBound - windowStart + 1 else {
            return nil
        }

        var blocksByID: [BlockInputBlockID: BlockInputBlock] = [:]
        for block in windowBlocks where blocksByID[block.id] == nil {
            blocksByID[block.id] = block
        }
        var windowDocument = BlockInputDocument(blocks: windowBlocks)
        guard let result = windowDocument.moveBlockWithChangedBlocks(
            sourceIndex: sourceIndex - windowStart,
            to: targetIndex - windowStart
        ) else {
            return nil
        }
        let beforeChangedBlocks = result.changedBlocks.compactMap { blocksByID[$0.id] }
        guard beforeChangedBlocks.count == result.changedBlocks.count else {
            return nil
        }
        return BoundedListMove(
            result: result,
            beforeChangedBlocks: beforeChangedBlocks,
            afterChangedBlocks: result.changedBlocks
        )
    }

    private func numberedListMoveMarkerTransaction(
        sourceIndex: Int,
        targetIndex: Int
    ) -> BlockInputNumberedListMarkerTransaction? {
        guard sourceIndex != targetIndex,
              let sourceBlock = block(at: sourceIndex),
              case let .numberedListItem(sourceStart) = sourceBlock.kind,
              sourceBlock.indentationLevel(forLine: 0) == 0 else {
            return nil
        }
        let lowerBound = min(sourceIndex, targetIndex)
        let upperBound = max(sourceIndex, targetIndex)
        for index in lowerBound...upperBound {
            guard let block = block(at: index),
                  case let .numberedListItem(start) = block.kind,
                  start == index + 1,
                  block.indentationLevel(forLine: 0) == 0 else {
                return nil
            }
        }
        let shiftedRange: ClosedRange<Int>
        let delta: Int
        if sourceIndex < targetIndex {
            shiftedRange = sourceIndex...(targetIndex - 1)
            delta = -1
        } else {
            shiftedRange = (targetIndex + 1)...sourceIndex
            delta = 1
        }
        return BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: shiftedRange.lowerBound,
                    endIndex: shiftedRange.upperBound,
                    indentationLevel: 0,
                    delta: delta
                )
            ],
            overrides: [
                BlockInputNumberedListMarkerOverride(
                    blockID: sourceBlock.id,
                    start: targetIndex + 1,
                    previousStart: sourceStart
                )
            ]
        )
    }

    private func numberedListUndoMoveMarkerTransaction(
        blockID: BlockInputBlockID,
        sourceIndex: Int,
        targetIndex: Int
    ) -> BlockInputNumberedListMarkerTransaction? {
        guard sourceIndex != targetIndex else {
            return nil
        }
        let shiftedRange: ClosedRange<Int>
        let delta: Int
        if sourceIndex < targetIndex {
            shiftedRange = (sourceIndex + 1)...targetIndex
            delta = 1
        } else {
            shiftedRange = targetIndex...(sourceIndex - 1)
            delta = -1
        }
        return BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: shiftedRange.lowerBound,
                    endIndex: shiftedRange.upperBound,
                    indentationLevel: 0,
                    delta: delta
                )
            ],
            overrides: [
                BlockInputNumberedListMarkerOverride(
                    blockID: blockID,
                    start: sourceIndex + 1,
                    previousStart: targetIndex + 1
                )
            ]
        )
    }

    private func previousListSeedIndex(before index: Int) -> Int? {
        guard index > 0,
              block(at: index - 1)?.kind.isListItem == true else {
            return nil
        }
        return index - 1
    }
}

private struct BoundedListMove {
    var result: BlockInputMoveResult
    var beforeChangedBlocks: [BlockInputBlock]
    var afterChangedBlocks: [BlockInputBlock]
}

private extension BlockInputBlockKind {
    var isListItem: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }
}
