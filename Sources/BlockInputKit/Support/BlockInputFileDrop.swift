import Foundation

/// Host hook for resolving local file drops before the editor inserts Markdown.
public typealias BlockInputFileDropHandler = @Sendable (BlockInputFileDropContext) async throws -> BlockInputFileDropResult

/// Semantic insertion kind for a dropped local file.
public enum BlockInputDroppedFileKind: Equatable, Codable, Sendable {
    /// Insert as a Markdown file link.
    case fileLink
    /// Insert as an image block.
    case image
}

/// Logical placement where a local file drop will be inserted.
public enum BlockInputFileDropPlacement: Equatable, Sendable {
    /// Insert into a text-capable block at a UTF-16 offset.
    case inline(blockID: BlockInputBlockID, utf16Offset: Int)
    /// Insert at the current document end.
    case documentEnd
}

/// One local file URL from a drop, with the editor's default insertion decision.
public struct BlockInputDroppedFile: Equatable, Sendable {
    /// Original order in the pasteboard file URL list.
    public var index: Int
    /// Original local file URL from the pasteboard.
    public var url: URL
    /// Editor's default insertion kind.
    public var defaultKind: BlockInputDroppedFileKind
    /// Editor's default Markdown destination.
    public var defaultSource: String
    /// Editor's default link label or image alt text.
    public var defaultLabel: String
    /// Default reference equivalent to the built-in insertion behavior.
    public var defaultReference: BlockInputFileDropReference {
        BlockInputFileDropReference(kind: defaultKind, source: defaultSource, label: defaultLabel)
    }

    /// Creates a drop item description for host resolution.
    public init(
        index: Int,
        url: URL,
        defaultKind: BlockInputDroppedFileKind,
        defaultSource: String,
        defaultLabel: String
    ) {
        self.index = index
        self.url = url
        self.defaultKind = defaultKind
        self.defaultSource = defaultSource
        self.defaultLabel = defaultLabel
    }
}

/// Context passed to a host file-drop hook.
public struct BlockInputFileDropContext: Equatable, Sendable {
    /// Dropped local file URLs with default insertion metadata.
    public var files: [BlockInputDroppedFile]
    /// Logical insertion placement.
    public var placement: BlockInputFileDropPlacement
    /// Loaded document snapshot at the time the drop was accepted.
    public var document: BlockInputDocument

    /// Creates host drop-resolution context.
    public init(
        files: [BlockInputDroppedFile],
        placement: BlockInputFileDropPlacement,
        document: BlockInputDocument
    ) {
        self.files = files
        self.placement = placement
        self.document = document
    }
}

/// Host result for a local file drop.
public enum BlockInputFileDropResult: Equatable, Sendable {
    /// Use the editor's built-in insertion behavior.
    case useDefault
    /// Do not mutate the document.
    case cancel
    /// Insert the returned logical references.
    case insert([BlockInputFileDropReference])
}

/// Final logical Markdown reference to insert for one dropped file.
public struct BlockInputFileDropReference: Equatable, Sendable {
    /// Final insertion kind.
    public var kind: BlockInputDroppedFileKind
    /// Unescaped Markdown destination, such as `assets/photo.png`.
    public var source: String
    /// File link label or image alt text.
    public var label: String

    /// Creates a final drop insertion reference.
    public init(kind: BlockInputDroppedFileKind, source: String, label: String) {
        self.kind = kind
        self.source = source
        self.label = label
    }
}
