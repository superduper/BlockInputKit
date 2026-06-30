import AppKit

public extension BlockInputView {
    /// Plain text of the active block as currently shown in the editor.
    ///
    /// Returns the live text-view string when the block is mounted, so the value
    /// is coherent with `cursorOffset` even during an uncommitted edit. Falls back
    /// to the store's committed text for blocks outside the loaded window. Returns
    /// `nil` when no active block exists.
    var activeBlockText: String? {
        guard let blockID = activeBlockID else { return nil }
        if let item = mountedBlockItem(for: blockID) {
            return item.currentText
        }
        return block(withID: blockID)?.text
    }

    /// UTF-16 offset of the caret within the active block's text.
    ///
    /// Returns the caret offset for a `.cursor` selection, or the selection anchor
    /// (lower bound) for a `.text` selection. Returns `nil` for whole-block or
    /// mixed selections. Always indexes into `activeBlockText`.
    var cursorOffset: Int? {
        switch selection {
        case .cursor(let cursor):
            return cursor.utf16Offset
        case .text(let range):
            return range.range.location
        case .blocks, .mixed, nil:
            return nil
        }
    }

    /// Moves the caret to `offset` (UTF-16) within the text of `blockID`.
    ///
    /// Returns `false` when `blockID` is not in the loaded document, `offset` is
    /// negative, or `offset` exceeds the block's cursor length (one past the last
    /// character). The selection and any mounted text view are both updated.
    @discardableResult
    func setCursorOffset(_ offset: Int, in blockID: BlockInputBlockID) -> Bool {
        guard let block = block(withID: blockID),
              offset >= 0,
              offset <= block.cursorUTF16Length else {
            return false
        }
        applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: offset)), notify: true)
        restoreVisibleSelection()
        return true
    }

    /// Selects `range` (UTF-16) within the text of `blockID`.
    ///
    /// Returns `false` when `blockID` is not found, the range is empty, or the
    /// range extends beyond the block's text. The selection and any mounted text
    /// view are both updated.
    @discardableResult
    func setTextSelection(_ range: Range<Int>, in blockID: BlockInputBlockID) -> Bool {
        guard let block = block(withID: blockID) else { return false }
        let nsRange = NSRange(location: range.lowerBound, length: range.count)
        guard nsRange.length > 0,
              nsRange.location >= 0,
              nsRange.upperBound <= block.utf16Length else {
            return false
        }
        applySelection(.text(BlockInputTextRange(blockID: blockID, range: nsRange)), notify: true)
        restoreVisibleSelection()
        return true
    }
}
