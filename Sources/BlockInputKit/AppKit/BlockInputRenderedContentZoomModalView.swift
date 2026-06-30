import AppKit

/// Full-bleed overlay that zooms a rendered-content block. It shows the already-rendered image instantly,
/// then swaps in a host-supplied live interactive view (e.g. a Mermaid `WKWebView` with working links).
/// Dismisses via the close button, Escape, or a click on the dimmed background.
final class BlockInputRenderedContentZoomModalView: NSView {
    private static let cardInset: CGFloat = 40
    private static let cardCornerRadius: CGFloat = 12
    private static let cardBorderWidth: CGFloat = 1
    private static let imageInset: CGFloat = 16
    private static let chromeEdgeInset: CGFloat = 10

    private let dimButton = NSButton()
    private let card = NSView()
    private let imageView = NSImageView()
    private let chrome = BlockInputContentSurfaceChrome()
    private var liveView: NSView?
    private let cardGuide = NSLayoutGuide()
    private var escapeMonitor: Any?
    var onDismiss: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(image: NSImage) {
        imageView.image = image
        imageView.isHidden = false
    }

    /// Swaps in a live interactive view, filling the card and hiding the static image.
    func showLiveView(_ view: NSView) {
        removeLiveView()
        view.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(view, positioned: .below, relativeTo: chrome)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            view.topAnchor.constraint(equalTo: card.topAnchor),
            view.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        liveView = view
        imageView.isHidden = true
    }

    private func removeLiveView() {
        liveView?.removeFromSuperview()
        liveView = nil
    }

    /// Forwards the live fullscreen state to the shared chrome so its button title flips between
    /// "Full screen" and "Exit full screen".
    func setFullscreenActive(_ active: Bool) {
        chrome.setFullscreen(active)
    }

    override var acceptsFirstResponder: Bool { true }

    /// Escape dismisses even while a hosted web view holds key focus, via a local event monitor.
    func startEscapeMonitor() {
        stopEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else {
                return event
            }
            self.onDismiss?()
            return nil
        }
    }

    func stopEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }

    private func setup() {
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Zoomed diagram")

        configureDimButton()
        addSubview(dimButton)
        addLayoutGuide(cardGuide)
        configureCard()
        addSubview(card)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(imageView)

        configureChrome()
        card.addSubview(chrome, positioned: .above, relativeTo: nil)

        activateConstraints()
    }

    private func configureDimButton() {
        // A full-bleed transparent button captures background clicks to dismiss, without stealing clicks
        // from the card/live view above it.
        dimButton.isBordered = false
        dimButton.title = ""
        dimButton.wantsLayer = true
        dimButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        dimButton.translatesAutoresizingMaskIntoConstraints = false
        dimButton.target = self
        dimButton.action = #selector(dismissTapped)
        dimButton.setAccessibilityLabel("Dismiss zoomed diagram")
    }

    private func configureCard() {
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        card.layer?.cornerRadius = Self.cardCornerRadius
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.borderWidth = Self.cardBorderWidth
        card.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureChrome() {
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.onClose = { [weak self] in self?.onDismiss?() }
        chrome.onToggleFullscreen = { [weak self] in self?.onToggleFullscreen?() }
    }

    private func activateConstraints() {
        NSLayoutConstraint.activate([
            dimButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimButton.topAnchor.constraint(equalTo: topAnchor),
            dimButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.cardInset),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.cardInset),
            card.topAnchor.constraint(equalTo: topAnchor, constant: Self.cardInset),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.cardInset),
            imageView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Self.imageInset),
            imageView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Self.imageInset),
            imageView.topAnchor.constraint(equalTo: card.topAnchor, constant: Self.imageInset),
            imageView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Self.imageInset),
            chrome.topAnchor.constraint(equalTo: card.topAnchor, constant: Self.chromeEdgeInset),
            chrome.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Self.chromeEdgeInset)
        ])
    }

    func resetForReuse() {
        removeLiveView()
        imageView.image = nil
        imageView.isHidden = false
    }

    func triggerDismissForTesting() {
        onDismiss?()
    }
}

extension BlockInputView {
    func presentRenderedContentZoomModal(expansion: BlockInputRenderedContentExpansion) {
        let modal = renderedContentZoomModalView ?? BlockInputRenderedContentZoomModalView()
        modal.resetForReuse()
        modal.configure(image: expansion.image.image)
        modal.onDismiss = { [weak self] in
            self?.dismissRenderedContentZoomModal()
        }
        modal.onToggleFullscreen = { [weak self] in
            guard let self else { return }
            if self.diagramFullscreenWindow.isPresented {
                self.diagramFullscreenWindow.dismiss()
            } else {
                self.diagramFullscreenWindow.present(modal, restoringTo: self)
            }
            modal.setFullscreenActive(self.diagramFullscreenWindow.isPresented)
        }
        if modal.superview !== self {
            modal.removeFromSuperview()
            addSubview(modal, positioned: .above, relativeTo: nil)
        }
        modal.translatesAutoresizingMaskIntoConstraints = true
        modal.frame = bounds
        modal.autoresizingMask = [.width, .height]
        renderedContentZoomModalView = modal
        // The modal is now live (isBlockContentSurfacePresented is true); kill any open hover popover.
        hideLinkHoverEditAffordance()
        // Suspend canvas pinch/pan so trackpad gestures act on the modal, not the document underneath.
        pinchZoomController.isSuspended = true
        modal.startEscapeMonitor()
        window?.makeFirstResponder(modal)

        // Show the image instantly; swap in a live interactive view if the host provides one.
        if let provider = renderedContentZoomProvider {
            let context = BlockInputRenderedContentZoomContext(
                contentIdentifier: expansion.contentIdentifier,
                source: expansion.source
            )
            if let live = provider(context) {
                modal.showLiveView(live)
            }
        }
    }

    func dismissRenderedContentZoomModal() {
        exitFullscreenIfNeeded()
        renderedContentZoomModalView?.stopEscapeMonitor()
        renderedContentZoomModalView?.resetForReuse()
        renderedContentZoomModalView?.removeFromSuperview()
        renderedContentZoomModalView = nil
        pinchZoomController.isSuspended = false
        window?.makeFirstResponder(self)
    }
}
