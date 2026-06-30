import AppKit

extension BlockInputView {
    func linkModalContainsCurrentResponder() -> Bool {
        guard let modal = linkModalView,
              let firstResponder = window?.firstResponder else {
            return false
        }
        return modal.containsResponder(firstResponder)
    }
}

extension BlockInputLinkContext {
    /// Returns true while the editor selection still overlaps the source region this context is allowed to edit.
    func contains(selection: BlockInputSelection?) -> Bool {
        let selectionRange: BlockInputTextRange?
        switch selection {
        case let .cursor(cursor) where cursor.blockID == blockID:
            selectionRange = BlockInputTextRange(
                blockID: cursor.blockID,
                range: NSRange(location: cursor.utf16Offset, length: 0)
            )
        case let .text(textRange) where textRange.blockID == blockID:
            selectionRange = textRange
        case .blocks, .mixed, .cursor, .text, nil:
            return false
        }
        guard let selectionRange else {
            return false
        }
        switch mode {
        case .create(let range):
            return range.containsOrTouches(selectionRange.range.location) ||
                selectionRange.range.containsOrTouches(range.location)
        case .edit(let linkRange):
            return linkRange.fullRange.containsOrTouches(selectionRange.range.location) ||
                linkRange.fullRange.intersectionLength(with: selectionRange.range) > 0
        }
    }
}

extension String {
    func blockInputLinkClampedRange(_ range: NSRange) -> NSRange {
        let text = self as NSString
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), max(text.length - location, 0))
        return NSRange(location: location, length: length)
    }
}

extension NSRange {
    func containsOrTouches(_ offset: Int) -> Bool {
        location <= offset && offset <= NSMaxRange(self)
    }

    func intersectionLength(with range: NSRange) -> Int {
        NSIntersectionRange(self, range).length
    }
}
