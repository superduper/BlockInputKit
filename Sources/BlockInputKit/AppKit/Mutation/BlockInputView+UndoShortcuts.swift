import Foundation

extension BlockInputView {
    @discardableResult
    func performUndoShortcut(
        _ shortcut: BlockInputUndoShortcut,
        preferredBlockID: BlockInputBlockID? = nil
    ) -> Bool {
        guard isEditable else {
            return false
        }
        switch shortcut {
        case .undo:
            return undoForKeyboardShortcut(preferredBlockID: preferredBlockID) != nil
        case .redo:
            return redoForKeyboardShortcut(preferredBlockID: preferredBlockID) != nil
        }
    }

    @discardableResult
    func undoTextEdit(in blockID: BlockInputBlockID) -> BlockInputUndoResult? {
        guard isEditable,
              let block = block(withID: blockID),
              let result = undoController?.undoTextEdit(for: block) else {
            return nil
        }
        applyTextUndoResult(result, blockID: blockID)
        return result
    }

    @discardableResult
    func redoTextEdit(in blockID: BlockInputBlockID) -> BlockInputUndoResult? {
        guard isEditable,
              let block = block(withID: blockID),
              let result = undoController?.redoTextEdit(for: block) else {
            return nil
        }
        applyTextUndoResult(result, blockID: blockID)
        return result
    }

    private func undoForKeyboardShortcut(preferredBlockID: BlockInputBlockID?) -> BlockInputUndoResult? {
        switch undoController?.nextUndoOperation() {
        case let .text(blockID):
            return undoTextEdit(in: blockID)
        case .structural:
            return undoStructuralEdit()
        case nil:
            if let preferredBlockID, undoController?.canUndoTextEdit(in: preferredBlockID) == true {
                return undoTextEdit(in: preferredBlockID)
            }
            if let activeBlockID, undoController?.canUndoTextEdit(in: activeBlockID) == true {
                return undoTextEdit(in: activeBlockID)
            }
            return undoStructuralEdit()
        }
    }

    private func redoForKeyboardShortcut(preferredBlockID: BlockInputBlockID?) -> BlockInputUndoResult? {
        switch undoController?.nextRedoOperation() {
        case let .text(blockID):
            return redoTextEdit(in: blockID)
        case .structural:
            return redoStructuralEdit()
        case nil:
            if let preferredBlockID, undoController?.canRedoTextEdit(in: preferredBlockID) == true {
                return redoTextEdit(in: preferredBlockID)
            }
            if let activeBlockID, undoController?.canRedoTextEdit(in: activeBlockID) == true {
                return redoTextEdit(in: activeBlockID)
            }
            return redoStructuralEdit()
        }
    }

    private func applyTextUndoResult(_ result: BlockInputUndoResult, blockID: BlockInputBlockID) {
        guard let replacedBlock = result.replacedBlock,
              let replacementIndex = index(of: blockID) else {
            applyUndoResult(result)
            return
        }
        _ = applyGranularReplacementUndo(replacedBlock, at: replacementIndex, selection: result.selection)
    }
}

public extension BlockInputView {
    /// Undoes the most recent text edit in the active block.
    @discardableResult
    func undoTextEditInActiveBlock() -> BlockInputUndoResult? {
        guard isEditable,
              let blockID = activeBlockID else {
            return nil
        }
        return undoTextEdit(in: blockID)
    }

    /// Redoes the most recent undone text edit in the active block.
    @discardableResult
    func redoTextEditInActiveBlock() -> BlockInputUndoResult? {
        guard isEditable,
              let blockID = activeBlockID else {
            return nil
        }
        return redoTextEdit(in: blockID)
    }

    /// Undoes the most recent structural edit.
    @discardableResult
    func undoStructuralEdit() -> BlockInputUndoResult? {
        guard isEditable else {
            return nil
        }
        if let result = undoController?.nextGranularStructuralUndoResult() {
            if applyGranularUndoResult(result) { undoController?.commitGranularStructuralUndo(); return result }
            undoController?.cancelGranularStructuralUndo()
        }
        refreshDocumentFromStore()
        guard let result = undoController?.undoStructuralEdit(in: &document) else {
            return nil
        }
        applyUndoResult(result)
        return result
    }

    /// Redoes the most recent undone structural edit.
    @discardableResult
    func redoStructuralEdit() -> BlockInputUndoResult? {
        guard isEditable else {
            return nil
        }
        if let result = undoController?.nextGranularStructuralRedoResult() {
            if applyGranularUndoResult(result) { undoController?.commitGranularStructuralRedo(); return result }
            undoController?.cancelGranularStructuralRedo()
        }
        refreshDocumentFromStore()
        guard let result = undoController?.redoStructuralEdit(in: &document) else {
            return nil
        }
        applyUndoResult(result)
        return result
    }
}
