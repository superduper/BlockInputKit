import AppKit

/// Editable text surface used inside one table cell.
///
/// It inherits the standard block text-view command, menu, paste, and link-click
/// routing, while table adapters map its local ranges back to table source text.
final class BlockInputTableCellTextView: BlockInputTextView {
    override func mouseDown(with event: NSEvent) {
        if shouldTrackTableCellSelectionDrag(for: event) {
            blockItem?.beginTableCellSelectionDrag(from: self)
        } else {
            _ = blockItem?.finishTableCellSelectionDrag()
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if blockItem?.updateTableCellSelectionDrag(from: self, with: event) == true {
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if blockItem?.finishTableCellSelectionDrag() == true {
            return
        }
        super.mouseUp(with: event)
    }

    func localInsertionRange(atWindowLocation windowLocation: NSPoint) -> NSRange {
        let localLocation = convert(windowLocation, from: nil)
        let offset = characterIndexForInsertion(at: localLocation)
        let textLength = (string as NSString).length
        return NSRange(location: min(max(offset, 0), textLength), length: 0)
    }

    func anchorWindowRect(forLocalRange range: NSRange) -> NSRect {
        guard range.length > 0,
              let layoutManager,
              let textContainer else {
            return anchorWindowRect(forLocalOffset: range.location)
        }
        layoutManager.ensureLayout(for: textContainer)
        let characterRange = string.blockInputTableCellClampedRange(range)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
            .blockInputTableCellClamped(toGlyphCount: layoutManager.numberOfGlyphs)
        guard glyphRange.length > 0 else {
            return anchorWindowRect(forLocalOffset: range.location)
        }
        let localRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return convert(localRect, to: nil)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hideFileDropCaret()
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hideFileDropCaret()
        return []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        false
    }

    private func anchorWindowRect(forLocalOffset offset: Int) -> NSRect {
        let clampedOffset = min(max(offset, 0), (string as NSString).length)
        guard let window else {
            return .zero
        }
        let rect = firstRect(forCharacterRange: NSRange(location: clampedOffset, length: 0), actualRange: nil)
        guard rect != .zero, !rect.isNull, !rect.isInfinite else {
            return convert(bounds, to: nil)
        }
        let origin = window.convertPoint(fromScreen: rect.origin)
        return NSRect(origin: origin, size: rect.size)
    }

    private func shouldTrackTableCellSelectionDrag(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.clickCount == 1
            && !modifiers.contains(.command)
            && !modifiers.contains(.option)
            && !modifiers.contains(.control)
            && !modifiers.contains(.shift)
    }
}

private extension String {
    func blockInputTableCellClampedRange(_ range: NSRange) -> NSRange {
        let text = self as NSString
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), max(text.length - location, 0))
        return NSRange(location: location, length: length)
    }
}

private extension NSRange {
    func blockInputTableCellClamped(toGlyphCount glyphCount: Int) -> NSRange {
        let location = min(max(location, 0), glyphCount)
        let length = min(max(length, 0), max(glyphCount - location, 0))
        return NSRange(location: location, length: length)
    }
}
