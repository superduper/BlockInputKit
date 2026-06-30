import AppKit

extension BlockInputView {
    func performMovementCommand(_ command: BlockInputEditorCommand) -> Bool? {
        // Structural/navigation commands and image-caret edge moves are handled directly; only
        // text-view movement selectors fall through to the mounted text view below.
        if let handled = performStructuralOrImageEdgeMovement(command) {
            return handled
        }
        guard let selector = command.movementSelector else { return nil }
        guard let blockID = activeBlockID else { return false }
        if let item = mountedBlockItem(for: blockID) {
            item.textView.doCommand(by: selector)
            // For vertical movement: the text view's scrollRangeToVisible reaches only the
            // inner block-item scroll view (a no-op because the item grows to fit content).
            // Explicitly scroll the outer document scroll view so the caret stays visible.
            if command.isVerticalMovement {
                scrollActiveTextSelectionToVisibleIfNeeded()
            }
            return true
        }
        return false
    }

    /// Returns `nil` when `command` is a plain text-view movement that the caller should dispatch
    /// to the mounted text view; otherwise performs the structural edit or image-caret move and
    /// returns its result.
    private func performStructuralOrImageEdgeMovement(_ command: BlockInputEditorCommand) -> Bool?? {
        switch command {
        case .insertBlockBelow:
            return scrolledMovement { self.insertBlockBelowCurrentBlock() != nil }
        case .insertBlockAbove:
            return scrolledMovement { self.insertBlockAboveCurrentBlock() != nil }
        case let .insertBlockBelowWithContent(kind, text):
            return scrolledMovement { self.insertBlockBelowCurrentBlock(kind: kind, text: text) != nil }
        case .deleteCurrentBlock:
            return .some(deleteCurrentBlock() != nil)
        case .selectCurrentBlock:
            return .some(selectCurrentBlock() != nil)
        case .moveAfterCurrentBlock:
            return scrolledMovement { self.moveAfterCurrentBlock() != nil }
        case .moveBeforeCurrentBlock:
            return scrolledMovement { self.moveBeforeCurrentBlock() != nil }
        case .moveToBlockContentStart, .moveToBlockContentEnd:
            // Image blocks have no editable text view, so the AppKit paragraph-movement selectors
            // are a no-op. Seat the image caret explicitly (offset 0 = before, offset 1 = after)
            // so vim `0`/`$`/`A`/`I` and especially `o` (content-end + insert below) operate on
            // the correct caret side instead of leaving it at offset 0, which makes `o` push the
            // image down behind a phantom paragraph. Non-image blocks fall through to the selector.
            return moveActiveImageCaretToContentEdge(command).map { .some($0) }
        default:
            return nil
        }
    }

    /// Runs a structural movement, scrolling the active selection into view when it reports change.
    private func scrolledMovement(_ perform: () -> Bool) -> Bool? {
        let moved = perform()
        if moved { scrollActiveTextSelectionToVisibleIfNeeded() }
        return moved
    }

    /// Seats the caret on the active image block's start (offset 0) or end (offset 1) edge.
    ///
    /// Returns `nil` when the active block is not an image so the caller falls through to the
    /// regular text-view movement selectors; returns `true` once the image caret is seated.
    private func moveActiveImageCaretToContentEdge(_ command: BlockInputEditorCommand) -> Bool? {
        guard case let .cursor(cursor) = selection,
              block(withID: cursor.blockID)?.kind.isImage == true else {
            return nil
        }
        let offset = command == .moveToBlockContentEnd ? 1 : 0
        if cursor.utf16Offset != offset {
            applySelection(.cursor(BlockInputCursor(blockID: cursor.blockID, utf16Offset: offset)), notify: true)
            restoreVisibleSelection()
        }
        return true
    }

    func canPerformMovementCommand(_ command: BlockInputEditorCommand) -> Bool? {
        switch command {
        case .insertBlockBelow, .insertBlockAbove, .insertBlockBelowWithContent, .deleteCurrentBlock, .increaseIndent, .decreaseIndent:
            return isEditable && activeBlockID != nil
        case .selectCurrentBlock, .moveAfterCurrentBlock, .moveBeforeCurrentBlock:
            return activeBlockID != nil
        default:
            break
        }
        guard command.movementSelector != nil else { return nil }
        switch selection {
        case .cursor, .text:
            return true
        case .blocks, .mixed, nil:
            return false
        }
    }
}

private extension BlockInputEditorCommand {
    var isVerticalMovement: Bool {
        switch self {
        case .moveUp, .moveDown, .extendSelectionUp, .extendSelectionDown:
            return true
        default:
            return false
        }
    }

    var movementSelector: Selector? {
        switch self {
        case .moveLeft: return #selector(NSResponder.moveLeft(_:))
        case .moveRight: return #selector(NSResponder.moveRight(_:))
        case .moveUp: return #selector(NSResponder.moveUp(_:))
        case .moveDown: return #selector(NSResponder.moveDown(_:))
        case .moveWordLeft: return #selector(NSResponder.moveWordLeft(_:))
        case .moveWordRight: return #selector(NSResponder.moveWordRight(_:))
        case .moveToLineStart: return #selector(NSResponder.moveToBeginningOfLine(_:))
        case .moveToLineEnd: return #selector(NSResponder.moveToEndOfLine(_:))
        case .moveToDocumentStart: return #selector(NSResponder.moveToBeginningOfDocument(_:))
        case .moveToDocumentEnd: return #selector(NSResponder.moveToEndOfDocument(_:))
        case .extendSelectionLeft: return #selector(NSResponder.moveLeftAndModifySelection(_:))
        case .extendSelectionRight: return #selector(NSResponder.moveRightAndModifySelection(_:))
        case .extendSelectionUp: return #selector(NSResponder.moveUpAndModifySelection(_:))
        case .extendSelectionDown: return #selector(NSResponder.moveDownAndModifySelection(_:))
        case .extendSelectionWordLeft: return #selector(NSResponder.moveWordLeftAndModifySelection(_:))
        case .extendSelectionWordRight: return #selector(NSResponder.moveWordRightAndModifySelection(_:))
        case .extendSelectionToLineStart:
            return #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:))
        case .extendSelectionToLineEnd:
            return #selector(NSResponder.moveToEndOfLineAndModifySelection(_:))
        case .moveToBlockContentStart: return #selector(NSResponder.moveToBeginningOfParagraph(_:))
        case .moveToBlockContentEnd: return #selector(NSResponder.moveToEndOfParagraph(_:))
        case .extendSelectionToBlockContentStart:
            return #selector(NSResponder.moveToBeginningOfParagraphAndModifySelection(_:))
        case .extendSelectionToBlockContentEnd:
            return #selector(NSResponder.moveToEndOfParagraphAndModifySelection(_:))
        case .increaseIndent: return #selector(NSTextView.insertTab(_:))
        case .decreaseIndent: return #selector(NSTextView.insertBacktab(_:))
        case .insertLineBreak: return #selector(NSText.insertNewlineIgnoringFieldEditor(_:))
        case .deleteWordBackward: return #selector(NSResponder.deleteWordBackward(_:))
        case .deleteWordForward: return #selector(NSResponder.deleteWordForward(_:))
        case .deleteToLineEnd: return #selector(NSResponder.deleteToEndOfParagraph(_:))
        case .deleteCharForward: return #selector(NSResponder.deleteForward(_:))
        case .deleteCharBackward: return #selector(NSResponder.deleteBackward(_:))
        default: return nil
        }
    }
}
