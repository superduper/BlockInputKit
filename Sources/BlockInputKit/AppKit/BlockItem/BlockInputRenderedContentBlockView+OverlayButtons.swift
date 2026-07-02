import AppKit

/// Configuration for the ✏️ edit / ⤢ expand overlay buttons hosted in `overlayButtonBox`. The visibility,
/// hover-gating, and box-sizing logic live in the main view type; this companion holds the per-button setup
/// and the tap handlers.
extension BlockInputRenderedContentBlockView {
    func configureExpandButton() {
        configureOverlayButton(
            expandButton,
            symbol: "arrow.up.left.and.arrow.down.right",
            label: "Zoom diagram",
            action: #selector(expandTapped)
        )
    }

    func configureEditButton() {
        configureOverlayButton(editButton, symbol: "pencil", label: "Edit diagram", action: #selector(editTapped))
        setActionButtonsVisible(false)
    }

    private func configureOverlayButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .regularSquare
        button.isBordered = false
        // Each button gets its own fill so it reads as a distinct control WITHIN the box's scrim (the box is
        // windowBackgroundColor; the buttons are a step darker/lighter via controlColor). Rounded to sit inside
        // the box's corners.
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.controlColor.cgColor
        button.layer?.cornerRadius = 4
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.isHidden = true
    }

    @objc private func editTapped() {
        onEdit?()
    }

    @objc private func expandTapped() {
        onExpand?()
    }
}
