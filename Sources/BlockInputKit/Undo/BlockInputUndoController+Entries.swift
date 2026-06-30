import Foundation

struct BlockInputTextUndoEntry {
    let blockID: BlockInputBlockID
    let beforeText: String
    let afterText: String
    let beforeLineIndentationLevels: [Int]?
    let afterLineIndentationLevels: [Int]?
    let selectionBefore: BlockInputSelection?
    let selectionAfter: BlockInputSelection?
}

enum BlockInputHistoryOperation: Equatable {
    case text(BlockInputBlockID)
    case structural

    func canPerform(text: (BlockInputBlockID) -> Bool, structural: Bool) -> Bool {
        switch self {
        case .text(let blockID):
            return text(blockID)
        case .structural:
            return structural
        }
    }
}

struct BlockInputReplaceInsertEdit {
    var actionName: String
    var beforeBlock: BlockInputBlock
    var afterBlock: BlockInputBlock
    var insertedBlocks: [BlockInputBlock]
    var insertionIndex: Int
    var beforeChangedBlocks: [BlockInputBlock] = []
    var afterChangedBlocks: [BlockInputBlock] = []
    var beforeMarkerTransaction: BlockInputNumberedListMarkerTransaction?
    var afterMarkerTransaction: BlockInputNumberedListMarkerTransaction?
    var selectionBefore: BlockInputSelection?
    var selectionAfter: BlockInputSelection?
}

struct BlockInputReplaceDeleteEdit {
    var actionName: String
    var beforeBlock: BlockInputBlock
    var afterBlock: BlockInputBlock
    var deletedBlocks: [BlockInputBlock]
    var deletionIndex: Int
    var selectionBefore: BlockInputSelection?
    var selectionAfter: BlockInputSelection?
}

struct BlockInputMoveEdit {
    var actionName: String
    var blockID: BlockInputBlockID
    var beforeIndex: Int
    var afterIndex: Int
    var beforeChangedBlocks: [BlockInputBlock]
    var afterChangedBlocks: [BlockInputBlock]
    var beforeMarkerTransaction: BlockInputNumberedListMarkerTransaction?
    var afterMarkerTransaction: BlockInputNumberedListMarkerTransaction?
    var selectionBefore: BlockInputSelection?
    var selectionAfter: BlockInputSelection?
}

struct BlockInputMultiBlockReplacementEdit {
    var actionName: String
    var beforeBlocks: [BlockInputBlock]
    var afterBlocks: [BlockInputBlock]
    var selectionBefore: BlockInputSelection?
    var selectionAfter: BlockInputSelection?
}

struct BlockInputStructuralUndoEntry {
    let actionName: String
    let payload: BlockInputStructuralUndoPayload
    let selectionBefore: BlockInputSelection?
    let selectionAfter: BlockInputSelection?

    init(
        actionName: String,
        beforeDocument: BlockInputDocument,
        afterDocument: BlockInputDocument,
        selectionBefore: BlockInputSelection?,
        selectionAfter: BlockInputSelection?
    ) {
        self.actionName = actionName
        payload = .documentReplacement(beforeDocument: beforeDocument, afterDocument: afterDocument)
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
    }

    init(
        actionName: String,
        payload: BlockInputStructuralUndoPayload,
        selectionBefore: BlockInputSelection?,
        selectionAfter: BlockInputSelection?
    ) {
        self.actionName = actionName
        self.payload = payload
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
    }
}

enum BlockInputStructuralUndoPayload {
    case documentReplacement(beforeDocument: BlockInputDocument, afterDocument: BlockInputDocument)
    case blockReplacement(beforeBlock: BlockInputBlock, afterBlock: BlockInputBlock)
    case blockReplacementInsertion(
        beforeBlock: BlockInputBlock,
        afterBlock: BlockInputBlock,
        insertedBlocks: [BlockInputBlock],
        insertionIndex: Int,
        beforeChangedBlocks: [BlockInputBlock] = [],
        afterChangedBlocks: [BlockInputBlock] = [],
        beforeMarkerTransaction: BlockInputNumberedListMarkerTransaction? = nil,
        afterMarkerTransaction: BlockInputNumberedListMarkerTransaction? = nil
    )
    case blockReplacementDeletion(
        beforeBlock: BlockInputBlock,
        afterBlock: BlockInputBlock,
        deletedBlocks: [BlockInputBlock],
        deletionIndex: Int
    )
    case blockMove(
        blockID: BlockInputBlockID,
        beforeIndex: Int,
        afterIndex: Int,
        beforeChangedBlocks: [BlockInputBlock],
        afterChangedBlocks: [BlockInputBlock],
        beforeMarkerTransaction: BlockInputNumberedListMarkerTransaction? = nil,
        afterMarkerTransaction: BlockInputNumberedListMarkerTransaction? = nil
    )
    case blockInsertion(
        insertedBlocks: [BlockInputBlock],
        insertionIndex: Int,
        beforeChangedBlocks: [BlockInputBlock] = [],
        afterChangedBlocks: [BlockInputBlock] = [],
        beforeMarkerTransaction: BlockInputNumberedListMarkerTransaction? = nil,
        afterMarkerTransaction: BlockInputNumberedListMarkerTransaction? = nil
    )
    case blockDeletion(deletedBlocks: [BlockInputBlock], deletionIndex: Int)
    case multiBlockReplacement(beforeBlocks: [BlockInputBlock], afterBlocks: [BlockInputBlock])

    var replacementBlockForUndo: BlockInputBlock? {
        switch self {
        case let .blockReplacement(beforeBlock, _),
             let .blockReplacementInsertion(beforeBlock, _, _, _, _, _, _, _),
             let .blockReplacementDeletion(beforeBlock, _, _, _):
            return beforeBlock
        case .documentReplacement, .blockInsertion, .blockDeletion, .blockMove, .multiBlockReplacement:
            return nil
        }
    }

    var replacementBlockForRedo: BlockInputBlock? {
        switch self {
        case let .blockReplacement(_, afterBlock),
             let .blockReplacementInsertion(_, afterBlock, _, _, _, _, _, _),
             let .blockReplacementDeletion(_, afterBlock, _, _):
            return afterBlock
        case .documentReplacement, .blockInsertion, .blockDeletion, .blockMove, .multiBlockReplacement:
            return nil
        }
    }

    var replacementBlocksForUndo: [BlockInputBlock]? {
        switch self {
        case let .blockReplacementInsertion(_, _, _, _, beforeChangedBlocks, _, _, _):
            return beforeChangedBlocks
        case let .blockInsertion(_, _, beforeChangedBlocks, _, _, _):
            return beforeChangedBlocks
        case let .blockMove(_, _, _, beforeChangedBlocks, _, _, _):
            return beforeChangedBlocks
        case let .multiBlockReplacement(beforeBlocks, _):
            return beforeBlocks
        case .documentReplacement, .blockReplacement, .blockReplacementDeletion, .blockDeletion:
            return nil
        }
    }

    var replacementBlocksForRedo: [BlockInputBlock]? {
        switch self {
        case let .blockReplacementInsertion(_, _, _, _, _, afterChangedBlocks, _, _):
            return afterChangedBlocks
        case let .blockInsertion(_, _, _, afterChangedBlocks, _, _):
            return afterChangedBlocks
        case let .blockMove(_, _, _, _, afterChangedBlocks, _, _):
            return afterChangedBlocks
        case let .multiBlockReplacement(_, afterBlocks):
            return afterBlocks
        case .documentReplacement, .blockReplacement, .blockReplacementDeletion, .blockDeletion:
            return nil
        }
    }

    var deletedBlockIDsForUndo: [BlockInputBlockID]? {
        switch self {
        case let .blockInsertion(insertedBlocks, _, _, _, _, _),
             let .blockReplacementInsertion(_, _, insertedBlocks, _, _, _, _, _):
            return insertedBlocks.map(\.id)
        case .documentReplacement, .blockReplacement, .blockReplacementDeletion, .blockDeletion, .blockMove, .multiBlockReplacement:
            return nil
        }
    }

    var insertedBlocksForRedo: [BlockInputBlock]? {
        switch self {
        case let .blockInsertion(insertedBlocks, _, _, _, _, _),
             let .blockReplacementInsertion(_, _, insertedBlocks, _, _, _, _, _):
            return insertedBlocks
        case .documentReplacement, .blockReplacement, .blockReplacementDeletion, .blockDeletion, .blockMove, .multiBlockReplacement:
            return nil
        }
    }

    var insertionIndexForRedo: Int? {
        switch self {
        case let .blockInsertion(_, insertionIndex, _, _, _, _),
             let .blockReplacementInsertion(_, _, _, insertionIndex, _, _, _, _):
            return insertionIndex
        case .documentReplacement, .blockReplacement, .blockReplacementDeletion, .blockDeletion, .blockMove, .multiBlockReplacement:
            return nil
        }
    }

    var insertedBlocksForUndo: [BlockInputBlock]? {
        switch self {
        case let .blockDeletion(deletedBlocks, _),
             let .blockReplacementDeletion(_, _, deletedBlocks, _):
            return deletedBlocks
        case .documentReplacement, .blockReplacement, .blockReplacementInsertion, .blockInsertion, .blockMove, .multiBlockReplacement:
            return nil
        }
    }

    var insertionIndexForUndo: Int? {
        switch self {
        case let .blockDeletion(_, deletionIndex),
             let .blockReplacementDeletion(_, _, _, deletionIndex):
            return deletionIndex
        case .documentReplacement, .blockReplacement, .blockReplacementInsertion, .blockInsertion, .blockMove, .multiBlockReplacement:
            return nil
        }
    }

    var deletedBlockIDsForRedo: [BlockInputBlockID]? {
        switch self {
        case let .blockDeletion(deletedBlocks, _),
             let .blockReplacementDeletion(_, _, deletedBlocks, _):
            return deletedBlocks.map(\.id)
        case .documentReplacement, .blockReplacement, .blockReplacementInsertion, .blockInsertion, .blockMove, .multiBlockReplacement:
            return nil
        }
    }

    var movedBlockIDForUndo: BlockInputBlockID? {
        switch self {
        case let .blockMove(blockID, _, _, _, _, _, _):
            return blockID
        case .documentReplacement, .blockReplacement, .blockReplacementInsertion, .blockReplacementDeletion, .blockInsertion, .blockDeletion,
             .multiBlockReplacement:
            return nil
        }
    }

    var moveIndexForUndo: Int? {
        switch self {
        case let .blockMove(_, beforeIndex, _, _, _, _, _):
            return beforeIndex
        case .documentReplacement, .blockReplacement, .blockReplacementInsertion, .blockReplacementDeletion, .blockInsertion, .blockDeletion,
             .multiBlockReplacement:
            return nil
        }
    }

    var movedBlockIDForRedo: BlockInputBlockID? {
        switch self {
        case let .blockMove(blockID, _, _, _, _, _, _):
            return blockID
        case .documentReplacement, .blockReplacement, .blockReplacementInsertion, .blockReplacementDeletion, .blockInsertion, .blockDeletion,
             .multiBlockReplacement:
            return nil
        }
    }

    var moveIndexForRedo: Int? {
        switch self {
        case let .blockMove(_, _, afterIndex, _, _, _, _):
            return afterIndex
        case .documentReplacement, .blockReplacement, .blockReplacementInsertion, .blockReplacementDeletion, .blockInsertion, .blockDeletion,
             .multiBlockReplacement:
            return nil
        }
    }

    var canApplyGranularly: Bool {
        switch self {
        case .documentReplacement:
            return false
        case .blockReplacement, .blockReplacementInsertion, .blockReplacementDeletion, .blockInsertion, .blockDeletion, .blockMove,
             .multiBlockReplacement:
            return true
        }
    }

    func undoResult(selection: BlockInputSelection?, actionName: String) -> BlockInputUndoResult {
        BlockInputUndoResult(
            selection: selection,
            actionName: actionName,
            replacedBlock: replacementBlockForUndo,
            replacedBlocks: replacementBlocksForUndo,
            insertedBlocks: insertedBlocksForUndo,
            insertionIndex: insertionIndexForUndo,
            deletedBlockIDs: deletedBlockIDsForUndo,
            movedBlockID: movedBlockIDForUndo,
            moveIndex: moveIndexForUndo,
            markerTransaction: markerTransactionForUndo
        )
    }

    func redoResult(selection: BlockInputSelection?, actionName: String) -> BlockInputUndoResult {
        BlockInputUndoResult(
            selection: selection,
            actionName: actionName,
            replacedBlock: replacementBlockForRedo,
            replacedBlocks: replacementBlocksForRedo,
            insertedBlocks: insertedBlocksForRedo,
            insertionIndex: insertionIndexForRedo,
            deletedBlockIDs: deletedBlockIDsForRedo,
            movedBlockID: movedBlockIDForRedo,
            moveIndex: moveIndexForRedo,
            markerTransaction: markerTransactionForRedo
        )
    }

    var markerTransactionForUndo: BlockInputNumberedListMarkerTransaction? {
        switch self {
        case let .blockReplacementInsertion(_, _, _, _, _, _, beforeMarkerTransaction, _):
            return beforeMarkerTransaction
        case let .blockInsertion(_, _, _, _, beforeMarkerTransaction, _):
            return beforeMarkerTransaction
        case let .blockMove(_, _, _, _, _, beforeMarkerTransaction, _):
            return beforeMarkerTransaction
        case .documentReplacement, .blockReplacement, .blockReplacementDeletion, .blockDeletion, .multiBlockReplacement:
            return nil
        }
    }

    var markerTransactionForRedo: BlockInputNumberedListMarkerTransaction? {
        switch self {
        case let .blockReplacementInsertion(_, _, _, _, _, _, _, afterMarkerTransaction):
            return afterMarkerTransaction
        case let .blockInsertion(_, _, _, _, _, afterMarkerTransaction):
            return afterMarkerTransaction
        case let .blockMove(_, _, _, _, _, _, afterMarkerTransaction):
            return afterMarkerTransaction
        case .documentReplacement, .blockReplacement, .blockReplacementDeletion, .blockDeletion, .multiBlockReplacement:
            return nil
        }
    }

    func applyUndo(to document: inout BlockInputDocument) {
        switch self {
        case let .documentReplacement(beforeDocument, _):
            document = beforeDocument
        case let .blockReplacement(beforeBlock, _):
            replace(beforeBlock, in: &document)
        case let .blockReplacementInsertion(beforeBlock, _, insertedBlocks, _, beforeChangedBlocks, _, _, _):
            replace(beforeBlock, in: &document)
            replace(beforeChangedBlocks, in: &document)
            let insertedIDs = Set(insertedBlocks.map(\.id))
            document.blocks.removeAll { insertedIDs.contains($0.id) }
        case let .blockReplacementDeletion(beforeBlock, _, deletedBlocks, deletionIndex):
            replace(beforeBlock, in: &document)
            document.insertBlocks(deletedBlocks, at: deletionIndex)
        case let .blockInsertion(insertedBlocks, _, beforeChangedBlocks, _, _, _):
            replace(beforeChangedBlocks, in: &document)
            let insertedIDs = Set(insertedBlocks.map(\.id))
            document.blocks.removeAll { insertedIDs.contains($0.id) }
        case let .blockDeletion(deletedBlocks, deletionIndex):
            document.insertBlocks(deletedBlocks, at: deletionIndex)
        case let .blockMove(blockID, beforeIndex, _, beforeChangedBlocks, _, _, _):
            document.moveBlock(blockID: blockID, to: beforeIndex)
            replace(beforeChangedBlocks, in: &document)
        case let .multiBlockReplacement(beforeBlocks, _):
            replace(beforeBlocks, in: &document)
        }
    }

    func applyRedo(to document: inout BlockInputDocument) {
        switch self {
        case let .documentReplacement(_, afterDocument):
            document = afterDocument
        case let .blockReplacement(_, afterBlock):
            replace(afterBlock, in: &document)
        case let .blockReplacementInsertion(_, afterBlock, insertedBlocks, insertionIndex, _, afterChangedBlocks, _, _):
            replace(afterBlock, in: &document)
            document.insertBlocks(insertedBlocks, at: insertionIndex)
            replace(afterChangedBlocks, in: &document)
        case let .blockReplacementDeletion(_, afterBlock, deletedBlocks, _):
            replace(afterBlock, in: &document)
            let deletedIDs = Set(deletedBlocks.map(\.id))
            document.blocks.removeAll { deletedIDs.contains($0.id) }
        case let .blockInsertion(insertedBlocks, insertionIndex, _, afterChangedBlocks, _, _):
            document.insertBlocks(insertedBlocks, at: insertionIndex)
            replace(afterChangedBlocks, in: &document)
        case let .blockDeletion(deletedBlocks, _):
            let deletedIDs = Set(deletedBlocks.map(\.id))
            document.blocks.removeAll { deletedIDs.contains($0.id) }
        case let .blockMove(blockID, _, afterIndex, _, afterChangedBlocks, _, _):
            document.moveBlock(blockID: blockID, to: afterIndex)
            replace(afterChangedBlocks, in: &document)
        case let .multiBlockReplacement(_, afterBlocks):
            replace(afterBlocks, in: &document)
        }
    }

    private func replace(_ block: BlockInputBlock, in document: inout BlockInputDocument) {
        guard let index = document.index(of: block.id) else {
            return
        }
        document.blocks[index] = block
    }

    private func replace(_ blocks: [BlockInputBlock], in document: inout BlockInputDocument) {
        for block in blocks {
            replace(block, in: &document)
        }
    }
}
