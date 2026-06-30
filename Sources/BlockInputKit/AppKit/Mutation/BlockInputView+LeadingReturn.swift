import AppKit

extension BlockInputView {
    struct LeadingReturnMove {
        var afterBlock: BlockInputBlock
        var insertedBlock: BlockInputBlock
    }

    private struct LeadingReturnNumberingChanges {
        var beforeChangedBlocks: [BlockInputBlock]
        var afterChangedBlocks: [BlockInputBlock]
        var beforeMarkerTransaction: BlockInputNumberedListMarkerTransaction?
        var afterMarkerTransaction: BlockInputNumberedListMarkerTransaction?
    }

    func leadingReturnMove(
        from block: BlockInputBlock,
        selection: ReturnSelection?
    ) -> LeadingReturnMove? {
        guard (selection?.length ?? 0) == 0,
              (selection?.offset ?? block.utf16Length) == 0,
              block.canMoveDownOnLeadingReturn else {
            return nil
        }
        return LeadingReturnMove(
            afterBlock: block.leadingReturnPlaceholder(),
            insertedBlock: block.blockMovedDownOnLeadingReturn()
        )
    }

    func performGranularLeadingReturnMove(
        actionName: String,
        beforeBlock: BlockInputBlock,
        leadingReturnMove: LeadingReturnMove,
        replacementIndex: Int
    ) -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        let afterBlock = leadingReturnMove.afterBlock
        let insertedBlocks = [leadingReturnMove.insertedBlock]
        let insertionIndex = replacementIndex + 1
        let beforeSelection = selection
        guard let numberingChanges = prepareLeadingReturnNumberingChanges(
            beforeBlock: beforeBlock,
            leadingReturnMove: leadingReturnMove,
            insertionIndex: insertionIndex,
            replacementIndex: replacementIndex
        ) else {
            return nil
        }
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: afterBlock.id,
            utf16Offset: 0
        ))
        syncDocumentStore(.replaceBlock(afterBlock))
        syncDocumentStore(.insertBlocks(insertedBlocks, insertionIndex: insertionIndex))
        if let markerTransaction = numberingChanges.afterMarkerTransaction {
            syncDocumentStore(.numberedListMarkerTransaction(markerTransaction))
        } else {
            numberingChanges.afterChangedBlocks.forEach { syncDocumentStore(.replaceBlock($0)) }
        }
        applySelection(afterSelection, notify: true)
        undoController?.registerBlockReplacementInsertionStructuralEdit(BlockInputReplaceInsertEdit(
            actionName: actionName,
            beforeBlock: beforeBlock,
            afterBlock: afterBlock,
            insertedBlocks: insertedBlocks,
            insertionIndex: insertionIndex,
            beforeChangedBlocks: numberingChanges.beforeChangedBlocks,
            afterChangedBlocks: numberingChanges.afterChangedBlocks,
            beforeMarkerTransaction: numberingChanges.beforeMarkerTransaction,
            afterMarkerTransaction: numberingChanges.afterMarkerTransaction,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        ))
        if shouldDeferGranularCountLayout {
            reloadVisibleBlock(at: replacementIndex)
            insertVisibleBlock(at: insertionIndex)
        } else {
            reloadDataKeepingFocus()
        }
        publishDocumentChange()
        return afterSelection
    }

    private func prepareLeadingReturnNumberingChanges(
        beforeBlock: BlockInputBlock,
        leadingReturnMove: LeadingReturnMove,
        insertionIndex: Int,
        replacementIndex: Int
    ) -> LeadingReturnNumberingChanges? {
        let insertedBlock = leadingReturnMove.insertedBlock
        let insertedBlocks = [insertedBlock]
        guard canSynchronizeCacheForGranularInsertion(insertedBlockCount: insertedBlocks.count) else {
            if let markerChanges = leadingReturnMarkerTransaction(
                beforeBlock: beforeBlock,
                insertedBlock: insertedBlock,
                replacementIndex: replacementIndex
            ) {
                markDocumentCacheUnsynchronized()
                return markerChanges
            }
            let changes = leadingReturnNumberingChanges(
                beforeBlock: beforeBlock,
                afterBlock: leadingReturnMove.afterBlock,
                insertedBlock: insertedBlock,
                replacementIndex: replacementIndex
            )
            if changes != nil {
                markDocumentCacheUnsynchronized()
            }
            return changes
        }

        let beforeDocument = document
        guard replaceCachedBlock(leadingReturnMove.afterBlock, at: replacementIndex),
              document.insertBlocks(insertedBlocks, at: insertionIndex) != nil else {
            return nil
        }
        let afterChangedBlocks = document.normalizeNumberedListStartsAround(replacementIndex)
        let changedBlockIDs = Set(afterChangedBlocks.map(\.id))
        return LeadingReturnNumberingChanges(
            beforeChangedBlocks: beforeDocument.blocks.filter { changedBlockIDs.contains($0.id) },
            afterChangedBlocks: afterChangedBlocks
        )
    }

    private func leadingReturnMarkerTransaction(
        beforeBlock: BlockInputBlock,
        insertedBlock: BlockInputBlock,
        replacementIndex: Int
    ) -> LeadingReturnNumberingChanges? {
        guard documentStore is BlockInputMarkerAdjustingStore,
              case let .numberedListItem(start) = beforeBlock.kind else {
            return nil
        }
        let indentationLevel = beforeBlock.indentationLevel(forLine: 0)
        let insertedIndex = replacementIndex + 1
        let afterTransaction = BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: insertedIndex + 1,
                    endIndex: nil,
                    listRunStartIndex: replacementIndex,
                    indentationLevel: indentationLevel,
                    delta: 1
                )
            ],
            overrides: [
                BlockInputNumberedListMarkerOverride(
                    blockID: insertedBlock.id,
                    start: start + 1,
                    previousStart: start + 1
                )
            ]
        )
        return LeadingReturnNumberingChanges(
            beforeChangedBlocks: [],
            afterChangedBlocks: [],
            beforeMarkerTransaction: afterTransaction.inverted,
            afterMarkerTransaction: afterTransaction
        )
    }

    private func leadingReturnNumberingChanges(
        beforeBlock: BlockInputBlock,
        afterBlock: BlockInputBlock,
        insertedBlock: BlockInputBlock,
        replacementIndex: Int
    ) -> LeadingReturnNumberingChanges? {
        guard beforeBlock.kind.isLeadingReturnNumberedListItem else {
            return LeadingReturnNumberingChanges(beforeChangedBlocks: [], afterChangedBlocks: [])
        }

        let windowStart = previousLeadingReturnListSeedIndex(
            before: replacementIndex,
            targetIndentationLevel: beforeBlock.indentationLevel(forLine: 0)
        ) ?? replacementIndex
        var beforeWindowBlocks: [BlockInputBlock] = []
        var afterWindowBlocks: [BlockInputBlock] = []
        var index = windowStart
        while index < replacementIndex {
            guard let block = block(at: index), block.kind.isLeadingReturnListItem else {
                return nil
            }
            beforeWindowBlocks.append(block)
            afterWindowBlocks.append(block)
            index += 1
        }

        guard let sourceBlock = block(at: replacementIndex), sourceBlock.id == beforeBlock.id else {
            return nil
        }
        beforeWindowBlocks.append(sourceBlock)
        afterWindowBlocks.append(afterBlock)
        afterWindowBlocks.append(insertedBlock)

        let count = blockCount
        var followingIndex = replacementIndex + 1
        while followingIndex < count {
            guard let block = block(at: followingIndex), block.kind.isLeadingReturnListItem else {
                break
            }
            beforeWindowBlocks.append(block)
            afterWindowBlocks.append(block)
            followingIndex += 1
        }

        var afterDocument = BlockInputDocument(blocks: afterWindowBlocks)
        let changedBlocks = afterDocument.normalizeNumberedListStartsAround(replacementIndex - windowStart)
        let existingChangedBlocks = changedBlocks.filter { $0.id != insertedBlock.id }
        var beforeBlocksByID: [BlockInputBlockID: BlockInputBlock] = [:]
        for block in beforeWindowBlocks where beforeBlocksByID[block.id] == nil {
            beforeBlocksByID[block.id] = block
        }
        let beforeChangedBlocks = existingChangedBlocks.compactMap { beforeBlocksByID[$0.id] }
        guard beforeChangedBlocks.count == existingChangedBlocks.count else {
            return nil
        }
        return LeadingReturnNumberingChanges(
            beforeChangedBlocks: beforeChangedBlocks,
            afterChangedBlocks: changedBlocks
        )
    }

    private func previousLeadingReturnListSeedIndex(
        before index: Int,
        targetIndentationLevel: Int
    ) -> Int? {
        guard index > 0 else {
            return nil
        }
        var previousIndex = index - 1
        while previousIndex >= 0 {
            guard let previousBlock = block(at: previousIndex),
                  previousBlock.kind.isLeadingReturnListItem else {
                return nil
            }
            if previousBlock.indentationLevel(forLine: 0) <= targetIndentationLevel {
                return previousIndex
            }
            previousIndex -= 1
        }
        return nil
    }
}

private extension BlockInputBlockKind {
    var isLeadingReturnListItem: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }

    var isLeadingReturnNumberedListItem: Bool {
        switch self {
        case .numberedListItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .bulletedListItem, .checklistItem,
             .table, .image, .rawMarkdown:
            return false
        }
    }
}
