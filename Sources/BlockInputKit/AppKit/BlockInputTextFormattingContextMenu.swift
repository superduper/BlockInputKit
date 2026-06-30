import AppKit

/// Metadata for editor-owned source-formatting context-menu commands.
struct BlockInputTextFormattingMenuAction {
    let shortcut: BlockInputTextFormattingShortcut
    let title: String
    let selector: Selector
    let keyEquivalent: String
    let keyEquivalentModifierMask: NSEvent.ModifierFlags

    static let all: [BlockInputTextFormattingMenuAction] = [
        BlockInputTextFormattingMenuAction(
            shortcut: .bold,
            title: "Bold",
            selector: #selector(BlockInputView.blockInputFormatBold(_:)),
            keyEquivalent: "b",
            keyEquivalentModifierMask: .command
        ),
        BlockInputTextFormattingMenuAction(
            shortcut: .italic,
            title: "Italic",
            selector: #selector(BlockInputView.blockInputFormatItalic(_:)),
            keyEquivalent: "i",
            keyEquivalentModifierMask: .command
        ),
        BlockInputTextFormattingMenuAction(
            shortcut: .underline,
            title: "Underline",
            selector: #selector(BlockInputView.blockInputFormatUnderline(_:)),
            keyEquivalent: "u",
            keyEquivalentModifierMask: .command
        ),
        BlockInputTextFormattingMenuAction(
            shortcut: .strikethrough,
            title: "Strikethrough",
            selector: #selector(BlockInputView.blockInputFormatStrikethrough(_:)),
            keyEquivalent: "x",
            keyEquivalentModifierMask: [.command, .shift]
        )
    ]

    func menuItem(target: AnyObject, state: NSControl.StateValue) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = target
        item.keyEquivalentModifierMask = keyEquivalentModifierMask
        item.state = state
        item.representedObject = shortcut
        return item
    }
}

/// Resolved menu item state for one formatting command and the current eligible selection.
struct BlockInputTextFormattingMenuItemState {
    let action: BlockInputTextFormattingMenuAction
    let state: NSControl.StateValue
}

extension NSMenu {
    func blockInputRemovingSystemFontItems() {
        var removedItem = false
        for (index, item) in items.enumerated().reversed() where item.blockInputIsSystemFontMenu {
            removeItem(at: index)
            removedItem = true
        }
        if removedItem {
            blockInputRemovingRedundantSeparators()
        }
    }

    /// Removes AppKit's rich-text link actions because BlockInput links are Markdown source mutations.
    func blockInputRemovingSystemLinkItems() {
        var removedItem = false
        for (index, item) in items.enumerated().reversed() where item.blockInputIsSystemLinkMenuItem {
            removeItem(at: index)
            removedItem = true
        }
        if removedItem {
            blockInputRemovingRedundantSeparators()
        }
    }

    func blockInputPrependingTextFormattingItems(_ items: [NSMenuItem]) {
        guard !items.isEmpty else {
            return
        }
        let hadExistingItems = !self.items.isEmpty
        for item in items.reversed() {
            insertItem(item, at: 0)
        }
        if hadExistingItems {
            insertItem(.separator(), at: items.count)
            blockInputRemovingRedundantSeparators()
        }
    }

    /// Inserts editor-owned link actions ahead of the system menu while preserving separator cleanup.
    func blockInputPrependingLinkItems(_ items: [NSMenuItem]) {
        guard !items.isEmpty else {
            return
        }
        let hadExistingItems = !self.items.isEmpty
        for item in items.reversed() {
            insertItem(item, at: 0)
        }
        if hadExistingItems {
            insertItem(.separator(), at: items.count)
            blockInputRemovingRedundantSeparators()
        }
    }

    private func blockInputRemovingRedundantSeparators() {
        for (index, item) in items.enumerated().reversed() {
            guard item.isSeparatorItem else {
                continue
            }
            if index == 0 || index == items.count - 1 || items[index - 1].isSeparatorItem {
                removeItem(at: index)
            }
        }
    }
}

private extension NSMenuItem {
    var blockInputIsSystemFontMenu: Bool {
        guard let submenu else {
            return false
        }
        // AppKit localizes default menu titles, so identify its font submenu by the commands it dispatches.
        let submenuActionNames = submenu.items.compactMap { item in
            item.action.map(NSStringFromSelector)
        }
        return submenuActionNames.contains("orderFrontFontPanel:")
            && submenuActionNames.filter { $0 == "addFontTrait:" }.count >= 2
            && submenuActionNames.contains("underline:")
    }

    var blockInputIsSystemLinkMenuItem: Bool {
        guard let action else {
            return false
        }
        // AppKit exposes its default link commands through private selectors, while titles are localized.
        return [
            "_copyLinkFromMenu:",
            "_editLinkFromMenu:",
            "_openLinkFromMenu:",
            "_removeLinkFromMenu:"
        ].contains(NSStringFromSelector(action))
    }
}
