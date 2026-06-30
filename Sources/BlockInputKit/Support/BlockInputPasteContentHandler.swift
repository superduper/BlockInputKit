import AppKit

/// Host hook for resolving rich pasteboard content before the editor inserts Markdown.
///
/// Each handler claims one or more pasteboard types. On Cmd+V (and right-click Paste), the editor reads
/// the pasteboard types present and consults registered handlers in `BlockInputConfiguration.pasteContentHandlers`
/// order; the first handler whose claimed type is present and that returns a non-nil reference list wins, and the
/// editor inserts those references (image blocks / file-link chips) in a single undo group. When every handler
/// declines, paste falls through to native AppKit text insertion, preserving the editor's default behavior.
///
/// Core is policy-free: it never names a UTI, classifies content, converts rich text, or writes files. All such
/// policy lives in handlers (see the `BlockInputKitPaste` plugin), which reuse `BlockInputFileDropReference` so paste
/// and file-drop share the editor's insertion engine.
public protocol BlockInputPasteContentHandler: Sendable {
    /// Pasteboard types this handler claims, in the order the editor should try them.
    var handledTypes: [NSPasteboard.PasteboardType] { get }

    /// Produces logical references for the first handled type present on the pasteboard.
    ///
    /// Return `nil` to decline; the editor then tries the next handler, and finally native paste. The pasteboard is
    /// read on the calling actor before this async work begins, so implementations should capture any needed data
    /// from `pasteboard` synchronously where practical.
    func references(
        from pasteboard: NSPasteboard,
        type: NSPasteboard.PasteboardType,
        placement: BlockInputFileDropPlacement,
        document: BlockInputDocument
    ) async -> [BlockInputFileDropReference]?
}
