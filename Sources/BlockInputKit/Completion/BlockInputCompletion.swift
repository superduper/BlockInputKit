import Foundation

/// Completion mode requested by a block editor.
public enum BlockInputCompletionTrigger: Equatable, Codable, Sendable {
    /// Mention completion triggered by inline mention text.
    case mention
    /// Slash-command completion triggered by inline slash-command text.
    case slashCommand
    /// Host-registered token trigger; the associated value is `BlockInputCompletionTokenTrigger.identifier`.
    case custom(String)
}

/// A registrable completion trigger fed by a literal opening token (e.g. a multi-character bracket pair, or ":" for emoji).
///
/// Core does a backwards search for `openingToken` before the caret (handling multi-char tokens that single-char
/// boundary detection misses), extracts the query between the token and the caret, optionally extends the replacement
/// across a trailing `closingToken`, and drives the SAME popup as `@`/`/` with `BlockInputCompletionTrigger.custom(id)`.
public struct BlockInputCompletionTokenTrigger: Equatable, Sendable {
    /// Trigger identity; surfaces as `.custom(identifier)` in the completion context and suggestions.
    public var identifier: String
    /// Literal opening token searched for before the caret.
    public var openingToken: String
    /// Optional literal closing token; when the caret is immediately before it, the replacement range extends across it
    /// (so accepting a suggestion replaces the whole token pair, not just the opening half plus query).
    public var closingToken: String?
    /// Substrings that, if present in the query between token and caret, abort the trigger (e.g. an already-closed or
    /// re-opened token so the trigger doesn't mis-fire). Core checks `query.contains(_:)` for each.
    public var abortingSubstrings: [String]
    /// How to derive the provider query from the raw inner text. `.verbatim` passes the inner text unchanged;
    /// `.beforeFirst(separator)` takes the component before a separator.
    public var query: BlockInputCompletionTokenQuery

    public init(
        identifier: String,
        openingToken: String,
        closingToken: String? = nil,
        abortingSubstrings: [String] = [],
        query: BlockInputCompletionTokenQuery = .verbatim
    ) {
        self.identifier = identifier
        self.openingToken = openingToken
        self.closingToken = closingToken
        self.abortingSubstrings = abortingSubstrings
        self.query = query
    }
}

/// How a `BlockInputCompletionTokenTrigger` derives the provider query from the raw inner text.
public enum BlockInputCompletionTokenQuery: Equatable, Sendable {
    /// Pass the inner text unchanged.
    case verbatim
    /// Take the substring before the first `separator` (e.g. a `|` that splits target from display label).
    case beforeFirst(separator: Character)
}

/// Where live slash-command completion is allowed to open.
public enum BlockInputSlashCommandAvailability: String, CaseIterable, Equatable, Codable, Sendable {
    /// Only allow slash-command completion when `/` starts the first block.
    case documentStart
    /// Allow slash-command completion after token boundaries in any inline-capable text block.
    case anywhere
}

/// Source inserted when accepting a slash-command completion suggestion.
public enum BlockInputSlashCommandInsertionStyle: String, CaseIterable, Equatable, Codable, Sendable {
    /// Insert a Markdown link whose label renders as a slash-command chip.
    case markdownLink
    /// Insert the raw slash-command token text.
    case rawToken
}

/// Return-key behavior while the editor-owned completion popup is active.
public enum BlockInputCompletionReturnBehavior: String, CaseIterable, Equatable, Codable, Sendable {
    /// Return accepts the highlighted suggestion when one is available.
    case acceptHighlightedSuggestion
    /// Return passes through when the replacement text already exactly matches the highlighted suggestion.
    case passthroughExactMatch
}

/// Where the editor-owned completion popup should be shown.
public enum BlockInputCompletionPopupPlacement: String, CaseIterable, Equatable, Codable, Sendable {
    /// Anchor the popup near the active text caret.
    case caret
    /// Host the popup in an overlay surface, optionally with a host-provided parent view and frame.
    case overlay
}

/// Parsed path intent for file mention completion queries.
public struct BlockInputCompletionFileQuery: Equatable, Sendable {
    /// Directory shorthand typed before the path query.
    public enum DirectoryReference: String, Equatable, Codable, Sendable {
        /// Query resolves from the current directory shorthand.
        case current
        /// Query resolves from the parent directory shorthand.
        case parent
        /// Query resolves from the grandparent directory shorthand.
        case grandparent
    }

    /// Directory shorthand typed before the path query, when present.
    public var directoryReference: DirectoryReference?
    /// Number of parent-directory hops represented by the shorthand.
    public var levelsUp: Int
    /// Query text after the directory shorthand.
    public var remainder: String

    /// Creates parsed file-query intent for a mention completion request.
    public init(
        directoryReference: DirectoryReference?,
        levelsUp: Int,
        remainder: String
    ) {
        self.directoryReference = directoryReference
        self.levelsUp = levelsUp
        self.remainder = remainder
    }
}

/// Host-provided context for mention and slash-command completion lookups.
public struct BlockInputCompletionContext: Equatable, Sendable {
    /// Completion trigger currently being resolved.
    public var trigger: BlockInputCompletionTrigger
    /// User-entered query text after the trigger.
    public var query: String
    /// Current document snapshot.
    public var document: BlockInputDocument
    /// Block that owns the completion request.
    public var blockID: BlockInputBlockID
    /// Current AppKit text selection range, when available.
    public var selectedRange: NSRange?
    /// Source range that accepting a suggestion should replace, when known.
    public var replacementRange: NSRange?
    /// Raw query text after the trigger before editor-owned normalization.
    public var rawQuery: String
    /// Parsed file path intent for mention completions, when available.
    public var fileQuery: BlockInputCompletionFileQuery?

    /// Creates host completion lookup context for the active editor request.
    public init(
        trigger: BlockInputCompletionTrigger,
        query: String,
        document: BlockInputDocument,
        blockID: BlockInputBlockID,
        selectedRange: NSRange? = nil,
        replacementRange: NSRange? = nil,
        rawQuery: String? = nil,
        fileQuery: BlockInputCompletionFileQuery? = nil
    ) {
        self.trigger = trigger
        self.query = query
        self.document = document
        self.blockID = blockID
        self.selectedRange = selectedRange
        self.replacementRange = replacementRange
        self.rawQuery = rawQuery ?? query
        self.fileQuery = fileQuery
    }
}

/// A selectable completion row supplied by the host app.
public struct BlockInputCompletionSuggestion: Equatable, Identifiable, Sendable {
    /// Stable suggestion identity.
    public var id: String
    /// Primary text shown for the suggestion.
    public var title: String
    /// Optional secondary text shown for the suggestion.
    public var subtitle: String?
    /// Text inserted when the suggestion is accepted.
    public var insertionText: String
    /// Optional text used for `.passthroughExactMatch`; defaults to `insertionText`.
    public var exactMatchText: String?
    /// Trigger this suggestion is intended to satisfy.
    public var trigger: BlockInputCompletionTrigger
    /// Optional SF Symbol name shown by built-in completion UI.
    public var iconSystemName: String?
    /// Optional trailing detail shown by built-in completion UI.
    public var detailText: String?
    /// Character ranges in `title` that matched the query, for needle highlighting.
    public var titleMatchRanges: [NSRange]
    /// Character ranges in `subtitle` that matched the query, for needle highlighting.
    public var subtitleMatchRanges: [NSRange]

    /// Creates a host-provided completion suggestion.
    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        insertionText: String,
        exactMatchText: String? = nil,
        trigger: BlockInputCompletionTrigger,
        iconSystemName: String? = nil,
        detailText: String? = nil,
        titleMatchRanges: [NSRange] = [],
        subtitleMatchRanges: [NSRange] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.insertionText = insertionText
        self.exactMatchText = exactMatchText
        self.trigger = trigger
        self.iconSystemName = iconSystemName
        self.detailText = detailText
        self.titleMatchRanges = titleMatchRanges
        self.subtitleMatchRanges = subtitleMatchRanges
    }

    /// Builds a mention suggestion that inserts a Markdown file link followed by a space.
    public static func fileLink(
        id: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        label: String,
        fileURL: URL,
        trigger: BlockInputCompletionTrigger = .mention,
        iconSystemName: String? = "doc.text",
        detailText: String? = nil
    ) -> BlockInputCompletionSuggestion {
        let destination = fileURL.absoluteString
        return BlockInputCompletionSuggestion(
            id: id ?? destination,
            title: title ?? label,
            subtitle: subtitle,
            insertionText: "[\(Self.escapedMarkdownLinkLabel(label))](\(Self.escapedMarkdownLinkDestination(destination))) ",
            trigger: trigger,
            iconSystemName: iconSystemName,
            detailText: detailText
        )
    }

    /// Builds a mention suggestion that inserts a Markdown file link labeled with the file name followed by a space.
    public static func fileLink(
        id: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        fileURL: URL,
        trigger: BlockInputCompletionTrigger = .mention,
        iconSystemName: String? = "doc.text",
        detailText: String? = nil
    ) -> BlockInputCompletionSuggestion {
        fileLink(
            id: id,
            title: title,
            subtitle: subtitle,
            label: Self.defaultFileLinkLabel(for: fileURL),
            fileURL: fileURL,
            trigger: trigger,
            iconSystemName: iconSystemName,
            detailText: detailText
        )
    }

    /// Builds a slash-command suggestion that inserts slash-command source followed by a space.
    ///
    /// The visible label is normalized to begin with `/`. By default the inserted source is a Markdown link that
    /// renders as a slash-command chip; use `.rawToken` when the underlying Markdown should stay as raw `/command` text.
    public static func slashCommand(
        id: String? = nil,
        title: String,
        subtitle: String? = nil,
        uri: String,
        label: String? = nil,
        insertionStyle: BlockInputSlashCommandInsertionStyle = .markdownLink,
        iconSystemName: String? = "command",
        detailText: String? = nil
    ) -> BlockInputCompletionSuggestion {
        let chipLabel = Self.normalizedSlashCommandLabel(label ?? title)
        return BlockInputCompletionSuggestion(
            id: id ?? uri,
            title: title,
            subtitle: subtitle,
            insertionText: Self.slashCommandInsertionText(label: chipLabel, uri: uri, insertionStyle: insertionStyle),
            exactMatchText: chipLabel,
            trigger: .slashCommand,
            iconSystemName: iconSystemName,
            detailText: detailText
        )
    }

}

/// Supplies mention and slash-command completions to the editor.
public protocol BlockInputCompletionProvider: AnyObject, Sendable {
    /// Returns suggestions for the active completion context.
    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion]
}

private extension BlockInputCompletionSuggestion {
    static func defaultFileLinkLabel(for fileURL: URL) -> String {
        let name = fileURL.lastPathComponent
        return name.isEmpty ? fileURL.path : name
    }

    static func escapedMarkdownLinkLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    static func escapedMarkdownLinkDestination(_ destination: String) -> String {
        destination
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    static func normalizedSlashCommandLabel(_ label: String) -> String {
        label.hasPrefix("/") ? label : "/\(label)"
    }

    static func slashCommandInsertionText(
        label: String,
        uri: String,
        insertionStyle: BlockInputSlashCommandInsertionStyle
    ) -> String {
        switch insertionStyle {
        case .markdownLink:
            return "[\(escapedMarkdownLinkLabel(label))](\(escapedMarkdownLinkDestination(uri))) "
        case .rawToken:
            return "\(label) "
        }
    }
}
