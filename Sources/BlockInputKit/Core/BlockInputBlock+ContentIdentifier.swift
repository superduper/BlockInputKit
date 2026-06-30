import Foundation

public extension BlockInputBlock {
    /// Resolver key used to select a ``BlockInputBlockContentRendering`` for this block,
    /// or `nil` when the block has no renderable content.
    ///
    /// Code blocks map to `"code.<language>"` (e.g. `"code.mermaid"`). The scheme is
    /// extensible: future attachment blocks can resolve to identifiers like
    /// `"attachment.pdf"` without affecting existing renderers.
    var renderedContentIdentifier: String? {
        kind.renderedContentIdentifier
    }
}

public extension BlockInputBlockKind {
    /// Content identifier derived from the block kind. See ``BlockInputBlock/renderedContentIdentifier``.
    var renderedContentIdentifier: String? {
        switch self {
        case let .code(language):
            guard let language, !language.isEmpty else {
                return nil
            }
            return "code.\(language.lowercased())"
        case .paragraph, .heading, .horizontalRule, .frontMatter, .quote,
             .bulletedListItem, .numberedListItem, .checklistItem, .table, .image, .rawMarkdown:
            return nil
        }
    }
}
