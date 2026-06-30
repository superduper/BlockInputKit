import AppKit

/// Inline link variant routed to a host inline-link click handler.
public enum BlockInputInlineLinkKind: Equatable {
    /// A regular Markdown `[label](url)` link.
    case plainLink
    /// A file-link chip.
    case fileChip
    /// A slash-command chip (link-backed or raw `/command`).
    case slashCommand
    /// A registered custom inline markup; associated value is the provider `identifier`.
    case customMarkup(String)
}

/// Host decision for an inline-link click. Reuses the slash-command chip click action vocabulary.
public typealias BlockInputInlineLinkClickAction = BlockInputSlashCommandChipClickAction

/// Context sent when any inline link or chip is clicked.
public struct BlockInputInlineLinkClickContext {
    /// Classified link kind for the clicked range.
    public var kind: BlockInputInlineLinkKind
    /// Resolved destination URL for the clicked link.
    public var destination: URL
    /// Alias captured for custom markup that distinguishes a target from its display label, when present.
    public var alias: String?
    /// Visible label for the clicked link.
    public var label: String
    /// Block that contains the clicked link.
    public var blockID: BlockInputBlockID
    /// Full Markdown source range for the clicked link.
    public var sourceRange: NSRange
    /// Editor view routing the click.
    public var editorView: BlockInputView
    /// Original AppKit mouse event.
    public var event: NSEvent
    /// Normalized click kind.
    public var clickKind: BlockInputSlashCommandChipClickKind

    /// Creates host click context for an inline link.
    public init(
        kind: BlockInputInlineLinkKind,
        destination: URL,
        alias: String?,
        label: String,
        blockID: BlockInputBlockID,
        sourceRange: NSRange,
        editorView: BlockInputView,
        event: NSEvent,
        clickKind: BlockInputSlashCommandChipClickKind
    ) {
        self.kind = kind
        self.destination = destination
        self.alias = alias
        self.label = label
        self.blockID = blockID
        self.sourceRange = sourceRange
        self.editorView = editorView
        self.event = event
        self.clickKind = clickKind
    }
}
