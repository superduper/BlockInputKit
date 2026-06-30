import AppKit

extension BlockInputView {
    struct ReturnInsertionNumberingChanges {
        var beforeChangedBlocks: [BlockInputBlock]
        var afterChangedBlocks: [BlockInputBlock]
        var beforeMarkerTransaction: BlockInputNumberedListMarkerTransaction?
        var afterMarkerTransaction: BlockInputNumberedListMarkerTransaction?
    }

    func prepareReturnInsertionNumberingChanges(
        sourceBlock: BlockInputBlock,
        sourceIndex: Int,
        insertedBlock: BlockInputBlock,
        insertedBlocks: [BlockInputBlock],
        insertionIndex: Int
    ) -> ReturnInsertionNumberingChanges? {
        let isNumberedInsertion: Bool
        if case .numberedListItem = insertedBlock.kind {
            isNumberedInsertion = true
        } else {
            isNumberedInsertion = false
        }
        guard canSynchronizeCacheForGranularInsertion(insertedBlockCount: insertedBlocks.count) else {
            if isNumberedInsertion,
               let markerChanges = returnInsertionMarkerTransaction(
                   sourceBlock: sourceBlock,
                   insertedBlock: insertedBlock,
                   sourceIndex: sourceIndex,
                   insertionIndex: insertionIndex
               ) {
                markDocumentCacheUnsynchronized()
                return markerChanges
            }
            if !isNumberedInsertion {
                markDocumentCacheUnsynchronized()
                return ReturnInsertionNumberingChanges(beforeChangedBlocks: [], afterChangedBlocks: [])
            }
            if let fallbackChanges = returnInsertionNumberingChanges(
                sourceIndex: sourceIndex,
                insertedBlock: insertedBlock,
                insertionIndex: insertionIndex
            ) {
                markDocumentCacheUnsynchronized()
                return fallbackChanges
            }
            return nil
        }

        let beforeDocument = document
        guard document.insertBlocks(insertedBlocks, at: insertionIndex) != nil else {
            return nil
        }
        guard isNumberedInsertion else {
            return ReturnInsertionNumberingChanges(beforeChangedBlocks: [], afterChangedBlocks: [])
        }
        let afterChangedBlocks = document.normalizeNumberedListStartsAround(insertionIndex)
        let changedBlockIDs = Set(afterChangedBlocks.map(\.id))
        return ReturnInsertionNumberingChanges(
            beforeChangedBlocks: beforeDocument.blocks.filter { changedBlockIDs.contains($0.id) },
            afterChangedBlocks: afterChangedBlocks
        )
    }

    private func returnInsertionMarkerTransaction(
        sourceBlock: BlockInputBlock,
        insertedBlock: BlockInputBlock,
        sourceIndex: Int,
        insertionIndex: Int
    ) -> ReturnInsertionNumberingChanges? {
        guard documentStore is BlockInputMarkerAdjustingStore,
              case let .numberedListItem(insertedStart) = insertedBlock.kind else {
            return nil
        }
        let indentationLevel = sourceBlock.indentationLevel(forLine: 0)
        let afterTransaction = BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: insertionIndex + 1,
                    endIndex: nil,
                    listRunStartIndex: sourceIndex,
                    indentationLevel: indentationLevel,
                    delta: 1
                )
            ],
            overrides: [
                BlockInputNumberedListMarkerOverride(
                    blockID: insertedBlock.id,
                    start: insertedStart,
                    previousStart: insertedStart
                )
            ]
        )
        return ReturnInsertionNumberingChanges(
            beforeChangedBlocks: [],
            afterChangedBlocks: [],
            beforeMarkerTransaction: afterTransaction.inverted,
            afterMarkerTransaction: afterTransaction
        )
    }

    private func returnInsertionNumberingChanges(
        sourceIndex: Int,
        insertedBlock: BlockInputBlock,
        insertionIndex: Int
    ) -> ReturnInsertionNumberingChanges? {
        let windowStart = returnInsertionListWindowStart(containing: sourceIndex)
        var beforeWindowBlocks: [BlockInputBlock] = []
        var afterWindowBlocks: [BlockInputBlock] = []
        var index = windowStart
        while index <= sourceIndex {
            guard let block = block(at: index),
                  block.kind.isReturnInsertionListItem else {
                return nil
            }
            beforeWindowBlocks.append(block)
            afterWindowBlocks.append(block)
            index += 1
        }
        afterWindowBlocks.append(insertedBlock)

        var followingIndex = insertionIndex
        while followingIndex < blockCount {
            guard let block = block(at: followingIndex),
                  block.kind.isReturnInsertionListItem else {
                break
            }
            beforeWindowBlocks.append(block)
            afterWindowBlocks.append(block)
            followingIndex += 1
        }

        var afterDocument = BlockInputDocument(blocks: afterWindowBlocks)
        let changedBlocks = afterDocument.normalizeNumberedListStartsAround(insertionIndex - windowStart)
        let existingChangedBlocks = changedBlocks.filter { $0.id != insertedBlock.id }
        var beforeBlocksByID: [BlockInputBlockID: BlockInputBlock] = [:]
        for block in beforeWindowBlocks where beforeBlocksByID[block.id] == nil {
            beforeBlocksByID[block.id] = block
        }
        let beforeChangedBlocks = existingChangedBlocks.compactMap { beforeBlocksByID[$0.id] }
        guard beforeChangedBlocks.count == existingChangedBlocks.count else {
            return nil
        }
        return ReturnInsertionNumberingChanges(
            beforeChangedBlocks: beforeChangedBlocks,
            afterChangedBlocks: changedBlocks
        )
    }

    private func returnInsertionListWindowStart(containing index: Int) -> Int {
        var lowerBound = index
        while lowerBound > 0 {
            guard let previousBlock = block(at: lowerBound - 1),
                  previousBlock.kind.isReturnInsertionListItem else {
                break
            }
            lowerBound -= 1
        }
        return lowerBound
    }
}

private extension BlockInputBlockKind {
    var isReturnInsertionListItem: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }
}
