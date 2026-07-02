// Sources/BlockInputKit/AppKit/BlockInputContentSurfaceScaffold.swift
import AppKit

/// A reusable floating-card shell for a plugin-owned diagram surface: a dim full-bleed background, a centered
/// card hosting an arbitrary content view, and a floating top-right cluster (Done + shared ✕/⤢ chrome) that
/// hovers over the content rather than sitting in a header strip. Dismissal via Done / ✕ / double-Escape / a
/// click on the dim margin outside the card. Carries NO diagram or AI logic — a plugin places its interactive
/// view inside via `setContentView`. Future prompt-driven plugins (e.g. gen-AI image) can reuse this carcass.
@MainActor
final class BlockInputContentSurfaceScaffold: NSView {
    private static let cardInset: CGFloat = 48
    private static let cornerRadius: CGFloat = 12
    private static let contentInset: CGFloat = 12
    private static let chromeEdgeInset: CGFloat = 10
    private static let doneSpacing: CGFloat = 8
    private static let borderWidth: CGFloat = 1
    private static let doubleEscapeWindow: TimeInterval = 0.4

    private let dimView = NSView()
    private let card = NSView()
    private let doneButton = NSButton()
    private let chrome = BlockInputContentSurfaceChrome()
    private let contentContainer = NSView()
    private var escapeMonitor: Any?
    private var lastEscapeTime: TimeInterval = 0

    var onDismiss: (() -> Void)?
    var onFullscreen: (() -> Void)?

    /// When set, the card hugs this content size (centered) instead of filling the surface. Used by small
    /// config-panel surfaces (e.g. the TOC options panel) so they don't stretch to full screen.
    private var preferredContentSize: CGSize?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// Creates a scaffold with configurable fullscreen chrome. Pass `false` for surfaces (e.g. config panels)
    /// that never need fullscreen — the button is hidden and leaves no layout gap. Pass a `preferredContentSize`
    /// for a small surface that should hug its content (centered card) rather than fill the surface.
    convenience init(showsFullscreen: Bool, preferredContentSize: CGSize? = nil) {
        self.init(frame: .zero)
        self.preferredContentSize = preferredContentSize
        if !showsFullscreen {
            chrome.setFullscreenHidden(true)
        }
        applyCardSizing()
    }

    override var acceptsFirstResponder: Bool { true }

    func setContentView(_ view: NSView) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        // Keep the floating cluster above any freshly inserted content view.
        card.addSubview(doneButton, positioned: .above, relativeTo: nil)
        card.addSubview(chrome, positioned: .above, relativeTo: nil)
    }

    /// Forwards the live fullscreen state to the shared chrome so its button title flips between
    /// "Full screen" and "Exit full screen".
    func setFullscreenActive(_ active: Bool) {
        chrome.setFullscreen(active)
    }

    func startEscapeMonitor() {
        stopEscapeMonitor()
        lastEscapeTime = 0
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else {
                return event
            }
            let now = ProcessInfo.processInfo.systemUptime
            let isDouble = now - self.lastEscapeTime <= Self.doubleEscapeWindow
            self.lastEscapeTime = now
            if isDouble {
                self.lastEscapeTime = 0
                self.onDismiss?()
                return nil
            }
            return event
        }
    }

    func stopEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopEscapeMonitor()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if card.frame.contains(point) {
            super.mouseDown(with: event)
        } else {
            onDismiss?()
        }
    }

    @objc private func doneTapped() {
        onDismiss?()
    }

    private func setup() {
        wantsLayer = true
        configureDim()
        configureCard()
        configureContentContainer()
        configureFloatingChrome()
        activateConstraints()
        applyCardSizing()
    }

    private var cardSizingConstraints: [NSLayoutConstraint] = []

    /// Pins the card to fill the surface (default) or centers it at `preferredContentSize` (content-hugging).
    /// The hugging card is also capped to the available space (minus the inset) so it never overflows a small
    /// window.
    private func applyCardSizing() {
        NSLayoutConstraint.deactivate(cardSizingConstraints)
        if let size = preferredContentSize {
            let width = card.widthAnchor.constraint(equalToConstant: size.width)
            let height = card.heightAnchor.constraint(equalToConstant: size.height)
            width.priority = .defaultHigh
            height.priority = .defaultHigh
            cardSizingConstraints = [
                card.centerXAnchor.constraint(equalTo: centerXAnchor),
                card.centerYAnchor.constraint(equalTo: centerYAnchor),
                width, height,
                card.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * Self.cardInset),
                card.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, constant: -2 * Self.cardInset)
            ]
        } else {
            cardSizingConstraints = [
                card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.cardInset),
                card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.cardInset),
                card.topAnchor.constraint(equalTo: topAnchor, constant: Self.cardInset),
                card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.cardInset)
            ]
        }
        NSLayoutConstraint.activate(cardSizingConstraints)
    }

    private func configureDim() {
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        dimView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimView)
    }

    private func configureCard() {
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        card.layer?.cornerRadius = Self.cornerRadius
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.borderWidth = Self.borderWidth
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
    }

    private func configureContentContainer() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(contentContainer)
    }

    private func configureFloatingChrome() {
        doneButton.title = "Done"
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(doneTapped)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(doneButton, positioned: .above, relativeTo: nil)

        chrome.onClose = { [weak self] in self?.onDismiss?() }
        chrome.onToggleFullscreen = { [weak self] in self?.onFullscreen?() }
        chrome.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(chrome, positioned: .above, relativeTo: nil)
    }

    private func activateConstraints() {
        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Self.contentInset),
            contentContainer.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Self.contentInset),
            contentContainer.topAnchor.constraint(equalTo: card.topAnchor, constant: Self.contentInset),
            contentContainer.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Self.contentInset),
            chrome.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Self.chromeEdgeInset),
            chrome.topAnchor.constraint(equalTo: card.topAnchor, constant: Self.chromeEdgeInset),
            doneButton.trailingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: -Self.doneSpacing),
            doneButton.centerYAnchor.constraint(equalTo: chrome.centerYAnchor)
        ])
    }

    // MARK: - Test accessors

    func handleMarginClickForTesting(at point: NSPoint) {
        if !card.frame.contains(point) {
            onDismiss?()
        }
    }

    func triggerDoneForTesting() {
        doneTapped()
    }

    func triggerFullscreenForTesting() {
        chrome.triggerFullscreenForTesting()
    }

    var isFullscreenControlHiddenForTesting: Bool {
        chrome.isFullscreenButtonHiddenForTesting
    }
}
