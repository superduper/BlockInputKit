import AppKit

extension BlockInputView {
    func restoreVisibleTextSelection(_ textRange: BlockInputTextRange) {
        guard let item = visibleItem(for: textRange.blockID) else {
            return
        }
        item.focusText(inUTF16Range: textRange.range)
    }

    /// Whether the find bar (its query/replace field or that field's editor) currently holds first
    /// responder. While it does, layout/reload-driven selection restoration must not pull first
    /// responder back into a block text view — that would steal keyboard focus from the find query.
    var findBarHoldsFirstResponder: Bool {
        guard let bar = findBarView,
              let responder = window?.firstResponder as? NSView else {
            return false
        }
        return responder === bar || responder.isDescendant(of: bar)
    }

    /// When the find bar field holds first responder, restores selection chrome WITHOUT moving first
    /// responder into a block (a layout/reload-driven restore would otherwise steal the field's
    /// focus, so the typed query would leak into the document). Returns `true` when it handled the
    /// restore and the caller should stop; `false` to fall through to normal focus restoration.
    func restoreVisibleSelectionPreservingFindBarFocusIfNeeded() -> Bool {
        guard findBarHoldsFirstResponder else {
            return false
        }
        if case let .text(textRange) = selection,
           block(withID: textRange.blockID)?.kind != .table,
           let item = visibleItem(for: textRange.blockID) {
            item.setSelectedRange(textRange.range)
        }
        return true
    }
}
