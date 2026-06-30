import AppKit

/// Internal dispatch state for a shortcut candidate after host registration lookup.
enum BlockInputKeyboardShortcutDispatchResult {
    /// No host handler is registered for the shortcut, so editor/AppKit defaults should continue normally.
    case notRegistered
    /// A host handler consumed the shortcut or successfully ran a requested default action.
    case handled
    /// A host handler explicitly declined the shortcut, so the original event or selector should continue once.
    case ignored
}

extension BlockInputKeyboardShortcut {
    /// Creates a normalized shortcut from an AppKit key event.
    init?(event: NSEvent) {
        guard let key = BlockInputKeyboardKey(event: event) else {
            return nil
        }
        self.init(
            key: key,
            modifiers: BlockInputKeyboardModifiers(modifierFlags: event.modifierFlags)
        )
    }

    /// Creates a normalized shortcut from an AppKit command selector.
    ///
    /// When AppKit exposes both a selector and the current key-down event, the event supplies modifier precision as long
    /// as it still represents the selector's logical key and implied modifiers.
    @MainActor
    init?(selector: Selector) {
        guard let key = BlockInputKeyboardKey(selector: selector) else {
            return nil
        }
        let selectorModifiers = BlockInputKeyboardModifiers(selector: selector)
        if let event = NSApp.currentEvent,
           event.type == .keyDown,
           let shortcut = BlockInputKeyboardShortcut(event: event),
           shortcut.key == key,
           selectorModifiers.isEmpty || shortcut.modifiers.intersection(selectorModifiers) == selectorModifiers {
            self = shortcut
            return
        }
        self.init(
            key: key,
            modifiers: selectorModifiers
        )
    }

    var lineBoundarySelectionDirection: BlockInputLineBoundarySelectionDirection? {
        guard modifiers == [.command, .shift] else {
            return nil
        }
        switch key {
        case .leftArrow:
            return .beginning
        case .rightArrow:
            return .end
        default:
            return nil
        }
    }
}

extension BlockInputKeyboardModifiers {
    /// Creates semantic modifier flags from an AppKit event's modifier flags.
    init(modifierFlags: NSEvent.ModifierFlags) {
        var modifiers: BlockInputKeyboardModifiers = []
        let semanticFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        if semanticFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if semanticFlags.contains(.control) {
            modifiers.insert(.control)
        }
        if semanticFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if semanticFlags.contains(.command) {
            modifiers.insert(.command)
        }
        self = modifiers
    }

    /// Creates semantic modifier flags implied by selector-only AppKit command routing.
    init(selector: Selector) {
        switch selector {
        case #selector(NSTextView.insertNewlineIgnoringFieldEditor(_:)),
             #selector(NSTextView.insertBacktab(_:)),
             #selector(NSTextView.moveUpAndModifySelection(_:)),
             #selector(NSTextView.moveDownAndModifySelection(_:)),
             #selector(NSTextView.moveLeftAndModifySelection(_:)),
             #selector(NSTextView.moveBackwardAndModifySelection(_:)),
             #selector(NSTextView.moveRightAndModifySelection(_:)),
             #selector(NSTextView.moveForwardAndModifySelection(_:)):
            self = .shift
        case #selector(NSTextView.moveToBeginningOfDocument(_:)),
             #selector(NSTextView.moveToEndOfDocument(_:)),
             #selector(NSTextView.moveToBeginningOfLine(_:)),
             #selector(NSTextView.moveToEndOfLine(_:)):
            self = .command
        case #selector(NSTextView.moveToBeginningOfLineAndModifySelection(_:)),
             #selector(NSTextView.moveToLeftEndOfLineAndModifySelection(_:)),
             #selector(NSTextView.moveToEndOfLineAndModifySelection(_:)),
             #selector(NSTextView.moveToRightEndOfLineAndModifySelection(_:)):
            self = [.command, .shift]
        case #selector(NSTextView.moveWordLeft(_:)),
             #selector(NSTextView.moveWordRight(_:)),
             #selector(NSTextView.moveWordBackward(_:)),
             #selector(NSTextView.moveWordForward(_:)):
            self = .option
        case #selector(NSTextView.moveWordLeftAndModifySelection(_:)),
             #selector(NSTextView.moveWordRightAndModifySelection(_:)),
             #selector(NSTextView.moveWordBackwardAndModifySelection(_:)),
             #selector(NSTextView.moveWordForwardAndModifySelection(_:)):
            self = [.option, .shift]
        default:
            self = []
        }
    }
}

private extension BlockInputKeyboardKey {
    static let selectorMapping: [Selector: BlockInputKeyboardKey] = [
        #selector(NSTextView.insertNewline(_:)): .return,
        #selector(NSTextView.insertNewlineIgnoringFieldEditor(_:)): .return,
        #selector(NSTextView.moveUp(_:)): .upArrow,
        #selector(NSTextView.moveUpAndModifySelection(_:)): .upArrow,
        #selector(NSTextView.moveDown(_:)): .downArrow,
        #selector(NSTextView.moveDownAndModifySelection(_:)): .downArrow,
        #selector(NSTextView.moveLeft(_:)): .leftArrow,
        #selector(NSTextView.moveLeftAndModifySelection(_:)): .leftArrow,
        #selector(NSTextView.moveBackwardAndModifySelection(_:)): .leftArrow,
        #selector(NSTextView.moveRight(_:)): .rightArrow,
        #selector(NSTextView.moveRightAndModifySelection(_:)): .rightArrow,
        #selector(NSTextView.moveForwardAndModifySelection(_:)): .rightArrow,
        #selector(NSTextView.moveToBeginningOfDocument(_:)): .upArrow,
        #selector(NSTextView.moveToEndOfDocument(_:)): .downArrow,
        #selector(NSTextView.moveToBeginningOfLine(_:)): .leftArrow,
        #selector(NSTextView.moveToBeginningOfLineAndModifySelection(_:)): .leftArrow,
        #selector(NSTextView.moveToLeftEndOfLineAndModifySelection(_:)): .leftArrow,
        #selector(NSTextView.moveWordLeft(_:)): .leftArrow,
        #selector(NSTextView.moveWordBackward(_:)): .leftArrow,
        #selector(NSTextView.moveWordLeftAndModifySelection(_:)): .leftArrow,
        #selector(NSTextView.moveWordBackwardAndModifySelection(_:)): .leftArrow,
        #selector(NSTextView.moveToEndOfLine(_:)): .rightArrow,
        #selector(NSTextView.moveToEndOfLineAndModifySelection(_:)): .rightArrow,
        #selector(NSTextView.moveToRightEndOfLineAndModifySelection(_:)): .rightArrow,
        #selector(NSTextView.moveWordRight(_:)): .rightArrow,
        #selector(NSTextView.moveWordForward(_:)): .rightArrow,
        #selector(NSTextView.moveWordRightAndModifySelection(_:)): .rightArrow,
        #selector(NSTextView.moveWordForwardAndModifySelection(_:)): .rightArrow,
        #selector(NSTextView.insertTab(_:)): .tab,
        #selector(NSTextView.insertBacktab(_:)): .tab,
        #selector(NSTextView.cancelOperation(_:)): .escape
    ]

    init?(event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 || event.charactersIgnoringModifiers == "\r" {
            self = .return
            return
        }
        if event.keyCode == 126 || event.charactersIgnoringModifiers == "\u{F700}" {
            self = .upArrow
            return
        }
        if event.keyCode == 125 || event.charactersIgnoringModifiers == "\u{F701}" {
            self = .downArrow
            return
        }
        if event.keyCode == 123 || event.charactersIgnoringModifiers == "\u{F702}" {
            self = .leftArrow
            return
        }
        if event.keyCode == 124 || event.charactersIgnoringModifiers == "\u{F703}" {
            self = .rightArrow
            return
        }
        if event.keyCode == 48 || event.charactersIgnoringModifiers == "\t" {
            self = .tab
            return
        }
        if event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1B}" {
            self = .escape
            return
        }
        guard let character = event.charactersIgnoringModifiers?.blockInputKeyboardShortcutCharacter else {
            return nil
        }
        self = .character(character)
    }

    init?(selector: Selector) {
        guard let key = Self.selectorMapping[selector] else {
            return nil
        }
        self = key
    }
}

private extension String {
    var blockInputKeyboardShortcutCharacter: String? {
        guard count == 1,
              let scalar = unicodeScalars.first,
              scalar.value >= 0x20,
              !(0xF700...0xF8FF).contains(scalar.value),
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.newlines.contains(scalar) else {
            return nil
        }
        return lowercased()
    }
}
