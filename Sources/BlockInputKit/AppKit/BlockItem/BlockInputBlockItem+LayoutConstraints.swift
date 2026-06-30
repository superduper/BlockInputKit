import AppKit

extension BlockInputBlockItem {
    /// Writes a constraint constant only when it differs by more than half a point.
    ///
    /// Layout-pass callees (e.g. `updateQuoteBarVerticalExtent`, `updateHorizontalConstraints`) run on every
    /// `viewDidLayout`. Writing a constant — even an unchanged one — marks the window as needing another
    /// layout pass. When a measurement jitters by sub-pixel amounts between passes (which larger fonts cause),
    /// unconditional writes never converge and AppKit aborts with "more Layout Window passes than views".
    /// Gating the write on a real change keeps the layout cycle stable.
    static func setConstantIfChanged(_ constraint: NSLayoutConstraint?, to value: CGFloat) {
        guard let constraint, abs(constraint.constant - value) > 0.5 else {
            return
        }
        constraint.constant = value
    }

    /// Collapses the quote bar to its default vertical inset (used when there is no measurable text rect).
    func resetQuoteBarInsets() {
        Self.setConstantIfChanged(quoteBarTopConstraint, to: Self.quoteBarVerticalInset)
        Self.setConstantIfChanged(quoteBarBottomConstraint, to: -Self.quoteBarVerticalInset)
    }

    func updateQuoteBarVerticalExtent() {
        guard renderedBlock?.kind == .quote,
              !quoteBarView.isHidden,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            resetQuoteBarInsets()
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let textRect = layoutManager.usedRect(for: textContainer).offsetBy(
            dx: textView.textContainerOrigin.x,
            dy: textView.textContainerOrigin.y
        )
        guard !textRect.isEmpty else {
            resetQuoteBarInsets()
            return
        }

        let itemTextRect = textView.convert(textRect, to: view)
        let quoteBarHeight = min(
            max(Self.minimumQuoteBarHeight, itemTextRect.height),
            max(0, view.bounds.height - Self.quoteBarVerticalInset * 2)
        )
        let textMidY = quoteBarAlignmentRect(
            itemTextRect: itemTextRect,
            layoutManager: layoutManager,
            textContainer: textContainer
        ).midY
        let quoteBarMinY = min(
            max(view.bounds.minY + Self.quoteBarVerticalInset, textMidY - quoteBarHeight / 2),
            view.bounds.maxY - Self.quoteBarVerticalInset - quoteBarHeight
        )
        let quoteBarMaxY = quoteBarMinY + quoteBarHeight
        let topInset = max(Self.quoteBarVerticalInset, view.bounds.maxY - quoteBarMaxY)
        let bottomInset = max(Self.quoteBarVerticalInset, quoteBarMinY - view.bounds.minY)
        // Write only on real changes; idempotent layout passes must not re-dirty the window (see
        // `setConstantIfChanged`), or larger-font height jitter spins the layout cycle until AppKit aborts.
        Self.setConstantIfChanged(quoteBarTopConstraint, to: topInset)
        Self.setConstantIfChanged(quoteBarBottomConstraint, to: -bottomInset)
        if abs(quoteBarView.frame.origin.y - quoteBarMinY) > 0.5 || abs(quoteBarView.frame.height - quoteBarHeight) > 0.5 {
            quoteBarView.frame.origin.y = quoteBarMinY
            quoteBarView.frame.size.height = quoteBarHeight
        }
    }

    private func quoteBarAlignmentRect(
        itemTextRect: NSRect,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0,
              layoutManager.lineFragmentCount(in: glyphRange) == 1 else {
            return itemTextRect
        }
        let firstLineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil).offsetBy(
            dx: textView.textContainerOrigin.x,
            dy: textView.textContainerOrigin.y
        )
        return textView.convert(firstLineRect, to: view)
    }
}

private extension NSLayoutManager {
    func lineFragmentCount(in glyphRange: NSRange) -> Int {
        var lineCount = 0
        enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, stop in
            lineCount += 1
            if lineCount > 1 {
                stop.pointee = true
            }
        }
        return lineCount
    }
}
