import AppKit

/// Minimal bottom-leading "command line" surface for vim search. It is display-only: it shows
/// `/needle` while typing and `needle  3/12` after commit. It hosts a single monospaced label, is
/// layer-backed, and returns `nil` from `hitTest` so it never intercepts editor clicks.
///
/// Unlike the find bar this captures no input — vim keys are consumed by the state machine, which
/// drives this label through `BlockInputView`'s vim-search API.
final class BlockInputVimSearchLineView: NSView {
    /// Current label text (`/needle` or `needle  3/12`).
    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    private let label: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.textColor = .secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        applyBackgroundColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackgroundColor()
    }

    /// Subtle secondary background that reads as a chip without competing with the content.
    private func applyBackgroundColor() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
    }
}

extension BlockInputVimSearchLineView {
    /// Current label text. Test-only accessor.
    var textForTesting: String {
        text
    }
}
