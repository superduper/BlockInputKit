import AppKit

/// Mouse-gesture classification and routing for inline link clicks.
///
/// Split from `BlockInputTextView+Links.swift` to keep that file under the line limit. These helpers decide which
/// gestures reach the editor's `handleLinkClick` decision (command-click, double-click, completed tracked single click)
/// and forward the resolved selection plus clicked link range to the owning block item.
extension BlockInputTextView {
    /// Returns true for the exact command-click gesture that should open a link immediately.
    func shouldRequestCommandClickLink(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let disallowedModifiers = NSEvent.ModifierFlags([.option, .control, .shift])
        return modifiers.contains(.command) && modifiers.isDisjoint(with: disallowedModifiers)
    }

    /// Returns true for an unmodified double-click that lands on a link, which should open/navigate.
    ///
    /// Detected on `mouseDown` so the open is routed before AppKit's native double-click word selection takes over; this
    /// keeps the test path off the hanging `super.mouseDown` event-tracking loop.
    func shouldRequestDoubleClickLink(with event: NSEvent) -> Bool {
        let disallowedModifiers = NSEvent.ModifierFlags([.command, .option, .control, .shift])
        guard event.clickCount == 2,
              event.modifierFlags.isDisjoint(with: disallowedModifiers) else {
            return false
        }
        return linkHitResult(for: event) != nil
    }

    /// Routes a completed plain click to link editing after native drag and text selection handling have had first chance.
    func requestLinkClickIfNeeded(with event: NSEvent) -> Bool {
        let disallowedModifiers = NSEvent.ModifierFlags([.option, .control, .shift])
        let isCompletedTrackedLinkClick = event.type == .leftMouseUp && blockSelectionClickLinkRange != nil
        // A double-click opens a link too (single click on the body just places the caret); allow it through here so the
        // `clickCount == 2` decision reaches `handleLinkClick`.
        let isRoutableClick = event.clickCount == 1 || event.clickCount == 2 || isCompletedTrackedLinkClick
        guard isRoutableClick,
              !isDraggingBlockSelection,
              !isUsingNativeMouseSelection,
              event.modifierFlags.isDisjoint(with: disallowedModifiers) else {
            return false
        }
        return routeLinkClick(with: event)
    }

    private func routeLinkClick(with event: NSEvent) -> Bool {
        let location = convert(event.locationInWindow, from: nil)
        let offset = blockSelectionDragAnchorOffset ?? characterIndexForInsertion(at: location)
        let localRange = NSRange(location: offset, length: 0)
        let selectedRange = blockItem?.sourceSelectedRange(for: self, localRange: localRange) ?? localRange
        let localClickedLinkRange = blockSelectionClickLinkRange ?? linkHitResult(for: event)?.range
        let clickedLinkRange = localClickedLinkRange.flatMap {
            blockItem?.sourceInlineMarkdownRange(for: self, localRange: $0) ?? $0
        }
        return blockItem?.requestLinkClick(
            selectedRange: selectedRange,
            clickedLinkRange: clickedLinkRange,
            event: event
        ) == true
    }
}
