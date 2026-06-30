import AppKit

extension BlockInputEditorCommand {
    init(_ shortcut: BlockInputUndoShortcut) {
        switch shortcut {
        case .undo:
            self = .undo
        case .redo:
            self = .redo
        }
    }

    init(_ shortcut: BlockInputTextFormattingShortcut) {
        switch shortcut {
        case .bold:
            self = .bold
        case .italic:
            self = .italic
        case .underline:
            self = .underline
        case .strikethrough:
            self = .strikethrough
        case .inlineCode:
            self = .formatCode
        }
    }
}

public extension BlockInputView {
    /// Performs a semantic editor command using the current selection or caret as the target.
    @discardableResult
    func performCommand(_ command: BlockInputEditorCommand) -> Bool {
        performCommand(command, context: BlockInputResolvedCommandContext())
    }

    /// Returns whether a semantic editor command can currently run.
    func canPerformCommand(_ command: BlockInputEditorCommand) -> Bool {
        guard isEditable || !command.isMutatingDocument else {
            return false
        }
        if let availability = canPerformUndoOrClipboardCommand(command) {
            return availability
        }
        if let availability = canPerformFormattingCommand(command) {
            return availability
        }
        if let availability = canPerformFormatCodeCommand(command) {
            return availability
        }
        if let availability = canPerformMovementCommand(command) {
            return availability
        }
        if let availability = canPerformLinkCommand(command) {
            return availability
        }
        if let availability = canPerformImageCommand(command) {
            return availability
        }
        if let availability = canPerformTableCommand(command) {
            return availability
        }
        if let availability = canPerformFindCommand(command) {
            return availability
        }
        if let availability = canPerformBlockKindCommand(command) {
            return availability
        }
        return false
    }

    /// Returns toggle state for formatting commands and availability for non-toggle commands.
    func state(for command: BlockInputEditorCommand) -> BlockInputEditorCommandState {
        guard isEditable || !command.isMutatingDocument else {
            return .unavailable
        }
        switch command {
        case .bold:
            return textFormattingCommandState(.bold)
        case .italic:
            return textFormattingCommandState(.italic)
        case .underline:
            return textFormattingCommandState(.underline)
        case .strikethrough:
            return textFormattingCommandState(.strikethrough)
        case .formatCode:
            return formatCodeCommandState()
        case .setBlockKind(let kind):
            return blockKindCommandState(kind)
        default:
            return canPerformCommand(command) ? .off : .unavailable
        }
    }
}

extension BlockInputView {
    func performKeyboardShortcutCommand(for event: NSEvent) -> Bool {
        guard let command = event.blockInputEditorCommandShortcut else {
            return false
        }
        guard isEditable || !command.isMutatingDocument else {
            return command.consumesKeyboardShortcutWhenUnavailable
        }
        let performed = performCommand(command)
        return performed || command.consumesKeyboardShortcutWhenUnavailable
    }

    @discardableResult
    func performCommand(
        _ command: BlockInputEditorCommand,
        context: BlockInputResolvedCommandContext
    ) -> Bool {
        guard isEditable || !command.isMutatingDocument else {
            return false
        }
        if commandShouldFailForFocusedModal(command) {
            return false
        }
        if let performed = performUndoOrClipboardCommand(command, context: context) {
            return performed
        }
        if let performed = performFormattingCommand(command) {
            return performed
        }
        if let performed = performFormatCodeCommand(command) {
            return performed
        }
        if let performed = performMovementCommand(command) {
            return performed
        }
        if let performed = performLinkCommand(command, context: context) {
            return performed
        }
        if let performed = performImageCommand(command, context: context) {
            return performed
        }
        if let performed = performTableCommand(command, context: context) {
            return performed
        }
        if let performed = performFindCommand(command) {
            return performed
        }
        if let performed = performBlockKindCommand(command) {
            return performed
        }
        return false
    }
}

private extension BlockInputEditorCommand {
    var consumesKeyboardShortcutWhenUnavailable: Bool {
        switch self {
        case .bold, .italic, .underline, .strikethrough:
            return true
        default:
            return false
        }
    }

    var textFormattingShortcut: BlockInputTextFormattingShortcut? {
        switch self {
        case .bold:
            return .bold
        case .italic:
            return .italic
        case .underline:
            return .underline
        case .strikethrough:
            return .strikethrough
        default:
            return nil
        }
    }
}

struct BlockInputResolvedCommandContext {
    var preferredBlockID: BlockInputBlockID?
    var linkContext: BlockInputLinkContext?
    var imageContext: BlockInputImageContext?
    var imageBlockID: BlockInputBlockID?
    var imageIndex: Int?
    var tableContext: BlockInputTableMenuContext?

    init(
        preferredBlockID: BlockInputBlockID? = nil,
        linkContext: BlockInputLinkContext? = nil,
        imageContext: BlockInputImageContext? = nil,
        imageBlockID: BlockInputBlockID? = nil,
        imageIndex: Int? = nil,
        tableContext: BlockInputTableMenuContext? = nil
    ) {
        self.preferredBlockID = preferredBlockID
        self.linkContext = linkContext
        self.imageContext = imageContext
        self.imageBlockID = imageBlockID
        self.imageIndex = imageIndex
        self.tableContext = tableContext
    }
}

private extension BlockInputView {
    func canPerformUndoOrClipboardCommand(_ command: BlockInputEditorCommand) -> Bool? {
        switch command {
        case .undo:
            return undoController?.canUndo() == true
        case .redo:
            return undoController?.canRedo() == true
        case .selectAll:
            return activeBlockID != nil
        case .copy, .cut:
            return canCopyActiveSelection()
        case .paste:
            return canPasteIntoActiveSelection
        default:
            return nil
        }
    }

    func canPerformFormattingCommand(_ command: BlockInputEditorCommand) -> Bool? {
        guard let shortcut = command.textFormattingShortcut else {
            return nil
        }
        return textFormattingCommandState(shortcut) != .unavailable
    }

    func canPerformLinkCommand(_ command: BlockInputEditorCommand) -> Bool? {
        switch command {
        case .insertLink(let payload):
            guard let linkContext = resolvedLinkContext(for: command, context: BlockInputResolvedCommandContext()) else {
                return false
            }
            return canPerformInsertLink(payload, context: linkContext)
        case .removeLink:
            return resolvedLinkContext(for: command, context: BlockInputResolvedCommandContext()) != nil
        default:
            return nil
        }
    }

    func canPerformImageCommand(_ command: BlockInputEditorCommand) -> Bool? {
        switch command {
        case .insertImage(let payload):
            return imageContextForActiveSelection() != nil && canPerformInsertImage(payload)
        case .deleteImage:
            return activeImageDeletionBlockID(context: BlockInputResolvedCommandContext()) != nil
        default:
            return nil
        }
    }

    func canPerformTableCommand(_ command: BlockInputEditorCommand) -> Bool? {
        switch command {
        case .insertTable:
            return activeTableInsertionBlockID(context: BlockInputResolvedCommandContext()) != nil
        case .insertRow, .insertColumn, .deleteRow, .deleteColumn:
            return activeTableCommandTarget(context: BlockInputResolvedCommandContext(), command: command) != nil
        case .deleteTable:
            return activeTableDeletionBlockID(context: BlockInputResolvedCommandContext()) != nil
        default:
            return nil
        }
    }

    func performUndoOrClipboardCommand(
        _ command: BlockInputEditorCommand,
        context: BlockInputResolvedCommandContext
    ) -> Bool? {
        switch command {
        case .undo:
            return performUndoShortcut(.undo, preferredBlockID: context.preferredBlockID)
        case .redo:
            return performUndoShortcut(.redo, preferredBlockID: context.preferredBlockID)
        case .selectAll:
            return selectAllFromActiveSelection()
        case .copy:
            return copyActiveSelection()
        case .cut:
            return cutActiveSelection()
        case .paste:
            return pasteIntoActiveSelection()
        default:
            return nil
        }
    }

    func performFormattingCommand(_ command: BlockInputEditorCommand) -> Bool? {
        guard let shortcut = command.textFormattingShortcut else {
            return nil
        }
        return performTextFormattingShortcut(shortcut)
    }

    func performLinkCommand(
        _ command: BlockInputEditorCommand,
        context: BlockInputResolvedCommandContext
    ) -> Bool? {
        switch command {
        case .insertLink(let payload):
            return performInsertLink(payload, context: context)
        case .removeLink:
            return performRemoveLink(context: context)
        default:
            return nil
        }
    }

    func performImageCommand(
        _ command: BlockInputEditorCommand,
        context: BlockInputResolvedCommandContext
    ) -> Bool? {
        switch command {
        case .insertImage(let payload):
            return performInsertImage(payload, context: context)
        case .deleteImage:
            return performDeleteImage(context: context)
        default:
            return nil
        }
    }

    func performTableCommand(
        _ command: BlockInputEditorCommand,
        context: BlockInputResolvedCommandContext
    ) -> Bool? {
        switch command {
        case .insertTable:
            return activeTableInsertionBlockID(context: context).map { insertTable(after: $0) } ?? false
        case .insertRow, .insertColumn, .deleteRow, .deleteColumn:
            return performTableCellCommand(command, context: context)
        case .deleteTable:
            return activeTableDeletionBlockID(context: context).map { deleteTable(blockID: $0) } ?? false
        default:
            return nil
        }
    }

    func performTableCellCommand(
        _ command: BlockInputEditorCommand,
        context: BlockInputResolvedCommandContext
    ) -> Bool {
        guard let target = activeTableCommandTarget(context: context, command: command) else {
            return false
        }
        switch command {
        case .insertRow:
            return insertTableBodyRow(blockID: target.blockID, position: target.position)
        case .insertColumn:
            return insertTableColumn(blockID: target.blockID, position: target.position)
        case .deleteRow:
            return deleteTableBodyRow(blockID: target.blockID, position: target.position, keepsLastBodyRow: true)
        case .deleteColumn:
            return deleteTableColumn(blockID: target.blockID, position: target.position)
        default:
            return false
        }
    }

    func canPerformFindCommand(_ command: BlockInputEditorCommand) -> Bool? {
        switch command {
        case .findNext, .findPrevious:
            return findEnabled && findMatchCount.total > 0
        default:
            return nil
        }
    }

    func performFindCommand(_ command: BlockInputEditorCommand) -> Bool? {
        switch command {
        case .findNext:
            return findNext()
        case .findPrevious:
            return findPrevious()
        default:
            return nil
        }
    }

    var canPasteIntoActiveSelection: Bool {
        switch selection {
        case .cursor, .text:
            return true
        case .blocks, .mixed, nil:
            return false
        }
    }
}
