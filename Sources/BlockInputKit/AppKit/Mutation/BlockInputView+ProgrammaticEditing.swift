import AppKit

/// Per-block backing store for transient highlights, re-applied on reconfigure so they survive reloads.
typealias BlockInputTransientHighlightMap = [BlockInputBlockID: [BlockInputTransientHighlight]]

/// A transient, non-mutating visual highlight over a range of a block's text — a background fill and an
/// optional strikethrough — painted with `NSLayoutManager` temporary attributes (the same mechanism as
/// find-match highlighting). Intended for diff/edit overlays: e.g. a deleted run as a red background +
/// strikethrough, an inserted run as a green background, with the document text left unchanged.
public struct BlockInputTransientHighlight: Equatable, Sendable {
    /// UTF-16 range within the block's text.
    public var range: NSRange
    /// Background fill painted behind the range.
    public var backgroundColor: NSColor
    /// Whether to draw a single strikethrough line across the range.
    public var strikethrough: Bool
    /// Strikethrough line color; defaults to the text color when `nil`.
    public var strikethroughColor: NSColor?

    public init(
        range: NSRange,
        backgroundColor: NSColor,
        strikethrough: Bool = false,
        strikethroughColor: NSColor? = nil
    ) {
        self.range = range
        self.backgroundColor = backgroundColor
        self.strikethrough = strikethrough
        self.strikethroughColor = strikethroughColor
    }
}

public extension BlockInputView {
    /// Paints transient highlights over a block WITHOUT mutating its text, for diff/edit overlays.
    ///
    /// Uses `NSLayoutManager` temporary attributes (like find-match highlighting), so the document model
    /// is untouched and syntax/selection styling is preserved. The highlights are stored and re-applied
    /// automatically whenever the block re-renders (e.g. after edits/reloads), then removed by
    /// ``clearTransientHighlights(in:)``.
    func setTransientHighlights(_ highlights: [BlockInputTransientHighlight], in blockID: BlockInputBlockID) {
        transientHighlightsByBlock[blockID] = highlights
        mountedBlockItem(for: blockID)?.applyTransientHighlights(highlights)
    }

    /// The transient highlights currently set on a block (empty if none), for additive updates or inspection.
    func transientHighlights(in blockID: BlockInputBlockID) -> [BlockInputTransientHighlight] {
        transientHighlightsByBlock[blockID] ?? []
    }

    /// Removes any transient highlights from a block.
    func clearTransientHighlights(in blockID: BlockInputBlockID) {
        transientHighlightsByBlock[blockID] = nil
        mountedBlockItem(for: blockID)?.clearTransientHighlights()
    }

    /// The rect (in this view's coordinate space) of a UTF-16 range within a block, for anchoring a
    /// host-owned floating accessory (e.g. an inline accept/reject control) at a diff/edit region.
    /// Returns `nil` if the block is not currently visible or the range has no glyphs. Re-query after
    /// scroll/layout changes to keep an anchored view positioned (mirrors find-match anchoring).
    func rectForRange(_ range: NSRange, in blockID: BlockInputBlockID) -> NSRect? {
        guard let item = mountedBlockItem(for: blockID) else { return nil }
        return item.findMatchRect(forUTF16Range: range, in: self)
    }
}

public extension BlockInputView {
    /// Replaces a UTF-16 range of a block's text with `replacement`, re-rendering just that block.
    ///
    /// This is the programmatic analogue of typing: it applies a precise range edit and routes it through
    /// the same granular replace-and-reconfigure path the editor uses for user input, so only the affected
    /// block re-renders (no full reload) and the document store stays in sync. Intended for hosts/plugins
    /// that drive scripted edits (e.g. an AI inline-edit "scenario player" animating a rewrite).
    ///
    /// - Parameters:
    ///   - blockID: Block to edit. No-op (returns `nil`) if it is not currently loaded.
    ///   - range: UTF-16 range within the block's text; clamped to the text bounds.
    ///   - replacement: Text to splice in (may be empty to delete).
    /// - Returns: The resulting selection (a cursor after the replacement), or `nil` if the edit could not
    ///   be applied (block missing, editor not editable, or a non-text block such as a horizontal rule).
    @discardableResult
    func replaceText(
        in blockID: BlockInputBlockID,
        range: NSRange,
        with replacement: String
    ) -> BlockInputSelection? {
        guard isEditable,
              let index = index(of: blockID),
              var block = block(at: index),
              block.kind != .horizontalRule else {
            return nil
        }
        let nsText = block.text as NSString
        let editRange = NSRange(
            location: min(max(range.location, 0), nsText.length),
            length: min(range.length, nsText.length - min(max(range.location, 0), nsText.length))
        )
        let mutable = NSMutableString(string: block.text)
        mutable.replaceCharacters(in: editRange, with: replacement)
        block.text = mutable as String
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: editRange.location + (replacement as NSString).length
        ))
        guard applyGranularBlockReplacement(block, at: index, selection: afterSelection) else {
            return nil
        }
        return afterSelection
    }

    /// Replaces a block's entire text, re-rendering just that block. Convenience over
    /// ``replaceText(in:range:with:)`` for whole-block scripted rewrites.
    ///
    /// - Returns: The resulting selection, or `nil` if the block is missing or the editor is not editable.
    @discardableResult
    func replaceBlockText(
        blockID: BlockInputBlockID,
        with text: String
    ) -> BlockInputSelection? {
        guard let block = block(withID: blockID) else { return nil }
        let fullRange = NSRange(location: 0, length: (block.text as NSString).length)
        return replaceText(in: blockID, range: fullRange, with: text)
    }

    /// Inserts `block` immediately after `afterBlockID`, re-rendering and registering undo. Programmatic
    /// analogue of pressing Return then typing — intended for scripted structural edits (e.g. an AI
    /// inline-edit inserting a new list item during a diff animation).
    ///
    /// - Returns: A cursor selection in the inserted block, or `nil` if `afterBlockID` is missing.
    @discardableResult
    func insertBlock(_ block: BlockInputBlock, after afterBlockID: BlockInputBlockID) -> BlockInputSelection? {
        performStructuralEdit(named: "Insert Block") { document in
            guard let index = document.index(of: afterBlockID) else { return nil }
            return document.insertBlock(block, at: index + 1)
        }
    }

    /// Deletes a block, re-rendering and registering undo. Programmatic analogue of deleting a block.
    ///
    /// - Returns: The resulting selection, or `nil` if the block is missing.
    @discardableResult
    func deleteBlock(blockID: BlockInputBlockID) -> BlockInputSelection? {
        performStructuralEdit(named: "Delete Block") { document in
            document.deleteBlock(blockID: blockID)
        }
    }
}
