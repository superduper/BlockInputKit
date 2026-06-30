import AppKit

/// Identifies the inline link the hover Edit popover is currently anchored to.
struct BlockInputLinkHoverTarget: Equatable {
    /// Block that owns the hovered link.
    let blockID: BlockInputBlockID
    /// Source-space Markdown range for the hovered link, used to rebuild the edit context.
    let sourceLinkRange: BlockInputInlineMarkdownRange
    /// Visual rects for the hovered link in window coordinates, used for anchoring.
    let windowRects: [NSRect]
}

extension BlockInputView {
    /// Grace period that keeps the popover visible after the pointer leaves the link so it can be moved onto the button.
    private static let linkHoverDismissGrace: TimeInterval = 0.18

    /// True while any diagram surface (editor scaffold or zoom modal) is presented. Derived from the live
    /// surfaces so it is always accurate (self-healing) — it suppresses underlying document link-hover
    /// affordances so they don't bleed through the surface on top of them.
    var isBlockContentSurfacePresented: Bool {
        interactiveBlockContentScaffold != nil || renderedContentZoomModalView != nil
    }

    /// Shows or repositions the hover Edit popover for a hovered inline link.
    ///
    /// Gated by `linkHoverEditAffordance` and `isEditable`: when either is off the editor keeps no hover affordance and
    /// link editing stays on the modal fallback reached by plain click. Idempotent for the same link so repeated
    /// `mouseMoved` events do not rebuild the popover.
    func showLinkHoverEditAffordance(
        blockID: BlockInputBlockID,
        sourceLinkRange: BlockInputInlineMarkdownRange,
        windowRects: [NSRect]
    ) {
        guard linkHoverEditAffordance, isEditable, !windowRects.isEmpty, !isBlockContentSurfacePresented else {
            hideLinkHoverEditAffordance()
            return
        }
        cancelLinkHoverDismissal()
        let target = BlockInputLinkHoverTarget(blockID: blockID, sourceLinkRange: sourceLinkRange, windowRects: windowRects)
        if linkHoverTarget == target, linkHoverPopover != nil {
            return
        }
        linkHoverTarget = target
        let popover = linkHoverPopover ?? makeLinkHoverPopover()
        linkHoverPopover = popover
        popover.setButtons(linkHoverButtons(for: target))
        if popover.superview !== self {
            popover.removeFromSuperview()
            addSubview(popover, positioned: .above, relativeTo: nil)
        }
        popover.appearance = effectiveAppearance
        positionLinkHoverPopover(popover, windowRects: windowRects)
    }

    /// Hides the hover Edit popover immediately and clears its tracked target.
    func hideLinkHoverEditAffordance() {
        cancelLinkHoverDismissal()
        linkHoverPopover?.removeFromSuperview()
        linkHoverPopover = nil
        linkHoverTarget = nil
    }

    /// Schedules a graced dismissal so the pointer can travel from the link onto the popover button.
    func scheduleLinkHoverDismissal() {
        guard linkHoverPopover != nil else {
            return
        }
        cancelLinkHoverDismissal()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.linkHoverDismissWorkItem = nil
            guard !self.popoverContainsMouse() else {
                return
            }
            self.hideLinkHoverEditAffordance()
        }
        linkHoverDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.linkHoverDismissGrace, execute: workItem)
    }

    private func cancelLinkHoverDismissal() {
        linkHoverDismissWorkItem?.cancel()
        linkHoverDismissWorkItem = nil
    }

    private func popoverContainsMouse() -> Bool {
        guard let popover = linkHoverPopover,
              let window else {
            return false
        }
        let localPoint = popover.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return popover.bounds.insetBy(dx: -4, dy: -4).contains(localPoint)
    }

    private func makeLinkHoverPopover() -> BlockInputLinkHoverPopover {
        let popover = BlockInputLinkHoverPopover()
        popover.onMouseExited = { [weak self] in
            self?.scheduleLinkHoverDismissal()
        }
        return popover
    }

    /// Builds the hover popover buttons: built-in Open + Edit, with any host-supplied extra actions inserted before Edit.
    ///
    /// Extra actions (e.g. "Show in Finder" for file chips) come from `linkHoverActionsProvider`, keeping file-specific
    /// policy in the host while core only renders and routes the buttons.
    private func linkHoverButtons(for target: BlockInputLinkHoverTarget) -> [BlockInputLinkHoverButton] {
        var buttons: [BlockInputLinkHoverButton] = [
            BlockInputLinkHoverButton(title: "Open", accessibilityLabel: "Open Link") { [weak self] in
                self?.beginLinkHoverOpen()
            }
        ]
        if let provider = linkHoverActionsProvider,
           let destination = target.sourceLinkRange.linkDestination {
            let context = BlockInputLinkHoverActionContext(
                destination: destination,
                blockID: target.blockID,
                kind: inlineLinkKind(for: target.sourceLinkRange, in: block(withID: target.blockID)?.text ?? "")
            )
            buttons += provider(context).map { hostAction in
                BlockInputLinkHoverButton(title: hostAction.title, accessibilityLabel: hostAction.title) { [weak self] in
                    self?.hideLinkHoverEditAffordance()
                    hostAction.perform()
                }
            }
        }
        buttons.append(
            BlockInputLinkHoverButton(title: "Edit", accessibilityLabel: "Edit Link") { [weak self] in
                self?.beginLinkHoverEdit()
            }
        )
        return buttons
    }

    private func positionLinkHoverPopover(_ popover: BlockInputLinkHoverPopover, windowRects: [NSRect]) {
        let editorRects = windowRects.map { convert($0, from: nil) }
        let union = editorRects.dropFirst().reduce(editorRects[0]) { $0.union($1) }
        let size = popover.preferredSize
        var originX = union.midX - size.width / 2
        originX = min(max(originX, bounds.minX + 2), bounds.maxX - size.width - 2)
        // Anchor below the link by default; flip above only when there is no room below.
        let isFlipped = isFlippedCoordinateSpace
        let belowY = isFlipped
            ? union.maxY + BlockInputLinkHoverPopover.anchorGap
            : union.minY - BlockInputLinkHoverPopover.anchorGap - size.height
        let aboveY = isFlipped
            ? union.minY - BlockInputLinkHoverPopover.anchorGap - size.height
            : union.maxY + BlockInputLinkHoverPopover.anchorGap
        let fitsBelow = isFlipped ? (belowY + size.height <= bounds.maxY - 2) : (belowY >= bounds.minY + 2)
        let originY = fitsBelow ? belowY : aboveY
        popover.frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    private var isFlippedCoordinateSpace: Bool {
        isFlipped
    }

    /// Opens the hovered link. "Open" is an explicit intent, so it opens the destination directly through the URL opener
    /// rather than synthesizing a body click (a click can resolve to caret placement — e.g. a host returning
    /// `.placeCaret` for file chips — which would make this button a no-op). Custom markups still route through their
    /// click path so the provider's own activation runs.
    private func beginLinkHoverOpen() {
        guard let target = linkHoverTarget else {
            return
        }
        hideLinkHoverEditAffordance()
        if target.sourceLinkRange.style.customMarkupIdentity != nil,
           let event = synthesizedHoverOpenEvent(for: target.windowRects) {
            _ = handleLinkClick(
                blockID: target.blockID,
                selectedRange: target.sourceLinkRange.contentRange,
                clickedLinkRange: target.sourceLinkRange,
                event: event
            )
            return
        }
        guard let destination = target.sourceLinkRange.linkDestination else {
            return
        }
        _ = linkURLOpener(destination)
    }

    /// Builds a plain (no-modifier) left-click event over the hovered link so the open path runs as a normal click.
    private func synthesizedHoverOpenEvent(for windowRects: [NSRect]) -> NSEvent? {
        guard let window, let anchor = windowRects.first else {
            return nil
        }
        return NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: anchor.midX, y: anchor.midY),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    /// Opens the existing link modal for the hovered link; Edit is how the modal is reached under the hover model.
    /// Custom markups route to their registered modal mode that round-trips the provider's own source.
    private func beginLinkHoverEdit() {
        guard let target = linkHoverTarget else {
            return
        }
        hideLinkHoverEditAffordance()
        guard isEditable else {
            return
        }
        if let identity = target.sourceLinkRange.style.customMarkupIdentity {
            _ = showCustomMarkupModalIfAvailable(
                blockID: target.blockID,
                range: target.sourceLinkRange,
                identity: identity
            )
            return
        }
        guard let context = linkContext(
            blockID: target.blockID,
            selectedRange: target.sourceLinkRange.contentRange,
            clickedLinkRange: target.sourceLinkRange,
            event: nil,
            prefersClickedOffset: true
        ) else {
            return
        }
        showLinkModal(context: context)
    }
}
