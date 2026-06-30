import AppKit

extension BlockInputTextView {
    func dispatchKeyboardShortcut(
        event: NSEvent,
        focusSource: BlockInputKeyboardShortcutFocusSource
    ) -> BlockInputKeyboardShortcutDispatchResult {
        guard !hasMarkedText(),
              !isSkippingKeyboardShortcutDispatch(for: event),
              let shortcut = BlockInputKeyboardShortcut(event: event) else {
            return .notRegistered
        }
        return blockItem?.requestKeyboardShortcut(
            shortcut,
            selectedRange: blockInputSourceSelectedRange(),
            focusSource: focusSource,
            isRepeat: event.isARepeat,
            performDefault: { [weak self] shortcut in
                self?.performDefaultKeyboardShortcut(shortcut) == true
            }
        ) ?? .notRegistered
    }

    func dispatchKeyboardShortcut(
        selector: Selector,
        focusSource: BlockInputKeyboardShortcutFocusSource
    ) -> BlockInputKeyboardShortcutDispatchResult {
        guard !hasMarkedText(),
              !isSkippingKeyboardShortcutDispatchForCurrentEvent(),
              let shortcut = BlockInputKeyboardShortcut(selector: selector) else {
            return .notRegistered
        }
        let event = NSApp.currentEvent
        return blockItem?.requestKeyboardShortcut(
            shortcut,
            selectedRange: blockInputSourceSelectedRange(),
            focusSource: focusSource,
            isRepeat: event?.type == .keyDown && event?.isARepeat == true,
            performDefault: { [weak self] shortcut in
                self?.performDefaultKeyboardShortcut(shortcut) == true
            }
        ) ?? .notRegistered
    }

    func performDefaultKeyboardShortcut(_ shortcut: BlockInputKeyboardShortcut) -> Bool {
        if let direction = shortcut.lineBoundarySelectionDirection {
            return requestLineBoundarySelectionFromOwningBlock(direction)
        }
        guard shortcut == .returnKey else {
            return false
        }
        if blockItem?.isTableCellTextView(self) == true {
            return blockItem?.handleTableCellCommand(#selector(insertNewline(_:)), selectedRange: selectedRange()) == true
        }
        guard let blockItem else {
            return false
        }
        if blockItem.requestReturn() {
            return true
        }
        super.doCommand(by: #selector(insertNewline(_:)))
        return true
    }

    func performKeyEquivalentDefaults(with event: NSEvent) -> Bool {
        if event.blockInputIsSelectAllShortcut,
           let blockItem {
            blockItem.requestSelectAll()
            return true
        }
        if let undoShortcut = event.blockInputUndoShortcut,
           blockItem?.requestUndoShortcut(undoShortcut) == true {
            return true
        }
        if let formattingShortcut = event.blockInputTextFormattingShortcut {
            _ = blockItem?.requestTextFormattingShortcut(formattingShortcut)
            return true
        }
        if handleTableCellKeyEquivalent(event) {
            return true
        }
        if handleNonTableSelectionKeyEquivalent(event) {
            return true
        }
        if handleWordMovementShortcut(event) {
            return true
        }
        if event.blockInputIsCopyShortcut {
            if blockItem?.requestCopyActiveSelection() == true || copySelectedPlainText(allowingEditorRoute: false) {
                return true
            }
        }
        if event.blockInputIsCutShortcut {
            cut(nil)
            return true
        }
        if event.blockInputIsPasteShortcut {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func performTableCellCommandDefaults(_ selector: Selector) {
        if handleLocalInlineLinkHorizontalSelectionCommand(selector) {
            BlockInputSelectionDebug.emit("text command consumed table inline link selector=\(selector)")
            return
        }
        if blockItem?.handleTableCellCommand(selector, selectedRange: selectedRange()) == true {
            BlockInputSelectionDebug.emit("text command consumed table selector=\(selector)")
            return
        }
        if handleBoundaryCommand(selector) {
            BlockInputSelectionDebug.emit("text command consumed table boundary selector=\(selector)")
            return
        }
        super.doCommand(by: selector)
    }

    func performNonTableCommandDefaults(_ selector: Selector) {
        if handleBlockCommand(selector) ||
            handleDocumentBoundaryCommand(selector) ||
            handleLineBoundarySelectionCommand(selector) ||
            handleSelectionExpansionCommand(selector) ||
            handleHorizontalSelectionAdjustmentCommand(selector) ||
            handleWordSelectionAdjustmentCommand(selector) ||
            handleWordMovementCommand(selector) ||
            handleLinkBoundaryMovementCommand(selector) ||
            handleBoundaryCommand(selector) {
            BlockInputSelectionDebug.emit("text command consumed selector=\(selector)")
            return
        }
        super.doCommand(by: selector)
    }

    func performKeyboardShortcutContinuationAfterIgnoredEvent<T>(_ event: NSEvent, _ continuation: () -> T) -> T {
        let eventID = ObjectIdentifier(event)
        isIgnoringShortcutDispatch = true
        ignoredKeyboardShortcutEventIDs.insert(eventID)
        defer {
            ignoredKeyboardShortcutEventIDs.remove(eventID)
            isIgnoringShortcutDispatch = false
        }
        return continuation()
    }

    func handleKeyboardShortcutDispatchResult(
        _ result: BlockInputKeyboardShortcutDispatchResult,
        event: NSEvent,
        continuation: () -> Void
    ) -> Bool {
        switch result {
        case .handled:
            return true
        case .ignored:
            performKeyboardShortcutContinuationAfterIgnoredEvent(event, continuation)
            return true
        case .notRegistered:
            return false
        }
    }

    private func isSkippingKeyboardShortcutDispatch(for event: NSEvent) -> Bool {
        ignoredKeyboardShortcutEventIDs.contains(ObjectIdentifier(event))
    }

    private func isSkippingKeyboardShortcutDispatchForCurrentEvent() -> Bool {
        if isIgnoringShortcutDispatch {
            return true
        }
        guard let event = NSApp.currentEvent,
              event.type == .keyDown else {
            return false
        }
        return isSkippingKeyboardShortcutDispatch(for: event)
    }
}
