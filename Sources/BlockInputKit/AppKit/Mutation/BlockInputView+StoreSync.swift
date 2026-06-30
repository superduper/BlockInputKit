import AppKit

extension BlockInputView {
    func syncDocumentStore(_ action: StoreSyncAction) {
        guard let documentStore else {
            return
        }
        guard canSynchronizeDocumentStore(action) else {
            return
        }
        if syncMoveBlockAndReplaceChangedBlocks(action, documentStore: documentStore) {
            return
        }
        if syncMoveBlockAndApplyMarkerTransaction(action, documentStore: documentStore) {
            return
        }
        if syncSimpleDocumentStoreAction(action, documentStore: documentStore) {
            publishDocumentMutation(action.documentChange(document: document))
        }
    }

    private func syncSimpleDocumentStoreAction(
        _ action: StoreSyncAction,
        documentStore: BlockInputDocumentStore
    ) -> Bool {
        switch action {
        case .replaceDocument:
            documentStore.replaceDocument(document)
        case let .replaceBlock(block):
            documentStore.replaceBlock(block)
        case let .insertBlocks(blocks, insertionIndex):
            documentStore.insertBlocks(blocks, at: insertionIndex)
        case let .deleteBlocks(blockIDs):
            documentStore.deleteBlocks(withIDs: blockIDs)
        case let .moveBlock(blockID, targetIndex):
            documentStore.moveBlock(withID: blockID, to: targetIndex)
        case let .numberedListMarkerTransaction(transaction):
            guard let markerStore = documentStore as? BlockInputMarkerAdjustingStore else {
                return false
            }
            markerStore.applyNumberedListMarkerTransaction(transaction)
        case .moveBlockAndReplaceChangedBlocks, .moveBlockAndApplyMarkerTransaction:
            return false
        }
        return true
    }

    private func syncMoveBlockAndReplaceChangedBlocks(
        _ action: StoreSyncAction,
        documentStore: BlockInputDocumentStore
    ) -> Bool {
        guard case let .moveBlockAndReplaceChangedBlocks(blockID, targetIndex, changedBlocks) = action else {
            return false
        }
        if let markerStore = documentStore as? BlockInputMarkerAdjustingStore {
            markerStore.moveBlockWithoutNormalizing(withID: blockID, to: targetIndex)
        } else {
            documentStore.moveBlock(withID: blockID, to: targetIndex)
        }
        publishDocumentMutation(.moveBlock(blockID, index: targetIndex))
        for block in changedBlocks {
            documentStore.replaceBlock(block)
            publishDocumentMutation(.replaceBlock(block))
        }
        return true
    }

    private func syncMoveBlockAndApplyMarkerTransaction(
        _ action: StoreSyncAction,
        documentStore: BlockInputDocumentStore
    ) -> Bool {
        guard case let .moveBlockAndApplyMarkerTransaction(blockID, targetIndex, transaction) = action else {
            return false
        }
        guard let markerStore = documentStore as? BlockInputMarkerAdjustingStore else {
            return true
        }
        markerStore.moveBlockWithoutNormalizing(withID: blockID, to: targetIndex)
        publishDocumentMutation(.moveBlock(blockID, index: targetIndex))
        markerStore.applyNumberedListMarkerTransaction(transaction)
        publishDocumentMutation(.numberedListMarkersChanged(transaction))
        return true
    }

    func changedBlocksByID(
        before beforeDocument: BlockInputDocument,
        after afterDocument: BlockInputDocument
    ) -> [BlockInputBlock] {
        var beforeBlocksByID: [BlockInputBlockID: BlockInputBlock] = [:]
        for block in beforeDocument.blocks where beforeBlocksByID[block.id] == nil {
            beforeBlocksByID[block.id] = block
        }
        return afterDocument.blocks.filter { beforeBlocksByID[$0.id] != $0 }
    }
}

extension BlockInputView.StoreSyncAction {
    func documentChange(document: BlockInputDocument) -> BlockInputDocumentChange {
        switch self {
        case .replaceDocument:
            return .replaceDocument(document)
        case let .replaceBlock(block):
            return .replaceBlock(block)
        case let .insertBlocks(blocks, insertionIndex):
            return .insertBlocks(blocks, index: insertionIndex)
        case let .deleteBlocks(blockIDs):
            return .deleteBlocks(blockIDs)
        case let .moveBlock(blockID, targetIndex),
             let .moveBlockAndReplaceChangedBlocks(blockID, targetIndex, _):
            return .moveBlock(blockID, index: targetIndex)
        case let .numberedListMarkerTransaction(transaction):
            return .numberedListMarkersChanged(transaction)
        case let .moveBlockAndApplyMarkerTransaction(blockID, targetIndex, _):
            return .moveBlock(blockID, index: targetIndex)
        }
    }
}

extension BlockInputView {
    func canSynchronizeDocumentStore(_ action: StoreSyncAction) -> Bool {
        guard case .replaceDocument = action,
              let documentStore else {
            return true
        }
        return documentStore.isComplete
    }

    func defaultStoreSyncAction(for result: BlockInputUndoResult) -> StoreSyncAction {
        if result.replacedBlock != nil,
           result.insertedBlocks != nil || result.deletedBlockIDs != nil {
            return .replaceDocument
        }
        if let replacedBlock = result.replacedBlock {
            return .replaceBlock(replacedBlock)
        }
        if let insertedBlocks = result.insertedBlocks,
           let insertionIndex = result.insertionIndex {
            return .insertBlocks(insertedBlocks, insertionIndex: insertionIndex)
        }
        if let deletedBlockIDs = result.deletedBlockIDs {
            return .deleteBlocks(deletedBlockIDs)
        }
        return .replaceDocument
    }
}
