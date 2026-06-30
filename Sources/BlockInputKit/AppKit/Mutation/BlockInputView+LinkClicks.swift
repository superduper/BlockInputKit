import AppKit

extension BlockInputView {
    func handleLinkClick(
        blockID: BlockInputBlockID,
        selectedRange: NSRange,
        clickedLinkRange: BlockInputInlineMarkdownRange? = nil,
        event: NSEvent
    ) -> Bool {
        if let clickedLinkRange, let handled = handleStyledMarkupClick(
            blockID: blockID,
            clickedLinkRange: clickedLinkRange,
            event: event
        ) {
            return handled
        }
        guard let context = linkContext(
            blockID: blockID,
            selectedRange: selectedRange,
            clickedLinkRange: clickedLinkRange,
            event: event,
            prefersClickedOffset: true
        ),
              case let .edit(linkRange) = context.mode,
              let destination = linkRange.linkDestination else {
            return false
        }
        if routeInlineLinkClick(
            context: context,
            linkRange: linkRange,
            destination: destination,
            blockID: blockID,
            event: event
        ) {
            return true
        }
        // Interaction model (shipping default, `linkHoverEditAffordance` on): a click on the link BODY opens only on a
        // double-click or a command-click; a single click on the body returns false so the caret is placed. A single
        // click on the trailing OPEN ICON opens immediately. The legacy (`linkHoverEditAffordance` off) path keeps the
        // pre-wikilink behavior: plain click shows the modal, cmd-click opens.
        if linkHoverEditAffordance {
            guard linkClickShouldOpen(blockID: blockID, event: event) else {
                return false
            }
            let didOpen = linkURLOpener(destination)
            if didOpen {
                dismissLinkModal(restoreFocus: false)
            }
            return didOpen
        }
        if event.modifierFlags.contains(.command) {
            let didOpen = linkURLOpener(destination)
            if didOpen {
                dismissLinkModal(restoreFocus: false)
            }
            return didOpen
        }
        guard isEditable else {
            return false
        }
        showLinkModal(context: context)
        return true
    }

    /// Routes a click on a styled custom-markup span (which carries no Markdown `linkDestination`), returning the
    /// handled result, or `nil` when the clicked range is a regular link/chip the main path should handle.
    private func handleStyledMarkupClick(
        blockID: BlockInputBlockID,
        clickedLinkRange: BlockInputInlineMarkdownRange,
        event: NSEvent
    ) -> Bool? {
        if let identity = clickedLinkRange.style.customMarkupIdentity {
            return handleCustomMarkupClick(blockID: blockID, markupRange: clickedLinkRange, identity: identity, event: event)
        }
        return nil
    }

    /// Decides whether a link interaction should OPEN/navigate versus just place the caret.
    ///
    /// Opens for: a read-only view (a viewer has no caret, so a single click navigates), a command-click, a double-click
    /// on the link body, or a single click on the link's trailing open icon. A plain single click on the link body in an
    /// editable view returns false so the normal caret-placement path runs instead.
    func linkClickShouldOpen(
        blockID: BlockInputBlockID,
        event: NSEvent
    ) -> Bool {
        if !isEditable || event.modifierFlags.contains(.command) || event.clickCount >= 2 {
            return true
        }
        return linkClickHitOpenIcon(blockID: blockID, event: event)
    }

    /// Whether the event location lands inside one of the block's painted link open-icon rects.
    ///
    /// Resolves the block's text view and reuses the shared icon hit-test (`isPointInsideAnyLinkOpenIcon`, backed by the
    /// single `linkOpenIconRect(for:)` source of truth) so an icon click is distinguished from a link-body click without
    /// re-deriving geometry or mapping source-vs-local ranges. The event's candidate window locations cover pointer drift.
    private func linkClickHitOpenIcon(
        blockID: BlockInputBlockID,
        event: NSEvent
    ) -> Bool {
        guard let textView = visibleItem(for: blockID, refreshConfiguration: false)?.textView else {
            return false
        }
        return textView.linkEventWindowLocations(event).contains { textView.isPointInsideAnyLinkOpenIcon($0) }
    }

    private func routeInlineLinkClick(
        context: BlockInputLinkContext,
        linkRange: BlockInputInlineMarkdownRange,
        destination: URL,
        blockID: BlockInputBlockID,
        event: NSEvent
    ) -> Bool {
        let kind = inlineLinkKind(for: linkRange, in: context.sourceText)
        let label = linkText(in: context.sourceText, range: linkRange)
        guard let action = inlineLinkClickAction(
            kind: kind,
            destination: destination,
            alias: nil,
            label: label,
            blockID: blockID,
            sourceRange: linkRange.fullRange,
            event: event
        ) else {
            return false
        }
        switch action {
        case .showLinkModal:
            guard isEditable else {
                return false
            }
            showLinkModal(context: context)
            return true
        case .openURL:
            _ = linkURLOpener(destination)
            dismissLinkModal(restoreFocus: false)
            return true
        case .hostHandled:
            dismissLinkModal(restoreFocus: false)
            return true
        case .placeCaret:
            // Decline the click so `handleLinkClick` falls through to the editor's normal caret placement, letting the
            // label be edited inline like ordinary link text.
            return false
        }
    }

    func inlineLinkKind(
        for linkRange: BlockInputInlineMarkdownRange,
        in text: String
    ) -> BlockInputInlineLinkKind {
        switch linkRange.inlineChipKind(in: text) {
        case .fileLink:
            return .fileChip
        case .slashCommand, .rawSlashCommand:
            return .slashCommand
        case nil:
            return .plainLink
        }
    }

    /// Resolves the click action, preferring the general handler and forwarding `.slashCommand` to the deprecated one.
    private func inlineLinkClickAction(
        kind: BlockInputInlineLinkKind,
        destination: URL,
        alias: String?,
        label: String,
        blockID: BlockInputBlockID,
        sourceRange: NSRange,
        event: NSEvent
    ) -> BlockInputInlineLinkClickAction? {
        if let inlineLinkClickHandler {
            return inlineLinkClickHandler(BlockInputInlineLinkClickContext(
                kind: kind,
                destination: destination,
                alias: alias,
                label: label,
                blockID: blockID,
                sourceRange: sourceRange,
                editorView: self,
                event: event,
                clickKind: slashCommandChipClickKind(for: event)
            ))
        }
        guard kind == .slashCommand else {
            return nil
        }
        return slashCommandChipClickHandler?(BlockInputSlashCommandChipClickContext(
            label: label,
            uri: destination,
            blockID: blockID,
            sourceRange: sourceRange,
            editorView: self,
            event: event,
            clickKind: slashCommandChipClickKind(for: event)
        ))
    }

    private func slashCommandChipClickKind(for event: NSEvent) -> BlockInputSlashCommandChipClickKind {
        event.modifierFlags.contains(.command) ? .commandClick : .plainClick
    }
}
