import AppKit

extension BlockInputView {
    @objc(undo:)
    func blockInputUndo(_ sender: Any?) {
        _ = performCommand(.undo)
    }

    @objc(redo:)
    func blockInputRedo(_ sender: Any?) {
        _ = performCommand(.redo)
    }

    @objc(copy:)
    func blockInputCopy(_ sender: Any?) {
        if performFocusedModalFieldEditorAction(#selector(NSText.copy(_:)), sender: sender) {
            return
        }
        _ = performCommand(.copy)
    }

    @objc(cut:)
    func blockInputCut(_ sender: Any?) {
        if performFocusedModalFieldEditorAction(#selector(NSText.cut(_:)), sender: sender) {
            return
        }
        _ = performCommand(.cut)
    }

    @objc(paste:)
    func blockInputPaste(_ sender: Any?) {
        if performFocusedModalFieldEditorAction(#selector(NSText.paste(_:)), sender: sender) {
            return
        }
        _ = performCommand(.paste)
    }

    @objc(blockInputFormatBold:)
    func blockInputFormatBold(_ sender: Any?) {
        _ = performCommand(.bold)
    }

    @objc(blockInputFormatItalic:)
    func blockInputFormatItalic(_ sender: Any?) {
        _ = performCommand(.italic)
    }

    @objc(blockInputFormatUnderline:)
    func blockInputFormatUnderline(_ sender: Any?) {
        _ = performCommand(.underline)
    }

    @objc(blockInputFormatStrikethrough:)
    func blockInputFormatStrikethrough(_ sender: Any?) {
        _ = performCommand(.strikethrough)
    }

    func performFocusedModalFieldEditorAction(_ action: Selector, sender: Any?) -> Bool {
        guard let fieldEditor = window?.firstResponder as? NSTextView,
              fieldEditor.isFieldEditor,
              linkModalContainsCurrentResponder() || imageModalContainsCurrentResponder() else {
            return false
        }
        // Menu actions can still target the editor while the modal owns AppKit's shared field editor.
        return NSApp.sendAction(action, to: fieldEditor, from: sender ?? self)
    }

    func performFocusedModalFieldEditorKeyEquivalent(_ event: NSEvent) -> Bool {
        let action: Selector?
        if event.blockInputIsSelectAllShortcut {
            action = #selector(NSText.selectAll(_:))
        } else if event.blockInputIsCopyShortcut {
            action = #selector(NSText.copy(_:))
        } else if event.blockInputIsCutShortcut {
            action = #selector(NSText.cut(_:))
        } else if event.blockInputIsPasteShortcut {
            action = #selector(NSText.paste(_:))
        } else {
            action = nil
        }
        guard let action else {
            return false
        }
        return performFocusedModalFieldEditorAction(action, sender: self)
    }
}
