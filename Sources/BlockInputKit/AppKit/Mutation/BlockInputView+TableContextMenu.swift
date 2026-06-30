import AppKit

struct BlockInputTableMenuContext {
    var blockID: BlockInputBlockID
    var position: BlockInputTable.CellPosition?
}

extension BlockInputView {
    func tableContextMenuItems(blockID: BlockInputBlockID, selectedRange: NSRange, event: NSEvent) -> [NSMenuItem] {
        guard isEditable else {
            return []
        }
        guard let block = block(withID: blockID) else {
            return []
        }
        if block.kind.allowsTableContextInsertion {
            return [tableMenuItem(
                title: "Insert Table",
                action: #selector(blockInputInsertTableFromMenu(_:)),
                context: BlockInputTableMenuContext(blockID: blockID)
            )]
        }
        guard block.kind == .table,
              let table = BlockInputTable(markdown: block.text) else {
            return []
        }
        let position = tableMenuCellPosition(table: table, blockID: blockID, selectedRange: selectedRange, event: event)
        var items: [NSMenuItem] = []
        items.append(contentsOf: tableInsertionMenuItems(blockID: blockID, position: position))
        if let position,
           case .body = position.row,
           table.bodyRows.count > 1 {
            items.append(tableMenuItem(
                title: "Delete Row",
                action: #selector(blockInputDeleteTableRowFromMenu(_:)),
                context: BlockInputTableMenuContext(blockID: blockID, position: position)
            ))
        }
        if let position,
           table.columnCount > 1 {
            items.append(tableMenuItem(
                title: "Delete Column",
                action: #selector(blockInputDeleteTableColumnFromMenu(_:)),
                context: BlockInputTableMenuContext(blockID: blockID, position: position)
            ))
        }
        items.append(tableMenuItem(
            title: "Delete Table",
            action: #selector(blockInputDeleteTableFromMenu(_:)),
            context: BlockInputTableMenuContext(blockID: blockID, position: position)
        ))
        return items
    }

    @objc(blockInputInsertTableFromMenu:)
    func blockInputInsertTableFromMenu(_ sender: Any?) {
        guard let context = (sender as? NSMenuItem)?.representedObject as? BlockInputTableMenuContext else {
            return
        }
        _ = performCommand(.insertTable, context: .init(tableContext: context))
    }

    @objc(blockInputInsertTableRowFromMenu:)
    func blockInputInsertTableRowFromMenu(_ sender: Any?) {
        guard let context = (sender as? NSMenuItem)?.representedObject as? BlockInputTableMenuContext,
              context.position != nil else {
            return
        }
        _ = performCommand(.insertRow, context: .init(tableContext: context))
    }

    @objc(blockInputInsertTableColumnFromMenu:)
    func blockInputInsertTableColumnFromMenu(_ sender: Any?) {
        guard let context = (sender as? NSMenuItem)?.representedObject as? BlockInputTableMenuContext,
              context.position != nil else {
            return
        }
        _ = performCommand(.insertColumn, context: .init(tableContext: context))
    }

    @objc(blockInputDeleteTableRowFromMenu:)
    func blockInputDeleteTableRowFromMenu(_ sender: Any?) {
        guard let context = (sender as? NSMenuItem)?.representedObject as? BlockInputTableMenuContext,
              context.position != nil else {
            return
        }
        _ = performCommand(.deleteRow, context: .init(tableContext: context))
    }

    @objc(blockInputDeleteTableColumnFromMenu:)
    func blockInputDeleteTableColumnFromMenu(_ sender: Any?) {
        guard let context = (sender as? NSMenuItem)?.representedObject as? BlockInputTableMenuContext,
              context.position != nil else {
            return
        }
        _ = performCommand(.deleteColumn, context: .init(tableContext: context))
    }

    @objc(blockInputDeleteTableFromMenu:)
    func blockInputDeleteTableFromMenu(_ sender: Any?) {
        guard let context = (sender as? NSMenuItem)?.representedObject as? BlockInputTableMenuContext else {
            return
        }
        _ = performCommand(.deleteTable, context: .init(tableContext: context))
    }

    private func tableMenuCellPosition(
        table: BlockInputTable,
        blockID: BlockInputBlockID,
        selectedRange: NSRange,
        event: NSEvent
    ) -> BlockInputTable.CellPosition? {
        let clickedOffset = visibleItem(for: blockID, refreshConfiguration: false)?
            .utf16Offset(atWindowLocation: event.locationInWindow)
        if let clickedOffset,
           let position = table.cellPosition(containingSourceRange: NSRange(location: clickedOffset, length: 0)) {
            return position
        }
        return table.cellPosition(containingSourceRange: selectedRange)
    }

    private func tableMenuItem(
        title: String,
        action: Selector,
        context: BlockInputTableMenuContext
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = context
        if title.hasPrefix("Delete") {
            item.setAccessibilityLabel(title)
            item.setAccessibilityHelp("\(title) from the current table.")
        }
        return item
    }

    private func tableInsertionMenuItems(
        blockID: BlockInputBlockID,
        position: BlockInputTable.CellPosition?
    ) -> [NSMenuItem] {
        guard let position else {
            return []
        }
        return [
            tableMenuItem(
                title: "Insert Row",
                action: #selector(blockInputInsertTableRowFromMenu(_:)),
                context: BlockInputTableMenuContext(blockID: blockID, position: position)
            ),
            tableMenuItem(
                title: "Insert Column",
                action: #selector(blockInputInsertTableColumnFromMenu(_:)),
                context: BlockInputTableMenuContext(blockID: blockID, position: position)
            )
        ]
    }
}

extension BlockInputBlockKind {
    var allowsTableContextInsertion: Bool {
        switch self {
        case .paragraph, .heading, .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return false
        }
    }
}
