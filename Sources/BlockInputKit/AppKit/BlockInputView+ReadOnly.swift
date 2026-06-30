import AppKit

extension BlockInputView {
    var disabledCursorForReadOnly: NSCursor? {
        isEditable ? nil : disabledCursor
    }

    func dismissMutationUIIfNeeded(wasEditable: Bool) {
        guard wasEditable, !isEditable else {
            return
        }
        dismissCompletionPopup()
        dismissLinkModal(restoreFocus: false)
        dismissImageModal(restoreFocus: false)
        cancelAsyncContentTasks()
        hideDropIndicator()
    }

    func invalidateReadOnlyCursorRects() {
        invalidateVisibleCursorRects()
    }

    func addDisabledCursorRectIfNeeded(to view: NSView) {
        guard let cursor = disabledCursorForReadOnly else {
            return
        }
        view.addCursorRect(view.bounds, cursor: cursor)
    }

    func addEditableSurfaceCursorRectIfNeeded(to view: NSView) {
        guard isEditable else {
            return
        }
        view.addCursorRect(view.bounds, cursor: .iBeam)
    }

    @discardableResult
    func focusEditorFromEditableSurfaceClick() -> Bool {
        guard isEditable else {
            return false
        }
        focusEditor()
        return true
    }

    func discardReadOnlyTextChangeIfNeeded(item: BlockInputBlockItem, block: BlockInputBlock) -> Bool {
        guard !isEditable else {
            return false
        }
        configureBlockItem(item, block: block)
        return true
    }
}

extension BlockInputEditorCommand {
    var isMutatingDocument: Bool {
        switch self {
        case .copy, .selectAll,
             .moveLeft, .moveRight, .moveUp, .moveDown,
             .moveWordLeft, .moveWordRight,
             .moveToLineStart, .moveToLineEnd,
             .moveToDocumentStart, .moveToDocumentEnd,
             .moveToBlockContentStart, .moveToBlockContentEnd,
             .extendSelectionLeft, .extendSelectionRight,
             .extendSelectionUp, .extendSelectionDown,
             .extendSelectionWordLeft, .extendSelectionWordRight,
             .extendSelectionToLineStart, .extendSelectionToLineEnd,
             .extendSelectionToBlockContentStart, .extendSelectionToBlockContentEnd,
             .selectCurrentBlock, .moveAfterCurrentBlock, .moveBeforeCurrentBlock,
             .findNext, .findPrevious:
            return false
        case .undo, .redo, .cut, .paste,
             .bold, .italic, .underline, .strikethrough, .formatCode,
             .insertLink, .removeLink,
             .deleteCharForward, .deleteCharBackward,
             .insertBlockBelow, .insertBlockAbove, .insertBlockBelowWithContent,
             .insertImage, .deleteImage,
             .insertTable, .insertRow, .insertColumn, .deleteRow, .deleteColumn, .deleteTable,
             .deleteWordBackward, .deleteWordForward, .deleteToLineEnd,
             .deleteCurrentBlock, .increaseIndent, .decreaseIndent, .insertLineBreak,
             .setBlockKind:
            return true
        }
    }
}
