import AppKit

extension BlockInputTextView {
    func systemMenuPreservingSelectedRange(for event: NSEvent) -> NSMenu {
        let selectedRangeBeforeMenu = selectedRange()
        let shouldRestoreSelectedRange = selectedRangeBeforeMenu.length > 0 && window?.firstResponder === self
        let menu = super.menu(for: event) ?? NSMenu()
        // NSTextView can retarget the clicked word while building its default menu; formatting should keep the active selection.
        if shouldRestoreSelectedRange,
           !NSEqualRanges(selectedRange(), selectedRangeBeforeMenu) {
            setSelectedRange(selectedRangeBeforeMenu)
        }
        return menu
    }

    @objc(blockInputFormatBold:)
    func blockInputFormatBold(_ sender: Any?) {
        _ = requestTextFormattingShortcutFromContextMenu(.bold)
    }

    @objc(blockInputFormatItalic:)
    func blockInputFormatItalic(_ sender: Any?) {
        _ = requestTextFormattingShortcutFromContextMenu(.italic)
    }

    @objc(blockInputFormatUnderline:)
    func blockInputFormatUnderline(_ sender: Any?) {
        _ = requestTextFormattingShortcutFromContextMenu(.underline)
    }

    @objc(blockInputFormatStrikethrough:)
    func blockInputFormatStrikethrough(_ sender: Any?) {
        _ = requestTextFormattingShortcutFromContextMenu(.strikethrough)
    }

    func textFormattingMenuItems(for event: NSEvent) -> [NSMenuItem] {
        let selectedRange = blockInputSourceSelectedRange()
        guard selectedRange.length > 0,
              window?.firstResponder === self else {
            return blockItem?.textFormattingContextMenuItems(for: event) ?? []
        }
        return blockItem?.textFormattingContextMenuItemStates(selectedRange: selectedRange).map {
            $0.action.menuItem(target: self, state: $0.state)
        } ?? []
    }

    func linkContextMenuItems(for event: NSEvent) -> [NSMenuItem] {
        return blockItem?.linkContextMenuItems(for: event, selectedRange: blockInputSourceSelectedRange()) ?? []
    }

    private func requestTextFormattingShortcutFromContextMenu(_ shortcut: BlockInputTextFormattingShortcut) -> Bool {
        // Context menu items can outlive the text selection they were created for; stale text views should not rewrite source.
        guard window?.firstResponder === self else {
            return false
        }
        return blockItem?.requestTextFormattingShortcut(shortcut) ?? false
    }
}
