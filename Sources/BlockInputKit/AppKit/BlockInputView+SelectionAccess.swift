import AppKit

/// Cursor-anchored read/reveal facade over the editor's current selection.
///
/// A clean public entry point for hosts that drive edits at the caret: read the current selection's
/// plain text, then scroll/focus a specific block-id + range back into view after an edit lands.
/// Internals (`selection`, `visibleItem(for:)`, `focusText(inUTF16Range:)`) stay internal; this
/// extension only composes them.
public extension BlockInputView {
    /// The plain text currently selected, or `nil` when there is no ranged selection.
    ///
    /// - A `.cursor` (caret with no range) returns `nil` — there is no selected text.
    /// - A `.text` range returns that block's substring.
    /// - A whole-block `.blocks` or a `.mixed` selection returns the selected blocks' text joined by
    ///   newlines (partial edge ranges contribute only their selected slice), in document order.
    ///
    /// Slicing reads the loaded document, so store-backed blocks must be loaded to contribute text.
    func selectedText() -> String? {
        switch selection {
        case .none, .cursor:
            return nil
        case let .text(textRange):
            return substring(of: textRange.blockID, range: textRange.range)
        case let .blocks(blockIDs):
            let ordered = blockIDs.sorted { (index(of: $0) ?? Int.max) < (index(of: $1) ?? Int.max) }
            let pieces = ordered.compactMap { block(withID: $0)?.text }
            return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
        case let .mixed(mixed):
            return mixedSelectionText(mixed)
        }
    }

    /// Moves the caret/selection to a block-id + UTF-16 range and scrolls it into view.
    ///
    /// The reveal path a host calls after an edit to focus where the edit landed: it scrolls the block
    /// into the viewport (collection-view item scroll), applies the selection, and runs the text view's
    /// `scrollRangeToVisible` so the range is on screen. A zero-length range reveals a caret.
    ///
    /// - Parameters:
    ///   - range: Block-id + UTF-16 range to reveal. Clamped to the block's text bounds.
    ///   - focusEditor: When `true` (default), makes the range's text view first responder.
    /// - Returns: `false` if the block is not present in the loaded document.
    @discardableResult
    func reveal(_ range: BlockInputTextRange, focusEditor: Bool = true) -> Bool {
        guard let block = block(withID: range.blockID) else { return false }
        let clamped = clampRange(range.range, toLength: block.utf16Length)
        if clamped.length == 0 {
            let cursor = BlockInputCursor(blockID: range.blockID, utf16Offset: clamped.location)
            applySelection(.cursor(cursor), notify: true)
        } else {
            applySelection(.text(BlockInputTextRange(blockID: range.blockID, range: clamped)), notify: true)
        }
        guard let item = visibleItem(for: range.blockID) else { return true }
        if focusEditor {
            item.focusText(inUTF16Range: clamped)
        } else {
            item.setSelectedRange(clamped)
        }
        return true
    }

    /// Convenience over ``reveal(_:focusEditor:)`` that reveals a caret at a block-id + offset.
    @discardableResult
    func reveal(blockID: BlockInputBlockID, utf16Offset: Int, focusEditor: Bool = true) -> Bool {
        reveal(
            BlockInputTextRange(blockID: blockID, range: NSRange(location: utf16Offset, length: 0)),
            focusEditor: focusEditor
        )
    }

    private func substring(of blockID: BlockInputBlockID, range: NSRange) -> String? {
        guard let block = block(withID: blockID) else { return nil }
        let clamped = clampRange(range, toLength: block.utf16Length)
        guard clamped.length > 0 else { return "" }
        return (block.text as NSString).substring(with: clamped)
    }

    private func mixedSelectionText(_ mixed: BlockInputMixedSelection) -> String? {
        var byIndex: [(index: Int, text: String)] = []
        if let leading = mixed.leadingTextRange,
           let text = substring(of: leading.blockID, range: leading.range),
           let idx = index(of: leading.blockID) {
            byIndex.append((idx, text))
        }
        for blockID in mixed.blockIDs {
            if let block = block(withID: blockID), let idx = index(of: blockID) {
                byIndex.append((idx, block.text))
            }
        }
        if let trailing = mixed.trailingTextRange,
           let text = substring(of: trailing.blockID, range: trailing.range),
           let idx = index(of: trailing.blockID) {
            byIndex.append((idx, text))
        }
        guard !byIndex.isEmpty else { return nil }
        return byIndex.sorted { $0.index < $1.index }.map(\.text).joined(separator: "\n")
    }

    private func clampRange(_ range: NSRange, toLength length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let maxLength = length - location
        return NSRange(location: location, length: min(max(range.length, 0), maxLength))
    }
}
