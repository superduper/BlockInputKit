import Foundation

/// Controls whether insert commands mutate immediately or present editor UI.
public enum BlockInputCommandPresentation: String, Equatable, Codable, Sendable {
    /// Mutate directly when enough command data is supplied; otherwise present editor UI.
    case automatic
    /// Present editor UI even when command data is supplied.
    case modal
}

/// Payload for programmatic link insertion.
public struct BlockInputInsertLinkCommand: Equatable, Codable, Sendable {
    /// Optional label to place in the link modal or inserted Markdown.
    public var text: String?
    /// Optional destination URL string.
    public var urlString: String?
    /// Presentation behavior for the command.
    public var presentation: BlockInputCommandPresentation

    /// Creates a link insertion command payload.
    public init(
        text: String? = nil,
        urlString: String? = nil,
        presentation: BlockInputCommandPresentation = .automatic
    ) {
        self.text = text
        self.urlString = urlString
        self.presentation = presentation
    }
}

/// Payload for programmatic image insertion.
public struct BlockInputInsertImageCommand: Equatable, Codable, Sendable {
    /// Optional image source URL string.
    public var source: String?
    /// Optional image alternate text.
    public var altText: String?
    /// Presentation behavior for the command.
    public var presentation: BlockInputCommandPresentation

    /// Creates an image insertion command payload.
    public init(
        source: String? = nil,
        altText: String? = nil,
        presentation: BlockInputCommandPresentation = .automatic
    ) {
        self.source = source
        self.altText = altText
        self.presentation = presentation
    }
}

/// Programmatic editor commands that mirror BlockInputKit-owned shortcut and context-menu actions.
public enum BlockInputEditorCommand: Equatable, Codable, Sendable {
    /// Undo the most recent editor text or structural edit.
    case undo
    /// Redo the most recently undone editor text or structural edit.
    case redo
    /// Select all editable document content from the current editor context.
    case selectAll
    /// Copy the active text, block, or mixed selection to the pasteboard.
    case copy
    /// Cut the active text, block, or mixed selection to the pasteboard.
    case cut
    /// Paste pasteboard content into the active text selection or caret.
    case paste
    /// Toggle bold inline formatting for the active text selection.
    case bold
    /// Toggle italic inline formatting for the active text selection.
    case italic
    /// Toggle underline inline formatting for the active text selection.
    case underline
    /// Toggle strikethrough inline formatting for the active text selection.
    case strikethrough
    /// Toggle code formatting for the active text selection.
    ///
    /// When the selection spans multiple lines (contains a newline), the active block is converted
    /// to a fenced code block (toggling back to a paragraph when it is already code). When the
    /// selection is single-line, it toggles inline code (single backticks) around the selection.
    case formatCode
    /// Insert or edit a Markdown link using the supplied command payload.
    case insertLink(BlockInputInsertLinkCommand = BlockInputInsertLinkCommand())
    /// Remove the active Markdown link when the current context targets one.
    case removeLink
    /// Insert an image block using the supplied command payload.
    case insertImage(BlockInputInsertImageCommand = BlockInputInsertImageCommand())
    /// Delete the active image block when the current context targets one.
    case deleteImage
    /// Insert a default table after the active block when table insertion is available.
    case insertTable
    /// Insert a body row next to the active table cell.
    case insertRow
    /// Insert a column next to the active table cell.
    case insertColumn
    /// Delete the active table body row, preserving a final empty body row.
    case deleteRow
    /// Delete the active table column.
    case deleteColumn
    /// Delete the active table block.
    case deleteTable
    /// Change the active block's kind to the supplied kind, keeping its text content.
    ///
    /// The editor renders kind-specific prefixes (heading, list marker, quote, code fence)
    /// from the block kind, so the block text is preserved verbatim. ``state(for:)`` reports
    /// `.on` when the active block already has the requested kind, comparing heading levels
    /// while ignoring numbered-list start values and checklist checked state.
    case setBlockKind(BlockInputBlockKind)

    // MARK: Cursor movement (non-mutating)

    /// Move caret one character left within the active block.
    case moveLeft
    /// Move caret one character right within the active block.
    case moveRight
    /// Move caret one visual line up, crossing block boundaries.
    case moveUp
    /// Move caret one visual line down, crossing block boundaries.
    case moveDown
    /// Move caret one word left within the active block.
    case moveWordLeft
    /// Move caret one word right within the active block.
    case moveWordRight
    /// Move caret to the start of the current line.
    case moveToLineStart
    /// Move caret to the end of the current line.
    case moveToLineEnd
    /// Move caret to the start of the document.
    case moveToDocumentStart
    /// Move caret to the end of the document.
    case moveToDocumentEnd
    /// Extend selection one character left.
    case extendSelectionLeft
    /// Extend selection one character right.
    case extendSelectionRight
    /// Extend selection one visual line up, crossing block boundaries.
    case extendSelectionUp
    /// Extend selection one visual line down, crossing block boundaries.
    case extendSelectionDown
    /// Extend selection one word left.
    case extendSelectionWordLeft
    /// Extend selection one word right.
    case extendSelectionWordRight
    /// Extend selection to the start of the current line.
    case extendSelectionToLineStart
    /// Extend selection to the end of the current line.
    case extendSelectionToLineEnd
    /// Delete the word to the left of the caret.
    case deleteWordBackward
    /// Delete the word to the right of the caret.
    case deleteWordForward
    /// Delete from the caret to the end of the current line.
    case deleteToLineEnd
    /// Delete the single character to the right of the caret (vim `x`).
    case deleteCharForward
    /// Delete the single character to the left of the caret (vim `X`).
    case deleteCharBackward

    // MARK: Block insertion

    /// Insert a new empty paragraph block below the active block and move the caret into it (vim `o`).
    case insertBlockBelow
    /// Insert a new empty paragraph block above the active block and move the caret into it (vim `O`).
    case insertBlockAbove
    /// Insert a new block with a specific kind and text below the active block (vim register paste `p`).
    case insertBlockBelowWithContent(kind: BlockInputBlockKind, text: String)

    // MARK: Block operations

    /// Delete the active block and move the caret to the adjacent block (vim `dd`).
    case deleteCurrentBlock
    /// Select the active block as a whole-block selection (vim `V`).
    case selectCurrentBlock
    /// Move the caret to the start of the block immediately after the active block.
    case moveAfterCurrentBlock
    /// Move the caret to the start of the block immediately before the active block.
    case moveBeforeCurrentBlock

    // MARK: Paragraph / indent

    /// Move the caret to the very start of the current block's text content, ignoring visual line wrapping (vim `0`).
    case moveToBlockContentStart
    /// Move the caret to the very end of the current block's text content, ignoring visual line wrapping (vim `$`).
    case moveToBlockContentEnd
    /// Extend the selection to the very start of the current block's text content (vim visual `0`).
    case extendSelectionToBlockContentStart
    /// Extend the selection to the very end of the current block's text content (vim visual `$`).
    case extendSelectionToBlockContentEnd
    /// Increase the indent level of the active block (equivalent to Tab; vim `>`).
    case increaseIndent
    /// Decrease the indent level of the active block (equivalent to Shift-Tab; vim `<`).
    case decreaseIndent
    /// Insert a literal newline character at the current cursor position without splitting the block (vim `o` within a block).
    case insertLineBreak

    // MARK: Find

    /// Advance to the next find match with wrap-around (Cmd+G, vim `n`).
    case findNext
    /// Move to the previous find match with wrap-around (Cmd+Shift+G, vim `N`).
    case findPrevious
}

/// Availability or toggle state for a command.
public enum BlockInputEditorCommandState: String, Equatable, Codable, Sendable {
    /// The command cannot run in the current editor context.
    case unavailable
    /// The command is available and its toggle state is inactive, or it is a non-toggle command.
    case off
    /// The command is available and its toggle state is active.
    case on
}

/// SwiftUI-friendly command bridge bound to the currently mounted editor view.
@MainActor
public final class BlockInputEditorCommandDispatcher {
    private weak var editorView: BlockInputView?

    /// Creates an unbound dispatcher. Pass it through ``BlockInputConfiguration`` to bind it to a mounted editor.
    public init() {}

    /// Performs a command on the mounted editor.
    @discardableResult
    public func perform(_ command: BlockInputEditorCommand) -> Bool {
        editorView?.performCommand(command) ?? false
    }

    /// Returns whether the mounted editor can currently perform a command.
    public func canPerform(_ command: BlockInputEditorCommand) -> Bool {
        editorView?.canPerformCommand(command) ?? false
    }

    /// Returns the mounted editor's current command state.
    public func state(for command: BlockInputEditorCommand) -> BlockInputEditorCommandState {
        editorView?.state(for: command) ?? .unavailable
    }

    func bind(to editorView: BlockInputView) {
        self.editorView = editorView
    }

    func unbind(from editorView: BlockInputView) {
        guard self.editorView === editorView else {
            return
        }
        self.editorView = nil
    }
}
