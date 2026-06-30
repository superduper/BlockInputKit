import Foundation

/// Result of an undo or redo operation, including the selection to restore.
public struct BlockInputUndoResult: Equatable, Sendable {
    /// Selection that should be restored after applying the undo or redo result.
    public var selection: BlockInputSelection?
    /// Human-readable action name for menu titles and history UI.
    public var actionName: String
    var replacedBlock: BlockInputBlock?
    var replacedBlocks: [BlockInputBlock]?
    var insertedBlocks: [BlockInputBlock]?
    var insertionIndex: Int?
    var deletedBlockIDs: [BlockInputBlockID]?
    var movedBlockID: BlockInputBlockID?
    var moveIndex: Int?
    var markerTransaction: BlockInputNumberedListMarkerTransaction?

    init(
        selection: BlockInputSelection?,
        actionName: String,
        replacedBlock: BlockInputBlock? = nil,
        replacedBlocks: [BlockInputBlock]? = nil,
        insertedBlocks: [BlockInputBlock]? = nil,
        insertionIndex: Int? = nil,
        deletedBlockIDs: [BlockInputBlockID]? = nil,
        movedBlockID: BlockInputBlockID? = nil,
        moveIndex: Int? = nil,
        markerTransaction: BlockInputNumberedListMarkerTransaction? = nil
    ) {
        self.selection = selection
        self.actionName = actionName
        self.replacedBlock = replacedBlock
        self.replacedBlocks = replacedBlocks
        self.insertedBlocks = insertedBlocks
        self.insertionIndex = insertionIndex
        self.deletedBlockIDs = deletedBlockIDs
        self.movedBlockID = movedBlockID
        self.moveIndex = moveIndex
        self.markerTransaction = markerTransaction
    }
}

/// Coordinates per-block text undo with a separate structural undo stack.
public final class BlockInputUndoController {
    private var textUndoByBlockID: [BlockInputBlockID: [BlockInputTextUndoEntry]] = [:],
                textRedoByBlockID: [BlockInputBlockID: [BlockInputTextUndoEntry]] = [:]
    private var structuralUndoStack: [BlockInputStructuralUndoEntry] = [], structuralRedoStack: [BlockInputStructuralUndoEntry] = []
    private var undoOrder: [BlockInputHistoryOperation] = [], redoOrder: [BlockInputHistoryOperation] = []
    private var isApplyingStructuralUndo = false

    /// Creates an empty undo controller.
    public init() {}
    func canUndo() -> Bool { undoOrder.reversed().contains { $0.canPerform(text: canUndoTextEdit, structural: !structuralUndoStack.isEmpty) } }
    func canRedo() -> Bool { redoOrder.reversed().contains { $0.canPerform(text: canRedoTextEdit, structural: !structuralRedoStack.isEmpty) } }

    func canUndoTextEdit(in blockID: BlockInputBlockID) -> Bool {
        !(textUndoByBlockID[blockID]?.isEmpty ?? true)
    }

    func canRedoTextEdit(in blockID: BlockInputBlockID) -> Bool {
        !(textRedoByBlockID[blockID]?.isEmpty ?? true)
    }

    /// Records a text edit for a single block.
    ///
    /// List-like blocks may also pass per-line indentation snapshots when the
    /// edit inserts or removes list lines inside the block.
    public func registerTextEdit(
        blockID: BlockInputBlockID,
        beforeText: String,
        afterText: String,
        beforeLineIndentationLevels: [Int]? = nil,
        afterLineIndentationLevels: [Int]? = nil,
        selectionBefore: BlockInputSelection?,
        selectionAfter: BlockInputSelection?
    ) {
        guard beforeText != afterText || beforeLineIndentationLevels != afterLineIndentationLevels else {
            return
        }
        guard !isApplyingStructuralUndo else { return }
        textUndoByBlockID[blockID, default: []].append(BlockInputTextUndoEntry(
            blockID: blockID,
            beforeText: beforeText,
            afterText: afterText,
            beforeLineIndentationLevels: beforeLineIndentationLevels,
            afterLineIndentationLevels: afterLineIndentationLevels,
            selectionBefore: selectionBefore,
            selectionAfter: selectionAfter
        ))
        undoOrder.append(.text(blockID))
        textRedoByBlockID[blockID] = []
        structuralRedoStack = []
        redoOrder = []
    }

    /// Records a document-level structural edit.
    public func registerStructuralEdit(
        actionName: String,
        beforeDocument: BlockInputDocument,
        afterDocument: BlockInputDocument,
        selectionBefore: BlockInputSelection?,
        selectionAfter: BlockInputSelection?
    ) {
        guard beforeDocument != afterDocument, !isApplyingStructuralUndo else { return }
        structuralUndoStack.append(BlockInputStructuralUndoEntry(
            actionName: actionName,
            beforeDocument: beforeDocument,
            afterDocument: afterDocument,
            selectionBefore: selectionBefore,
            selectionAfter: selectionAfter
        ))
        undoOrder.append(.structural)
        structuralRedoStack = []
        textRedoByBlockID = [:]
        redoOrder = []
    }

    /// Records a structural edit that replaces one block without snapshotting the full document.
    func registerBlockReplacementStructuralEdit(
        actionName: String,
        beforeBlock: BlockInputBlock,
        afterBlock: BlockInputBlock,
        selectionBefore: BlockInputSelection?,
        selectionAfter: BlockInputSelection?
    ) {
        guard beforeBlock != afterBlock, !isApplyingStructuralUndo else { return }
        structuralUndoStack.append(BlockInputStructuralUndoEntry(
            actionName: actionName,
            payload: .blockReplacement(beforeBlock: beforeBlock, afterBlock: afterBlock),
            selectionBefore: selectionBefore,
            selectionAfter: selectionAfter
        ))
        undoOrder.append(.structural)
        structuralRedoStack = []
        textRedoByBlockID = [:]
        redoOrder = []
    }

    /// Records a structural edit that replaces multiple blocks without snapshotting the full document.
    func registerMultiBlockReplacementStructuralEdit(_ edit: BlockInputMultiBlockReplacementEdit) {
        guard edit.beforeBlocks.count == edit.afterBlocks.count,
              zip(edit.beforeBlocks, edit.afterBlocks).contains(where: !=),
              !isApplyingStructuralUndo else { return }
        structuralUndoStack.append(BlockInputStructuralUndoEntry(
            actionName: edit.actionName,
            payload: .multiBlockReplacement(beforeBlocks: edit.beforeBlocks, afterBlocks: edit.afterBlocks),
            selectionBefore: edit.selectionBefore,
            selectionAfter: edit.selectionAfter
        ))
        undoOrder.append(.structural)
        structuralRedoStack = []
        textRedoByBlockID = [:]
        redoOrder = []
    }

    /// Records a structural edit that inserts blocks without snapshotting the full document.
    func registerBlockInsertionStructuralEdit(
        actionName: String,
        insertedBlocks: [BlockInputBlock],
        insertionIndex: Int,
        beforeChangedBlocks: [BlockInputBlock] = [],
        afterChangedBlocks: [BlockInputBlock] = [],
        beforeMarkerTransaction: BlockInputNumberedListMarkerTransaction? = nil,
        afterMarkerTransaction: BlockInputNumberedListMarkerTransaction? = nil,
        selectionBefore: BlockInputSelection?,
        selectionAfter: BlockInputSelection?
    ) {
        guard !insertedBlocks.isEmpty, !isApplyingStructuralUndo else { return }
        structuralUndoStack.append(BlockInputStructuralUndoEntry(
            actionName: actionName,
            payload: .blockInsertion(
                insertedBlocks: insertedBlocks,
                insertionIndex: insertionIndex,
                beforeChangedBlocks: beforeChangedBlocks,
                afterChangedBlocks: afterChangedBlocks,
                beforeMarkerTransaction: beforeMarkerTransaction,
                afterMarkerTransaction: afterMarkerTransaction
            ),
            selectionBefore: selectionBefore,
            selectionAfter: selectionAfter
        ))
        undoOrder.append(.structural)
        structuralRedoStack = []
        textRedoByBlockID = [:]
        redoOrder = []
    }

    /// Records a structural edit that replaces one block and inserts follow-up blocks.
    func registerBlockReplacementInsertionStructuralEdit(_ edit: BlockInputReplaceInsertEdit) {
        guard edit.beforeBlock != edit.afterBlock, !edit.insertedBlocks.isEmpty, !isApplyingStructuralUndo else { return }
        structuralUndoStack.append(BlockInputStructuralUndoEntry(
            actionName: edit.actionName,
            payload: .blockReplacementInsertion(
                beforeBlock: edit.beforeBlock,
                afterBlock: edit.afterBlock,
                insertedBlocks: edit.insertedBlocks,
                insertionIndex: edit.insertionIndex,
                beforeChangedBlocks: edit.beforeChangedBlocks,
                afterChangedBlocks: edit.afterChangedBlocks,
                beforeMarkerTransaction: edit.beforeMarkerTransaction,
                afterMarkerTransaction: edit.afterMarkerTransaction
            ),
            selectionBefore: edit.selectionBefore,
            selectionAfter: edit.selectionAfter
        ))
        undoOrder.append(.structural)
        structuralRedoStack = []
        textRedoByBlockID = [:]
        redoOrder = []
    }

    /// Records a structural edit that replaces one block and deletes follow-up blocks.
    func registerBlockReplacementDeletionStructuralEdit(_ edit: BlockInputReplaceDeleteEdit) {
        guard edit.beforeBlock != edit.afterBlock, !edit.deletedBlocks.isEmpty, !isApplyingStructuralUndo else { return }
        structuralUndoStack.append(BlockInputStructuralUndoEntry(
            actionName: edit.actionName,
            payload: .blockReplacementDeletion(
                beforeBlock: edit.beforeBlock,
                afterBlock: edit.afterBlock,
                deletedBlocks: edit.deletedBlocks,
                deletionIndex: edit.deletionIndex
            ),
            selectionBefore: edit.selectionBefore,
            selectionAfter: edit.selectionAfter
        ))
        undoOrder.append(.structural)
        structuralRedoStack = []
        textRedoByBlockID = [:]
        redoOrder = []
    }

    /// Records a structural move without snapshotting the full document.
    func registerBlockMoveStructuralEdit(_ edit: BlockInputMoveEdit) {
        guard !isApplyingStructuralUndo else { return }
        structuralUndoStack.append(BlockInputStructuralUndoEntry(
            actionName: edit.actionName,
            payload: .blockMove(
                blockID: edit.blockID,
                beforeIndex: edit.beforeIndex,
                afterIndex: edit.afterIndex,
                beforeChangedBlocks: edit.beforeChangedBlocks,
                afterChangedBlocks: edit.afterChangedBlocks,
                beforeMarkerTransaction: edit.beforeMarkerTransaction,
                afterMarkerTransaction: edit.afterMarkerTransaction
            ),
            selectionBefore: edit.selectionBefore,
            selectionAfter: edit.selectionAfter
        ))
        undoOrder.append(.structural)
        structuralRedoStack = []
        textRedoByBlockID = [:]
        redoOrder = []
    }

    /// Undoes the most recent text edit for a block.
    public func undoTextEdit(
        in document: inout BlockInputDocument,
        blockID: BlockInputBlockID
    ) -> BlockInputUndoResult? {
        guard var stack = textUndoByBlockID[blockID],
              let entry = stack.popLast(),
              let index = document.index(of: blockID) else {
            return nil
        }
        textUndoByBlockID[blockID] = stack
        textRedoByBlockID[blockID, default: []].append(entry)
        removeLastUndoOperation(.text(blockID))
        redoOrder.append(.text(blockID))
        document.blocks[index].text = entry.beforeText
        if let beforeLineIndentationLevels = entry.beforeLineIndentationLevels {
            document.blocks[index].lineIndentationLevels = beforeLineIndentationLevels
        }
        return BlockInputUndoResult(selection: entry.selectionBefore, actionName: "Text Edit")
    }

    /// Undoes text using the current block snapshot so store-backed views can
    /// replace one block without refreshing the full document.
    func undoTextEdit(for block: BlockInputBlock) -> BlockInputUndoResult? {
        guard var stack = textUndoByBlockID[block.id],
              let entry = stack.popLast() else {
            return nil
        }
        textUndoByBlockID[block.id] = stack
        textRedoByBlockID[block.id, default: []].append(entry)
        removeLastUndoOperation(.text(block.id))
        redoOrder.append(.text(block.id))
        var replacement = block
        replacement.text = entry.beforeText
        if let beforeLineIndentationLevels = entry.beforeLineIndentationLevels {
            replacement.lineIndentationLevels = beforeLineIndentationLevels
        }
        return BlockInputUndoResult(
            selection: entry.selectionBefore,
            actionName: "Text Edit",
            replacedBlock: replacement
        )
    }

    /// Redoes the most recent undone text edit for a block.
    public func redoTextEdit(
        in document: inout BlockInputDocument,
        blockID: BlockInputBlockID
    ) -> BlockInputUndoResult? {
        guard var stack = textRedoByBlockID[blockID],
              let entry = stack.popLast(),
              let index = document.index(of: blockID) else {
            return nil
        }
        textRedoByBlockID[blockID] = stack
        textUndoByBlockID[blockID, default: []].append(entry)
        undoOrder.append(.text(blockID))
        removeLastRedoOperation(.text(blockID))
        document.blocks[index].text = entry.afterText
        if let afterLineIndentationLevels = entry.afterLineIndentationLevels {
            document.blocks[index].lineIndentationLevels = afterLineIndentationLevels
        }
        return BlockInputUndoResult(selection: entry.selectionAfter, actionName: "Text Edit")
    }

    /// Redoes text using the current block snapshot so store-backed views can
    /// replace one block without refreshing the full document.
    func redoTextEdit(for block: BlockInputBlock) -> BlockInputUndoResult? {
        guard var stack = textRedoByBlockID[block.id],
              let entry = stack.popLast() else {
            return nil
        }
        textRedoByBlockID[block.id] = stack
        textUndoByBlockID[block.id, default: []].append(entry)
        undoOrder.append(.text(block.id))
        removeLastRedoOperation(.text(block.id))
        var replacement = block
        replacement.text = entry.afterText
        if let afterLineIndentationLevels = entry.afterLineIndentationLevels {
            replacement.lineIndentationLevels = afterLineIndentationLevels
        }
        return BlockInputUndoResult(
            selection: entry.selectionAfter,
            actionName: "Text Edit",
            replacedBlock: replacement
        )
    }

    /// Undoes the most recent structural edit.
    public func undoStructuralEdit(in document: inout BlockInputDocument) -> BlockInputUndoResult? {
        guard let entry = structuralUndoStack.popLast() else {
            return nil
        }
        structuralRedoStack.append(entry)
        removeLastUndoOperation(.structural)
        redoOrder.append(.structural)
        entry.payload.applyUndo(to: &document)
        return BlockInputUndoResult(
            selection: entry.selectionBefore,
            actionName: entry.actionName,
            replacedBlock: entry.payload.replacementBlockForUndo,
            insertedBlocks: entry.payload.insertedBlocksForUndo,
            insertionIndex: entry.payload.insertionIndexForUndo,
            deletedBlockIDs: entry.payload.deletedBlockIDsForUndo
        )
    }

    /// Redoes the most recent undone structural edit.
    public func redoStructuralEdit(in document: inout BlockInputDocument) -> BlockInputUndoResult? {
        guard let entry = structuralRedoStack.popLast() else {
            return nil
        }
        structuralUndoStack.append(entry)
        undoOrder.append(.structural)
        removeLastRedoOperation(.structural)
        entry.payload.applyRedo(to: &document)
        return BlockInputUndoResult(
            selection: entry.selectionAfter,
            actionName: entry.actionName,
            replacedBlock: entry.payload.replacementBlockForRedo,
            insertedBlocks: entry.payload.insertedBlocksForRedo,
            insertionIndex: entry.payload.insertionIndexForRedo,
            deletedBlockIDs: entry.payload.deletedBlockIDsForRedo
        )
    }

    func nextGranularStructuralUndoResult() -> BlockInputUndoResult? {
        guard let entry = structuralUndoStack.last,
              entry.payload.canApplyGranularly else {
            return nil
        }
        isApplyingStructuralUndo = true
        return entry.payload.undoResult(selection: entry.selectionBefore, actionName: entry.actionName)
    }

    func cancelGranularStructuralUndo() { isApplyingStructuralUndo = false }

    func commitGranularStructuralUndo() {
        defer { isApplyingStructuralUndo = false }
        guard let entry = structuralUndoStack.last,
              entry.payload.canApplyGranularly else {
            return
        }
        structuralUndoStack.removeLast()
        structuralRedoStack.append(entry)
        removeLastUndoOperation(.structural)
        redoOrder.append(.structural)
    }

    func nextGranularStructuralRedoResult() -> BlockInputUndoResult? {
        guard let entry = structuralRedoStack.last,
              entry.payload.canApplyGranularly else {
            return nil
        }
        isApplyingStructuralUndo = true
        return entry.payload.redoResult(selection: entry.selectionAfter, actionName: entry.actionName)
    }

    func cancelGranularStructuralRedo() { isApplyingStructuralUndo = false }

    func commitGranularStructuralRedo() {
        defer { isApplyingStructuralUndo = false }
        guard let entry = structuralRedoStack.last,
              entry.payload.canApplyGranularly else {
            return
        }
        structuralRedoStack.removeLast()
        structuralUndoStack.append(entry)
        undoOrder.append(.structural)
        removeLastRedoOperation(.structural)
    }

}
extension BlockInputUndoController {
    func nextUndoOperation() -> BlockInputHistoryOperation? {
        while let operation = undoOrder.last {
            switch operation {
            case let .text(blockID):
                if canUndoTextEdit(in: blockID) {
                    return operation
                }
            case .structural:
                if !structuralUndoStack.isEmpty {
                    return operation
                }
            }
            undoOrder.removeLast()
        }
        return nil
    }

    func nextRedoOperation() -> BlockInputHistoryOperation? {
        while let operation = redoOrder.last {
            switch operation {
            case let .text(blockID):
                if canRedoTextEdit(in: blockID) {
                    return operation
                }
            case .structural:
                if !structuralRedoStack.isEmpty {
                    return operation
                }
            }
            redoOrder.removeLast()
        }
        return nil
    }

    private func removeLastRedoOperation(_ operation: BlockInputHistoryOperation) {
        guard let index = redoOrder.lastIndex(of: operation) else {
            return
        }
        redoOrder.remove(at: index)
    }

    private func removeLastUndoOperation(_ operation: BlockInputHistoryOperation) {
        guard let index = undoOrder.lastIndex(of: operation) else {
            return
        }
        undoOrder.remove(at: index)
    }

    /// Records a structural edit that deletes blocks without snapshotting the full document.
    func registerBlockDeletionStructuralEdit(
        actionName: String,
        deletedBlocks: [BlockInputBlock],
        deletionIndex: Int,
        selectionBefore: BlockInputSelection?,
        selectionAfter: BlockInputSelection?
    ) {
        guard !deletedBlocks.isEmpty else { return }
        guard !isApplyingStructuralUndo else { return }
        structuralUndoStack.append(BlockInputStructuralUndoEntry(
            actionName: actionName,
            payload: .blockDeletion(deletedBlocks: deletedBlocks, deletionIndex: deletionIndex),
            selectionBefore: selectionBefore,
            selectionAfter: selectionAfter
        ))
        undoOrder.append(.structural)
        structuralRedoStack = []
        textRedoByBlockID = [:]
        redoOrder = []
    }
}
