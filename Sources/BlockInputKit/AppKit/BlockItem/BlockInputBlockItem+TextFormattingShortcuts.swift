import AppKit

extension BlockInputBlockItem {
    func requestTextFormattingShortcut(_ shortcut: BlockInputTextFormattingShortcut) -> Bool {
        guard isEditable,
              let blockID else {
            return false
        }
        return delegate?.blockItem(self, blockID: blockID, didRequestTextFormattingShortcut: shortcut) ?? false
    }

    func textFormattingContextMenuItemStates(selectedRange: NSRange) -> [BlockInputTextFormattingMenuItemState] {
        guard isEditable,
              let blockID else {
            return []
        }
        return delegate?.blockItem(
            self,
            blockID: blockID,
            textFormattingMenuItemStatesForSelectedRange: selectedRange
        ) ?? []
    }

    func textFormattingContextMenuItemStates(for event: NSEvent) -> [BlockInputTextFormattingMenuItemState] {
        guard isEditable,
              let blockID else {
            return []
        }
        return delegate?.blockItem(
            self,
            blockID: blockID,
            textFormattingMenuItemStatesForContextEvent: event
        ) ?? []
    }

    func textFormattingContextMenuItems(for event: NSEvent) -> [NSMenuItem] {
        guard isEditable,
              let delegate else {
            return []
        }
        return textFormattingContextMenuItemStates(for: event).map {
            $0.action.menuItem(target: delegate, state: $0.state)
        }
    }

}
