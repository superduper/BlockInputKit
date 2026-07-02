import AppKit

/// Standalone surface that renders host-produced block content (e.g. a Mermaid diagram) as a scaled
/// image, with an expand affordance for zoom/pan. Modeled on ``BlockInputImageBlockView`` but without
/// resize gestures: rendered content scales to fit the column and is zoomed through the expand modal.
final class BlockInputRenderedContentBlockView: NSView {
    private let imageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    // Not `private`: the button setup lives in the +OverlayButtons companion file.
    let expandButton = NSButton()
    let editButton = NSButton()
    /// Enclosing rounded box that supplies the solid opaque scrim behind the ✏️/⤢ button cluster.
    private let overlayButtonBox = NSView()
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
    /// Whether the ⤢ zoom/expand affordance applies. True for a rendered image (zoomable); false for a hosted
    /// interactive view such as the TOC config panel, where only the ✏️ edit button makes sense.
    private var isExpandAvailable = true
    var isEditable = true
    var disabledCursor: NSCursor?

    /// Shared overlay chrome metrics so the ✏️/⤢ buttons line up with the content gutter in every diagram mode.
    /// The enclosing box now supplies the separation from the diagram, so the inset is back to its original value.
    private static let overlayInset: CGFloat = 12
    private static let overlayButtonSize: CGFloat = 24
    private static let overlayButtonGap: CGFloat = 6
    /// Internal padding between the box edge and each button (all four sides).
    private static let overlayBoxPadding: CGFloat = 8
    /// The ✏️ pencil's trailing: pinned to the box corner when expand is hidden (failure), else left of expand.
    private var editButtonTrailingToCorner: NSLayoutConstraint?
    private var editButtonTrailingToExpand: NSLayoutConstraint?
    /// Pins the expand button to the box's trailing edge; deactivated in edit-only (corner) mode so the hidden
    /// expand button doesn't fight the edit button for the box's right edge (which collapsed the box).
    private var expandTrailingToBox: NSLayoutConstraint?
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
        // Hosted interactive views (e.g. the TOC) get the hover ✏️ edit button (opens the interactive
        // provider / config panel) but no ⤢ expand — there's nothing to zoom.
        setActionButtonsVisible(true, expandAvailable: false)
        removeHostedView()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view, positioned: .below, relativeTo: overlayButtonBox)
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
        overlayButtonBox.isHidden = !isEditAvailable
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
        } else if hostedView != nil {
            // A hosted interactive/read-only view (e.g. the TOC) owns its cursor region. Claim an arrow rect
            // over the surface so the OUTER editable editor's I-beam can't bleed in; the inner view's own
            // cursorUpdate refines it (pointer over links, its disabledCursor elsewhere).
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if !isEditable {
            disabledCursor?.set()
            return
        }
        if hostedView != nil {
            // Let the hosted inner view drive its own cursor; don't fall through to the outer I-beam.
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
        // The box wraps the ✏️/⤢ cluster; delegate to its own hitTest when the point is inside it.
        // This works in all states: on the failure surface the box shows with just ✏️, and on a
        // successfully-rendered diagram it shows with both buttons (hover-gated).
        if !overlayButtonBox.isHidden, overlayButtonBox.frame.contains(localPoint) {
            return overlayButtonBox.hitTest(localPoint) ?? overlayButtonBox
        }
        // When the failure surface is showing, let it (its links + selectable source) handle the rest.
        if !failureView.isHidden {
            return super.hitTest(point)
        }
        // A hosted interactive view (e.g. the read-only TOC) must receive clicks itself so its own
        // links/handlers fire. hostedView is a subview of self, so hitTest takes the point in self's coords.
        if let hostedView, let hit = hostedView.hitTest(localPoint) {
            return hit
        }
        return self
    }

    /// `visible` enables the ✏️/⤢ overlay for a rendered diagram, but they only actually show while the pointer
    /// is over the view (hover-gated); `false` hides + un-gates them (loading / non-diagram content).
    func setActionButtonsVisible(_ visible: Bool, expandAvailable: Bool = true) {
        actionButtonsHoverGated = visible
        isExpandAvailable = expandAvailable
        if !visible { actionButtonsHovered = false }
        applyActionButtonVisibility()
    }

    /// Shows the overlay buttons only when hover-gated AND the pointer is over the diagram. Skipped while the
    /// failure surface is up — there the ✏️ (Fix/Edit) is always shown regardless of hover.
    private func applyActionButtonVisibility() {
        guard failureView.isHidden else { return }
        let show = actionButtonsHoverGated && actionButtonsHovered
        let showExpand = show && isExpandAvailable
        let showEdit = show && isEditAvailable
        expandButton.isHidden = !showExpand
        editButton.isHidden = !showEdit
        // Pencil takes the box corner when expand is hidden (hosted views); box shows if any button is visible.
        setEditButtonInCorner(!showExpand)
        overlayButtonBox.isHidden = !(showExpand || showEdit)
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

        // Configure the enclosing rounded box that provides the solid scrim behind the button cluster.
        overlayButtonBox.wantsLayer = true
        overlayButtonBox.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        overlayButtonBox.layer?.cornerRadius = 7
        overlayButtonBox.layer?.borderWidth = 1
        overlayButtonBox.layer?.borderColor = NSColor.separatorColor.cgColor
        overlayButtonBox.layer?.masksToBounds = true
        overlayButtonBox.translatesAutoresizingMaskIntoConstraints = false
        overlayButtonBox.isHidden = true
        addSubview(overlayButtonBox)

        // Buttons are subviews of the box; the box supplies the enclosing chrome.
        configureExpandButton()
        overlayButtonBox.addSubview(expandButton)
        configureEditButton()
        overlayButtonBox.addSubview(editButton)

        failureView.translatesAutoresizingMaskIntoConstraints = false
        failureView.isHidden = true
        failureView.onFixWithAI = { [weak self] in self?.onFixWithAI?() }
        // Below the overlay box so the ✏️ pencil stays clickable on top of the failure surface.
        addSubview(failureView, positioned: .below, relativeTo: overlayButtonBox)

        setupOverlayConstraints()
    }

    private func setupOverlayConstraints() {
        let pad = Self.overlayBoxPadding
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
            // Box pinned to top-right corner of self.
            overlayButtonBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.overlayInset),
            overlayButtonBox.topAnchor.constraint(equalTo: topAnchor, constant: Self.overlayInset),
            // Box left edge hugs the left edge of the edit button (always the leftmost button).
            overlayButtonBox.leadingAnchor.constraint(equalTo: editButton.leadingAnchor, constant: -pad),
            // Expand button geometry (its box-trailing pin is toggled below so it doesn't fight the edit
            // button for the box's right edge when expand is hidden).
            expandButton.topAnchor.constraint(equalTo: overlayButtonBox.topAnchor, constant: pad),
            expandButton.bottomAnchor.constraint(equalTo: overlayButtonBox.bottomAnchor, constant: -pad),
            expandButton.widthAnchor.constraint(equalToConstant: Self.overlayButtonSize),
            expandButton.heightAnchor.constraint(equalToConstant: Self.overlayButtonSize),
            editButton.topAnchor.constraint(equalTo: overlayButtonBox.topAnchor, constant: pad),
            editButton.bottomAnchor.constraint(equalTo: overlayButtonBox.bottomAnchor, constant: -pad),
            editButton.widthAnchor.constraint(equalToConstant: Self.overlayButtonSize),
            editButton.heightAnchor.constraint(equalToConstant: Self.overlayButtonSize)
        ])

        // Exactly ONE button owns the box's trailing edge at a time:
        // - expand shown  → expand hugs box trailing, edit sits left of expand (`editButtonTrailingToExpand`).
        // - expand hidden → edit hugs box trailing (`editButtonTrailingToCorner`); expand's pin is off.
        expandTrailingToBox = expandButton.trailingAnchor.constraint(
            equalTo: overlayButtonBox.trailingAnchor, constant: -pad
        )
        editButtonTrailingToExpand = editButton.trailingAnchor.constraint(
            equalTo: expandButton.leadingAnchor, constant: -Self.overlayButtonGap
        )
        editButtonTrailingToCorner = editButton.trailingAnchor.constraint(
            equalTo: overlayButtonBox.trailingAnchor, constant: -pad
        )
        expandTrailingToBox?.isActive = true
        editButtonTrailingToExpand?.isActive = true
    }

    /// Pins the ✏️ pencil to the right corner of the box (when `corner` is true, e.g. failure with expand hidden)
    /// or left of the expand button (a normally rendered diagram).
    private func setEditButtonInCorner(_ corner: Bool) {
        // In corner (edit-only) mode the expand button is hidden, so release its box-trailing pin first to
        // avoid an over-constrained box, then let the edit button own the trailing edge.
        expandTrailingToBox?.isActive = !corner
        editButtonTrailingToExpand?.isActive = !corner
        editButtonTrailingToCorner?.isActive = corner
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

    // MARK: - Test accessors

    /// True when the hosted-view arrow-cursor branch is active (editable host with a hosted view present).
    var hasArrowCursorRectForTesting: Bool { hostedView != nil && isEditable }
    var renderedImageForTesting: NSImage? { imageView.image }
    var isFailureSurfaceVisibleForTesting: Bool { !failureView.isHidden }
    var failureErrorTextForTesting: String { failureView.errorTextForTesting }
    var failureSourceTextForTesting: String { failureView.sourceTextForTesting }
    var isFixWithAIButtonVisibleForTesting: Bool { failureView.isFixLinkVisibleForTesting }
    func clickFixWithAIForTesting() { onFixWithAI?() }
    var isExpandButtonVisibleForTesting: Bool { !expandButton.isHidden }
    var hasSelectionBorderForTesting: Bool { selectionBorderColor != nil }
    /// The expand button frame in the surface's own coordinate space (the button is a subview of the box).
    var expandButtonFrameForTesting: NSRect {
        overlayButtonBox.convert(expandButton.frame, to: self)
    }

    /// Simulates pointer enter/exit so tests can assert the hover-gated ✏️/⤢ overlay visibility.
    func setHoveredForTesting(_ hovered: Bool) {
        actionButtonsHovered = hovered
        applyActionButtonVisibility()
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
