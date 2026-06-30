// Sources/BlockInputKit/AppKit/BlockInputContentSurfaceChrome.swift
import AppKit

/// A small reusable floating overlay that holds a ✕ close button and a "Full screen" text toggle, pinned to
/// the top-right of whatever content view it is added over. Both diagram surfaces (the zoom-modal viewer and
/// the editor scaffold) consume it so their chrome stays consistent. The fullscreen control is a TEXT button
/// (not an icon) so it never collides with the inline ⤢ expand glyph. Carries no diagram logic — the host
/// wires `onClose` / `onToggleFullscreen`.
@MainActor
final class BlockInputContentSurfaceChrome: NSView {
    private static let enterFullscreenTitle = "Full screen"
    private static let edgeInset: CGFloat = 10
    private static let buttonSpacing: CGFloat = 8
    private static let buttonSize: CGFloat = 26
    private static let symbolPointSize: CGFloat = 12
    private static let textPointSize: CGFloat = 12
    /// Horizontal breathing room on each side of the "Full screen" text so it isn't cramped against the edges.
    private static let textHPadding: CGFloat = 12
    private static let backgroundAlpha: CGFloat = 0.55
    /// A small radius for a squarer (not pill/circular) look on the floating chrome buttons.
    private static let backgroundCornerRadius: CGFloat = 6

    private let fullscreenButton = NSButton()
    private let closeButton = ClampedHeightButton()
    /// Width of the text button = title width + horizontal padding on each side; updated when the title flips.
    private var fullscreenWidthConstraint: NSLayoutConstraint?
    /// Close button leading pins: one used when fullscreen button is visible, one when it is hidden.
    private var closeLeadingAfterFullscreen: NSLayoutConstraint?
    private var closeLeadingAtEdge: NSLayoutConstraint?

    var onClose: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Adds this chrome over `content`, pinned to its top-right with a named inset.
    func addToTopRight(of content: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(self, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.edgeInset),
            topAnchor.constraint(equalTo: content.topAnchor, constant: Self.edgeInset)
        ])
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        closeButton.maxHeight = Self.buttonSize
        configureTextButton(fullscreenButton,
                            title: Self.enterFullscreenTitle,
                            action: #selector(fullscreenTapped))
        configureButton(closeButton, symbol: "xmark", label: "Close", action: #selector(closeTapped))
        addSubview(fullscreenButton)
        addSubview(closeButton)
        // Lay the two buttons out directly (NSStackView sizes a bezeled image button by its taller intrinsic
        // height, ignoring the height constraint). The text button drives the chrome height (top+bottom pins);
        // the ✕ is the same height and CENTERED on it so a sub-pixel clamp can't nudge it up/down.
        let leadingAfterFullscreen = closeButton.leadingAnchor.constraint(
            equalTo: fullscreenButton.trailingAnchor, constant: Self.buttonSpacing)
        let leadingAtEdge = closeButton.leadingAnchor.constraint(equalTo: leadingAnchor)
        closeLeadingAfterFullscreen = leadingAfterFullscreen
        closeLeadingAtEdge = leadingAtEdge
        NSLayoutConstraint.activate([
            fullscreenButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            fullscreenButton.topAnchor.constraint(equalTo: topAnchor),
            fullscreenButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            leadingAfterFullscreen,
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: fullscreenButton.centerYAnchor),
            closeButton.heightAnchor.constraint(equalTo: fullscreenButton.heightAnchor)
        ])
    }

    private func configureButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = Self.backgroundCornerRadius
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.backgroundAlpha).cgColor
        button.contentTintColor = .white
        let config = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(config)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        // The ✕ is square; its HEIGHT comes from the chrome top/bottom pins (matching the text button), so
        // only the width is fixed here. Low vertical resistance lets the pin shrink it below its bezel min.
        button.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        button.widthAnchor.constraint(equalToConstant: Self.buttonSize).isActive = true
    }

    /// Configures a pill-shaped TEXT button (white text on the same translucent background as the icon
    /// buttons). The chrome auto-sizes around the title; while fullscreen this button hides (only the ✕ remains).
    private func configureTextButton(_ button: NSButton, title: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        // Same bezel as the icon buttons so both render at an identical height in the chrome.
        button.bezelStyle = .regularSquare
        button.wantsLayer = true
        button.layer?.cornerRadius = Self.backgroundCornerRadius
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.backgroundAlpha).cgColor
        button.contentTintColor = .white
        button.imagePosition = .noImage
        button.font = .systemFont(ofSize: Self.textPointSize, weight: .semibold)
        button.attributedTitle = titledAttributedString(title)
        button.target = self
        button.action = action
        button.toolTip = title
        button.setAccessibilityLabel(title)
        let width = button.widthAnchor.constraint(equalToConstant: paddedWidth(for: title))
        fullscreenWidthConstraint = width
        button.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        NSLayoutConstraint.activate([button.heightAnchor.constraint(equalToConstant: Self.buttonSize), width])
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    /// The button's title width plus `textHPadding` on each side, so the text has breathing room.
    private func paddedWidth(for title: String) -> CGFloat {
        let titleWidth = titledAttributedString(title).size().width
        return ceil(titleWidth) + Self.textHPadding * 2
    }

    private func titledAttributedString(_ title: String) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: Self.textPointSize, weight: .semibold)
        ])
    }

    /// Reflects the live fullscreen state: while fullscreen, only ✕ is shown (Esc exits fullscreen, ✕ closes
    /// the surface), so the now-redundant Full screen / Exit toggle is hidden.
    func setFullscreen(_ active: Bool) {
        fullscreenButton.isHidden = active
    }

    /// Permanently hides or shows the fullscreen button for surfaces that never need it (e.g. a config panel).
    /// Swaps the close-button leading constraint so hiding the fullscreen button leaves no gap.
    func setFullscreenHidden(_ hidden: Bool) {
        fullscreenButton.isHidden = hidden
        closeLeadingAfterFullscreen?.isActive = !hidden
        closeLeadingAtEdge?.isActive = hidden
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func fullscreenTapped() {
        onToggleFullscreen?()
    }

    // MARK: - Test accessors

    func triggerCloseForTesting() {
        closeTapped()
    }

    func triggerFullscreenForTesting() {
        fullscreenTapped()
    }

    var fullscreenButtonTitleForTesting: String { fullscreenButton.title }
    var isFullscreenButtonHiddenForTesting: Bool { fullscreenButton.isHidden }
    var closeButtonHeightForTesting: CGFloat { closeButton.frame.height }
    var fullscreenButtonHeightForTesting: CGFloat { fullscreenButton.frame.height }
    var closeButtonMidYForTesting: CGFloat { closeButton.frame.midY }
    var fullscreenButtonMidYForTesting: CGFloat { fullscreenButton.frame.midY }
}

/// A button that clamps its own frame height and re-centers within the layout slot. A bezeled image button
/// (the ✕) otherwise draws ~3.5pt taller than its Auto Layout slot; clamping alone would shave the extra
/// height off the bottom and drop the glyph, so the override also nudges the origin to keep it centered.
private final class ClampedHeightButton: NSButton {
    var maxHeight: CGFloat = 0
    override var frame: NSRect {
        get { super.frame }
        set {
            var rect = newValue
            if maxHeight > 0, rect.height > maxHeight {
                rect.origin.y += (rect.height - maxHeight) / 2
                rect.size.height = maxHeight
            }
            super.frame = rect
        }
    }
}
