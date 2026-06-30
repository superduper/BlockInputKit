import AppKit

/// Standalone surface that renders host-produced block content (e.g. a Mermaid diagram) as a scaled
/// image, with an expand affordance for zoom/pan. Modeled on ``BlockInputImageBlockView`` but without
/// resize gestures: rendered content scales to fit the column and is zoomed through the expand modal.
final class BlockInputRenderedContentBlockView: NSView {
    private let imageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let expandButton = NSButton()
    private let editButton = NSButton()
    /// Failure surface: an error banner on top, the broken source below, and a Fix-with-AI / Edit button row.
    private let failureView = BlockInputRenderedContentFailureView()
    /// Live content vended by a view-mode renderer (e.g. a hosted SVG view). Mutually exclusive with `imageView`.
    private var hostedView: NSView?
    private var loadedCacheKey: String?
    private var surfaceBorderColor: NSColor?
    private var selectionBorderColor: NSColor?
    weak var blockItem: BlockInputBlockItem?
    var onExpand: (() -> Void)?
    var onEdit: (() -> Void)?
    /// Invoked when the user clicks "Fix with AI" on a failed diagram (opens the editor in AI mode + auto-runs).
    var onFixWithAI: (() -> Void)?
    /// Whether the host wired an edit action (shows the ✏️ button only when diagram editing is available).
    var isEditAvailable = false
    var isEditable = true
    var disabledCursor: NSCursor?

    /// Shared overlay chrome metrics so the ✏️/⤢ buttons line up with the content gutter in every diagram mode.
    private static let overlayInset: CGFloat = 12
    private static let overlayButtonSize: CGFloat = 24
    private static let overlayButtonGap: CGFloat = 6
    /// The ✏️ pencil's trailing: pinned to the view corner when expand is hidden (failure), else left of expand.
    private var editButtonTrailingToCorner: NSLayoutConstraint?
    private var editButtonTrailingToExpand: NSLayoutConstraint?
    /// True for a successfully-rendered diagram: the ✏️/⤢ buttons are shown only while the pointer is over the
    /// diagram (set by `setActionButtonsVisible(true)`), so they stay out of the way in the document otherwise.
    private var actionButtonsHoverGated = false
    private var actionButtonsHovered = false
    private var actionButtonsTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func configurePlaceholder(style: BlockInputStyle) {
        isHidden = false
        loadedCacheKey = nil
        imageView.image = nil
        imageView.isHidden = true
        removeHostedView()
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        failureView.isHidden = true
        setActionButtonsVisible(false)
        applyPlaceholderStyle(style)
    }

    func configureRenderedImage(_ image: NSImage, cacheKey: String, style: BlockInputStyle) {
        isHidden = false
        loadedCacheKey = cacheKey
        removeHostedView()
        imageView.image = image
        imageView.isHidden = false
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        failureView.isHidden = true
        setActionButtonsVisible(true)
        applyLoadedStyle(style)
    }

    func reuseRenderedImage(cacheKey: String, style: BlockInputStyle) -> Bool {
        guard loadedCacheKey == cacheKey,
              imageView.image != nil,
              hostedView == nil else {
            return false
        }
        isHidden = false
        imageView.isHidden = false
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        failureView.isHidden = true
        setActionButtonsVisible(true)
        applyLoadedStyle(style)
        return true
    }

    /// Hosts a live view-mode renderer's content (e.g. a vector SVG view). The hosted view fills the surface,
    /// which is sized to the content's intrinsic dimensions by the block item's width constraint.
    func configureHostedView(_ view: NSView, cacheKey: String, style: BlockInputStyle) {
        isHidden = false
        loadedCacheKey = cacheKey
        imageView.image = nil
        imageView.isHidden = true
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        failureView.isHidden = true
        setActionButtonsVisible(false)
        removeHostedView()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view, positioned: .below, relativeTo: expandButton)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        hostedView = view
        applyLoadedStyle(style)
    }

    private func removeHostedView() {
        hostedView?.removeFromSuperview()
        hostedView = nil
    }

    /// Currently rendered image, used to seed the zoom modal.
    var renderedImage: NSImage? {
        imageView.image
    }

    func setSelectionBorderColor(_ color: NSColor?) {
        selectionBorderColor = color
        updateBorderLayer()
    }

    func configureFailure(style: BlockInputStyle, source: String, errorMessage: String?) {
        isHidden = false
        loadedCacheKey = nil
        imageView.image = nil
        imageView.isHidden = true
        removeHostedView()
        // The actionable failure surface (error links + bare source) replaces the old bare "failed" label.
        statusLabel.isHidden = true
        failureView.configure(source: source, errorMessage: errorMessage, fixAvailable: isEditAvailable)
        failureView.isHidden = false
        // Keep the ✏️ pencil (opens the code editor); the "Fix with AI" link handles the AI path. Expand is hidden
        // (nothing to zoom), so the pencil takes the right corner.
        expandButton.isHidden = true
        editButton.isHidden = !isEditAvailable
        setEditButtonInCorner(true)
        applyPlaceholderStyle(style)
    }

    func resetForReuse() {
        loadedCacheKey = nil
        imageView.image = nil
        imageView.isHidden = true
        removeHostedView()
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        failureView.isHidden = true
        setActionButtonsVisible(false)
        isHidden = true
        toolTip = nil
        setAccessibilityLabel(nil)
        isEditable = true
        disabledCursor = nil
        surfaceBorderColor = nil
        selectionBorderColor = nil
        onExpand = nil
        onEdit = nil
        onFixWithAI = nil
        isEditAvailable = false
        updateBorderLayer()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !isEditable, let disabledCursor {
            addCursorRect(bounds, cursor: disabledCursor)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if !isEditable {
            disabledCursor?.set()
            return
        }
        super.cursorUpdate(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinate space; convert before testing local geometry.
        let localPoint = convert(point, from: superview)
        guard !isHidden,
              alphaValue > 0,
              bounds.contains(localPoint) else {
            return nil
        }
        // The ✏️ pencil wins its top-right region in all states (including the failure surface).
        if !editButton.isHidden, editButton.frame.contains(localPoint) {
            return editButton
        }
        // When the failure surface is showing, let it (its links + selectable source) handle the rest.
        if !failureView.isHidden {
            return super.hitTest(point)
        }
        if !expandButton.isHidden, expandButton.frame.contains(localPoint) {
            return expandButton
        }
        return self
    }

    /// `visible` enables the ✏️/⤢ overlay for a rendered diagram, but they only actually show while the pointer
    /// is over the view (hover-gated); `false` hides + un-gates them (loading / non-diagram content).
    private func setActionButtonsVisible(_ visible: Bool) {
        actionButtonsHoverGated = visible
        if !visible { actionButtonsHovered = false }
        applyActionButtonVisibility()
        // Rendered diagram: expand is shown, so the pencil sits to its left.
        setEditButtonInCorner(false)
    }

    /// Shows the overlay buttons only when hover-gated AND the pointer is over the diagram. Skipped while the
    /// failure surface is up — there the ✏️ (Fix/Edit) is always shown regardless of hover.
    private func applyActionButtonVisibility() {
        guard failureView.isHidden else { return }
        let show = actionButtonsHoverGated && actionButtonsHovered
        expandButton.isHidden = !show
        editButton.isHidden = !(show && isEditAvailable)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let actionButtonsTrackingArea {
            removeTrackingArea(actionButtonsTrackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        actionButtonsTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        actionButtonsHovered = true
        applyActionButtonVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        actionButtonsHovered = false
        applyActionButtonVisibility()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        blockItem?.view.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        blockItem?.beginBlockSelectionDrag()
        blockItem?.requestSelectCurrentBlock()
    }

    override func mouseDragged(with event: NSEvent) {
        _ = blockItem?.updateBlockSelectionDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        blockItem?.finishBlockSelectionDrag()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityRole(.image)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        updateImageAlignment()
        addSubview(imageView)

        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.cell?.wraps = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        configureExpandButton()
        addSubview(expandButton)
        configureEditButton()
        addSubview(editButton)

        failureView.translatesAutoresizingMaskIntoConstraints = false
        failureView.isHidden = true
        failureView.onFixWithAI = { [weak self] in self?.onFixWithAI?() }
        // Below the overlay buttons so the ✏️ pencil stays clickable on top of the failure surface.
        addSubview(failureView, positioned: .below, relativeTo: editButton)

        NSLayoutConstraint.activate([
            failureView.leadingAnchor.constraint(equalTo: leadingAnchor),
            failureView.trailingAnchor.constraint(equalTo: trailingAnchor),
            failureView.topAnchor.constraint(equalTo: topAnchor),
            failureView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.overlayInset),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.overlayInset),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            expandButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.overlayInset),
            expandButton.topAnchor.constraint(equalTo: topAnchor, constant: Self.overlayInset),
            expandButton.widthAnchor.constraint(equalToConstant: Self.overlayButtonSize),
            expandButton.heightAnchor.constraint(equalToConstant: Self.overlayButtonSize),
            editButton.topAnchor.constraint(equalTo: topAnchor, constant: Self.overlayInset),
            editButton.widthAnchor.constraint(equalToConstant: Self.overlayButtonSize),
            editButton.heightAnchor.constraint(equalToConstant: Self.overlayButtonSize)
        ])

        // The pencil sits left of expand on a rendered diagram, but takes the right corner when expand is hidden
        // (the failure surface). Exactly one is active at a time — toggled in setActionButtonsVisible/configureFailure.
        editButtonTrailingToExpand = editButton.trailingAnchor.constraint(
            equalTo: expandButton.leadingAnchor, constant: -Self.overlayButtonGap
        )
        editButtonTrailingToCorner = editButton.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: -Self.overlayInset
        )
        editButtonTrailingToExpand?.isActive = true
    }

    /// Pins the ✏️ pencil to the right corner (when `corner` is true, e.g. failure with expand hidden) or left of
    /// the expand button (a normally rendered diagram).
    private func setEditButtonInCorner(_ corner: Bool) {
        editButtonTrailingToExpand?.isActive = !corner
        editButtonTrailingToCorner?.isActive = corner
    }

    private func configureExpandButton() {
        configureOverlayButton(
            expandButton,
            symbol: "arrow.up.left.and.arrow.down.right",
            label: "Zoom diagram",
            action: #selector(expandTapped)
        )
    }

    private func configureEditButton() {
        configureOverlayButton(editButton, symbol: "pencil", label: "Edit diagram", action: #selector(editTapped))
        setActionButtonsVisible(false)
    }

    private func configureOverlayButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        button.layer?.cornerRadius = 5
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
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

    private func applyPlaceholderStyle(_ style: BlockInputStyle) {
        let placeholderColor = style.imageBlock.placeholderColor ?? NSColor.quaternaryLabelColor.withAlphaComponent(0.28)
        layer?.backgroundColor = placeholderColor.cgColor
        applyBorderStyle(style)
        layer?.cornerRadius = style.imageBlock.cornerRadius ?? 6
    }

    private func applyLoadedStyle(_ style: BlockInputStyle) {
        // Rendered content may use a transparent background; give the surface a solid backdrop and a visible
        // border so the diagram reads clearly on both light and dark themes.
        layer?.backgroundColor = (style.imageBlock.placeholderColor ?? NSColor.textBackgroundColor).cgColor
        applyBorderStyle(style)
        layer?.cornerRadius = style.imageBlock.cornerRadius ?? 6
    }

    var renderedImageForTesting: NSImage? {
        imageView.image
    }

    var isFailureSurfaceVisibleForTesting: Bool {
        !failureView.isHidden
    }

    var failureErrorTextForTesting: String {
        failureView.errorTextForTesting
    }

    var failureSourceTextForTesting: String {
        failureView.sourceTextForTesting
    }

    var isFixWithAIButtonVisibleForTesting: Bool {
        failureView.isFixLinkVisibleForTesting
    }

    func clickFixWithAIForTesting() {
        onFixWithAI?()
    }

    var isExpandButtonVisibleForTesting: Bool {
        !expandButton.isHidden
    }

    /// Simulates pointer enter/exit so tests can assert the hover-gated ✏️/⤢ overlay visibility.
    func setHoveredForTesting(_ hovered: Bool) {
        actionButtonsHovered = hovered
        applyActionButtonVisibility()
    }

    var hasSelectionBorderForTesting: Bool {
        selectionBorderColor != nil
    }

    var expandButtonFrameForTesting: NSRect {
        expandButton.frame
    }

    private func updateImageAlignment() {
        imageView.imageAlignment = userInterfaceLayoutDirection == .rightToLeft ? .alignRight : .alignLeft
    }

    private func applyBorderStyle(_ style: BlockInputStyle) {
        // Always show a border for diagrams (fall back to a separator color) so the surface is delineated
        // on dark mode where the image-block style often provides no border.
        surfaceBorderColor = style.imageBlock.borderColor ?? NSColor.separatorColor
        updateBorderLayer()
    }

    private func updateBorderLayer() {
        if let selectionBorderColor {
            layer?.borderColor = selectionBorderColor.cgColor
            layer?.borderWidth = 2
        } else if let surfaceBorderColor {
            layer?.borderColor = surfaceBorderColor.cgColor
            layer?.borderWidth = 1
        } else {
            layer?.borderColor = nil
            layer?.borderWidth = 0
        }
    }
}
