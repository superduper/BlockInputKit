// Sources/BlockInputKit/AppKit/BlockInputContentFailureSurfaceView.swift
import AppKit

/// The minimal, non-interactive surface core renders when a plugin cannot produce an interactive diagram view
/// at all (no renderer/provider, or the plugin failed to initialize). A centered message; no controls.
@MainActor
final class BlockInputContentFailureSurfaceView: NSView {
    private static let inset: CGFloat = 16
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(message: String) {
        label.stringValue = message
    }

    private func setup() {
        wantsLayer = true
        label.font = .preferredFont(forTextStyle: .callout)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    // MARK: - Test accessors

    var messageForTesting: String { label.stringValue }
}
