import AppKit

enum BlockInputUndoShortcut {
    case undo
    case redo
}

/// Editor-owned text formatting shortcuts that mutate Markdown source instead of AppKit attributes.
enum BlockInputTextFormattingShortcut {
    case bold
    case italic
    case underline
    case strikethrough
    case inlineCode
}

extension NSEvent {
    var blockInputIsSelectAllShortcut: Bool {
        modifierFlags.contains(.command)
            && !modifierFlags.contains(.option)
            && !modifierFlags.contains(.control)
            && !modifierFlags.contains(.shift)
            && charactersIgnoringModifiers?.lowercased() == "a"
    }

    var blockInputIsCopyShortcut: Bool {
        modifierFlags.contains(.command)
            && !modifierFlags.contains(.option)
            && !modifierFlags.contains(.control)
            && !modifierFlags.contains(.shift)
            && charactersIgnoringModifiers?.lowercased() == "c"
    }

    var blockInputIsCutShortcut: Bool {
        modifierFlags.contains(.command)
            && !modifierFlags.contains(.option)
            && !modifierFlags.contains(.control)
            && !modifierFlags.contains(.shift)
            && charactersIgnoringModifiers?.lowercased() == "x"
    }

    var blockInputIsPasteShortcut: Bool {
        modifierFlags.contains(.command)
            && !modifierFlags.contains(.option)
            && !modifierFlags.contains(.control)
            && !modifierFlags.contains(.shift)
            && charactersIgnoringModifiers?.lowercased() == "v"
    }

    var blockInputUndoShortcut: BlockInputUndoShortcut? {
        guard modifierFlags.contains(.command),
              !modifierFlags.contains(.option),
              !modifierFlags.contains(.control),
              charactersIgnoringModifiers?.lowercased() == "z" else {
            return nil
        }
        return modifierFlags.contains(.shift) ? .redo : .undo
    }

    var blockInputTextFormattingShortcut: BlockInputTextFormattingShortcut? {
        guard modifierFlags.contains(.command),
              !modifierFlags.contains(.option),
              !modifierFlags.contains(.control) else {
            return nil
        }
        let key = charactersIgnoringModifiers?.lowercased()
        if !modifierFlags.contains(.shift) {
            switch key {
            case "b":
                return .bold
            case "i":
                return .italic
            case "u":
                return .underline
            default:
                return nil
            }
        }
        return key == "x" ? .strikethrough : nil
    }

    var blockInputEditorCommandShortcut: BlockInputEditorCommand? {
        if blockInputIsSelectAllShortcut { return .selectAll }
        if let undoShortcut = blockInputUndoShortcut { return BlockInputEditorCommand(undoShortcut) }
        if let formattingShortcut = blockInputTextFormattingShortcut { return BlockInputEditorCommand(formattingShortcut) }
        if blockInputIsCopyShortcut { return .copy }
        if blockInputIsCutShortcut { return .cut }
        if blockInputIsPasteShortcut { return .paste }
        return nil
    }

    var blockInputInsertedText: String? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard type == .keyDown,
              !modifiers.contains(.command),
              !modifiers.contains(.option),
              !modifiers.contains(.control),
              !isBackspaceOrDelete,
              !isCancelOperation,
              !isArrowKey,
              let characters,
              !characters.isEmpty,
              !characters.unicodeScalars.contains(where: \.blockInputIsNonPrintingKeyScalar) else {
            return nil
        }
        return characters
    }

    var blockInputSelectionExpansionDirection: BlockInputVerticalMovementDirection? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.shift),
              !modifiers.contains(.command),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return nil
        }
        if keyCode == 126 || charactersIgnoringModifiers == "\u{F700}" {
            return .upward
        }
        if keyCode == 125 || charactersIgnoringModifiers == "\u{F701}" {
            return .downward
        }
        return nil
    }

    var horizontalSelectionAdjustmentDirection: BlockInputHorizontalMovementDirection? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.shift),
              !modifiers.contains(.command),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return nil
        }
        if keyCode == 123 || charactersIgnoringModifiers == "\u{F702}" {
            return .leftward
        }
        if keyCode == 124 || charactersIgnoringModifiers == "\u{F703}" {
            return .rightward
        }
        return nil
    }

    var lineBoundarySelectionDirection: BlockInputLineBoundarySelectionDirection? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.shift),
              modifiers.contains(.command),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return nil
        }
        if keyCode == 123 || charactersIgnoringModifiers == "\u{F702}" {
            return .beginning
        }
        if keyCode == 124 || charactersIgnoringModifiers == "\u{F703}" {
            return .end
        }
        return nil
    }

    var plainHorizontalMovementDirection: BlockInputHorizontalMovementDirection? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.contains(.shift),
              !modifiers.contains(.command),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return nil
        }
        if keyCode == 123 || charactersIgnoringModifiers == "\u{F702}" {
            return .leftward
        }
        if keyCode == 124 || charactersIgnoringModifiers == "\u{F703}" {
            return .rightward
        }
        return nil
    }

    var blockInputWordMovementDirection: BlockInputWordMovementDirection? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.option),
              !modifiers.contains(.command),
              !modifiers.contains(.shift),
              !modifiers.contains(.control) else {
            return nil
        }
        if keyCode == 123 || charactersIgnoringModifiers == "\u{F702}" {
            return .leftward
        }
        if keyCode == 124 || charactersIgnoringModifiers == "\u{F703}" {
            return .rightward
        }
        return nil
    }

    var blockInputWordSelectionDirection: BlockInputWordMovementDirection? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.option),
              modifiers.contains(.shift),
              !modifiers.contains(.command),
              !modifiers.contains(.control) else {
            return nil
        }
        if keyCode == 123 || charactersIgnoringModifiers == "\u{F702}" {
            return .leftward
        }
        if keyCode == 124 || charactersIgnoringModifiers == "\u{F703}" {
            return .rightward
        }
        return nil
    }

    var blockInputDocumentBoundaryDirection: BlockInputVerticalMovementDirection? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              !modifiers.contains(.shift),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return nil
        }
        return verticalMovementDirection
    }

    var tableCellCommandArrow: Bool {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              !modifiers.contains(.shift),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return false
        }
        return isArrowKey
    }

    var plainVerticalMovementDirection: BlockInputVerticalMovementDirection? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.contains(.command),
              !modifiers.contains(.shift),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return nil
        }
        return verticalMovementDirection
    }

    var verticalMovementDirection: BlockInputVerticalMovementDirection? {
        if keyCode == 126 || charactersIgnoringModifiers == "\u{F700}" {
            return .upward
        }
        if keyCode == 125 || charactersIgnoringModifiers == "\u{F701}" {
            return .downward
        }
        return nil
    }

    var isBackspaceOrDelete: Bool {
        keyCode == 51
            || keyCode == 117
            || charactersIgnoringModifiers == "\u{7F}"
            || charactersIgnoringModifiers == "\u{F728}"
    }

    var isCancelOperation: Bool {
        keyCode == 53 || charactersIgnoringModifiers == "\u{1B}"
    }

    var isArrowKey: Bool {
        keyCode == 125
            || keyCode == 126
            || keyCode == 123
            || keyCode == 124
            || charactersIgnoringModifiers == "\u{F700}"
            || charactersIgnoringModifiers == "\u{F701}"
            || charactersIgnoringModifiers == "\u{F702}"
            || charactersIgnoringModifiers == "\u{F703}"
    }

    var debugKeyName: String {
        if keyCode == 123 || charactersIgnoringModifiers == "\u{F702}" {
            return "Left"
        }
        if keyCode == 124 || charactersIgnoringModifiers == "\u{F703}" {
            return "Right"
        }
        if keyCode == 126 || charactersIgnoringModifiers == "\u{F700}" {
            return "Up"
        }
        if keyCode == 125 || charactersIgnoringModifiers == "\u{F701}" {
            return "Down"
        }
        return "keyCode=\(keyCode)"
    }

    var debugModifierNames: String {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        var names: [String] = []
        if modifiers.contains(.command) {
            names.append("cmd")
        }
        if modifiers.contains(.shift) {
            names.append("shift")
        }
        if modifiers.contains(.option) {
            names.append("opt")
        }
        if modifiers.contains(.control) {
            names.append("ctrl")
        }
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }

}

private extension UnicodeScalar {
    var blockInputIsNonPrintingKeyScalar: Bool {
        CharacterSet.controlCharacters.contains(self) || (0xF700...0xF8FF).contains(value)
    }
}
