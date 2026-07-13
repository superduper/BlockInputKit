import AppKit

/// Conventional additions-green / deletions-red styling for an already-applied diff highlight.
///
/// Centralizes the diff colors so hosts don't reinvent `.systemGreen`/`.systemRed`. This is the same
/// styling the interactive ⌘K plugin uses for its diff overlay, but exposed for the *passive* case:
/// an edit already spliced into the document that we merely want to annotate.
public struct BlockInputAppliedDiffStyle: Equatable, Sendable {
    /// Background fill behind inserted (added) text.
    public var additionBackgroundColor: NSColor
    /// Background fill behind removed text (drawn over a still-present run to be struck through).
    public var deletionBackgroundColor: NSColor
    /// Strikethrough color drawn across a deletion run.
    public var deletionStrikethroughColor: NSColor

    /// The built-in additions-green / deletions-red styling.
    public static var `default`: BlockInputAppliedDiffStyle { BlockInputAppliedDiffStyle() }

    public init(
        additionBackgroundColor: NSColor = NSColor.systemGreen.withAlphaComponent(0.28),
        deletionBackgroundColor: NSColor = NSColor.systemRed.withAlphaComponent(0.22),
        deletionStrikethroughColor: NSColor = .systemRed
    ) {
        self.additionBackgroundColor = additionBackgroundColor
        self.deletionBackgroundColor = deletionBackgroundColor
        self.deletionStrikethroughColor = deletionStrikethroughColor
    }
}

public extension BlockInputView {
    /// Passively highlights an ALREADY-APPLIED edit inside one block — additions green, deletions red +
    /// strikethrough — with NO accept/reject controls and NO follow-up prompt.
    ///
    /// This is the non-interactive counterpart to the ⌘K interactive diff: the edit is already spliced
    /// into the document (e.g. an auto-applied AI rewrite); this call is purely a "here's what changed"
    /// annotation. It reuses the non-mutating transient-highlight machinery (``setTransientHighlights(_:in:)``),
    /// so the document text is untouched and the highlight re-applies across reconfigure/reload. The host
    /// decides when to remove it via ``clearAppliedDiffHighlight(in:)``.
    ///
    /// Ranges are UTF-16 offsets into the block's *current* text. A deletion range should point at a run
    /// still present in the text so the strikethrough has glyphs to cross; a fully-removed run has no range
    /// to highlight and belongs to the host's before/after presentation instead.
    ///
    /// - Parameters:
    ///   - additions: Ranges of inserted text to fill green.
    ///   - deletions: Ranges of removed text to fill red and strike through.
    ///   - blockID: Block the ranges belong to.
    ///   - style: Diff styling (defaults to additions-green / deletions-red).
    func presentAppliedDiff(
        additions: [NSRange],
        deletions: [NSRange] = [],
        in blockID: BlockInputBlockID,
        style: BlockInputAppliedDiffStyle = .default
    ) {
        var highlights: [BlockInputTransientHighlight] = []
        highlights.append(contentsOf: additions.map {
            BlockInputTransientHighlight(range: $0, backgroundColor: style.additionBackgroundColor)
        })
        highlights.append(contentsOf: deletions.map {
            BlockInputTransientHighlight(
                range: $0,
                backgroundColor: style.deletionBackgroundColor,
                strikethrough: true,
                strikethroughColor: style.deletionStrikethroughColor
            )
        })
        setTransientHighlights(highlights, in: blockID)
    }

    /// Removes an applied-diff highlight previously shown by ``presentAppliedDiff(additions:deletions:in:style:)``.
    ///
    /// A thin alias over ``clearTransientHighlights(in:)`` for symmetry with the applied-diff entry point.
    func clearAppliedDiffHighlight(in blockID: BlockInputBlockID) {
        clearTransientHighlights(in: blockID)
    }
}
