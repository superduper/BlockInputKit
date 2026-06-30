import AppKit

extension BlockInputView {
    func nativeTextSelectionExpansionDirection(
        blockID: BlockInputBlockID,
        selectedRange: NSRange,
        blockText: String
    ) -> BlockInputVerticalMovementDirection? {
        guard selectedRange.length > 0 else {
            return nil
        }
        if case let .text(textRange) = selection,
           textRange.blockID == blockID {
            if textRange.range == selectedRange,
               lastNativeTextSelectionExpansion?.matches(blockID: blockID, range: selectedRange) == true {
                return lastNativeTextSelectionExpansion?.direction
            }
            return selectedRange.expansionDirection(from: textRange.range)
        }
        if case let .cursor(cursor) = selection,
           cursor.blockID == blockID {
            return selectedRange.expansionDirection(fromUTF16Offset: cursor.utf16Offset, in: blockText)
        }
        return nil
    }

    func shouldPromoteRepeatedNativeTextSelection(
        blockID: BlockInputBlockID,
        selectedRange: NSRange,
        direction: BlockInputVerticalMovementDirection,
        blockText: String
    ) -> Bool {
        guard selectedRange.isSelectionExpansionBoundary(in: blockText, direction: direction),
              case let .text(textRange) = selection,
              textRange.blockID == blockID,
              textRange.range == selectedRange,
              lastNativeTextSelectionExpansion?.matches(blockID: blockID, range: selectedRange) == true,
              lastNativeTextSelectionExpansion?.direction == direction else {
            return false
        }
        return true
    }
}

/// Tracks an AppKit-owned text selection that reached a block boundary.
///
/// Native `NSTextView` command handling can report the same edge-touching range
/// again without preserving the original Shift+Arrow event, so the view records the
/// inferred direction and promotes the repeated edge selection to block selection.
struct BlockInputNativeTextSelectionExpansion {
    var blockID: BlockInputBlockID
    var range: NSRange
    var direction: BlockInputVerticalMovementDirection

    func matches(blockID: BlockInputBlockID, range: NSRange) -> Bool {
        self.blockID == blockID && self.range == range
    }
}

/// Tracks the keyboard anchor for a block selection created from Shift+Arrow.
///
/// The anchor lets opposite-direction Shift+Arrow contract the selected block range
/// before expanding in the other direction. It is also intentionally preserved
/// after contraction restores full text selection because AppKit may route the
/// next key through `NSTextView` as a Shift+Arrow-style event.
struct BlockInputBlockSelectionExpansion {
    var anchorBlockID: BlockInputBlockID
    var direction: BlockInputVerticalMovementDirection
}

/// Tracks the fixed edge while Shift+Left/Right adjusts editor-owned selections.
///
/// `NSRange` has no anchor/focus direction once selection crosses into block chrome. Keeping the anchor and active edge
/// explicit preserves zero-width continuation points that canonical `.mixed` selections cannot represent directly.
struct BlockInputHorizontalSelectionExpansion {
    var anchor: BlockInputDocumentTextBoundary
    var active: BlockInputDocumentTextBoundary?
}

/// A boundary in the flattened Markdown text stream represented by block ID plus UTF-16 offset.
///
/// Adjacent blocks have no real shared `NSRange`, so editor-level selection code uses this value as the cross-block
/// equivalent of a caret position when rebuilding `.text`, `.blocks`, or `.mixed` selection models.
struct BlockInputDocumentTextBoundary: Equatable {
    var blockID: BlockInputBlockID
    var utf16Offset: Int
}

extension BlockInputVerticalMovementDirection {
    var debugName: String {
        switch self {
        case .upward:
            return "up"
        case .downward:
            return "down"
        }
    }
}

extension BlockInputHorizontalMovementDirection {
    var debugName: String {
        switch self {
        case .leftward:
            return "left"
        case .rightward:
            return "right"
        }
    }
}

extension BlockInputLineBoundarySelectionDirection {
    var debugName: String {
        switch self {
        case .beginning:
            return "beginning"
        case .end:
            return "end"
        }
    }
}

extension NSRange {
    func expansionDirection(from previousRange: NSRange) -> BlockInputVerticalMovementDirection? {
        if location < previousRange.location {
            return .upward
        }
        if NSMaxRange(self) > NSMaxRange(previousRange) {
            return .downward
        }
        return nil
    }

    func expansionDirection(fromUTF16Offset offset: Int, in text: String) -> BlockInputVerticalMovementDirection? {
        let textLength = (text as NSString).length
        if location == 0, offset >= NSMaxRange(self) {
            return .upward
        }
        if NSMaxRange(self) >= textLength, offset <= location {
            return .downward
        }
        if location < offset {
            return .upward
        }
        if NSMaxRange(self) > offset {
            return .downward
        }
        return nil
    }

    func isCompleteTextSelection(in text: String) -> Bool {
        location <= 0 && NSMaxRange(self) >= (text as NSString).length
    }

    func isSelectionExpansionBoundary(in text: String, direction: BlockInputVerticalMovementDirection) -> Bool {
        guard length > 0 else {
            return false
        }
        let textLength = (text as NSString).length
        switch direction {
        case .upward:
            return location <= 0
        case .downward:
            return NSMaxRange(self) >= textLength
        }
    }
}
