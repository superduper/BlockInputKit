import AppKit

extension BlockInputView {
    /// Handles the built-in find key equivalents (Cmd+F, Cmd+G, Cmd+Shift+G).
    ///
    /// This runs from `performEditorKeyEquivalentDefaults`, which executes after host
    /// `keyboardShortcuts` dispatch in `performKeyEquivalent(with:)`. A host shortcut registered
    /// for any of these therefore wins before this code is reached. Returns true when consumed.
    func handleFindKeyEquivalent(_ event: NSEvent) -> Bool {
        guard findEnabled,
              let action = findKeyEquivalentAction(for: event) else {
            return false
        }
        switch action {
        case .open:
            presentFindBar()
        case .next:
            findNext()
            findBarView?.updateCount(current: findMatchCount.current, total: findMatchCount.total)
        case .previous:
            findPrevious()
            findBarView?.updateCount(current: findMatchCount.current, total: findMatchCount.total)
        }
        return true
    }

    private func findKeyEquivalentAction(for event: NSEvent) -> BlockInputFindKeyAction? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              !modifiers.contains(.option),
              !modifiers.contains(.control),
              let character = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }
        let hasShift = modifiers.contains(.shift)
        switch character {
        case "f" where !hasShift:
            return .open
        case "g":
            return hasShift ? .previous : .next
        default:
            return nil
        }
    }
}

/// Built-in find key-equivalent action resolved from a Cmd+F/Cmd+G event.
private enum BlockInputFindKeyAction {
    case open
    case next
    case previous
}
