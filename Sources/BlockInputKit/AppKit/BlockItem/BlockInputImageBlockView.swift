import AppKit

final class BlockInputImageBlockView: NSView {
    private let imageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var resizeStart: ResizeState?
    private var cleansUpDeferredResizeStateOnMouseUp = false
    private var loadedCacheKey: String?
    private var surfaceBorderColor: NSColor?
    private var selectionBorderColor: NSColor?
    weak var blockItem: BlockInputBlockItem?
    var onResize: ((Int, Int) -> Void)?
    var resizeDimensions: BlockInputImageDimensions?
    var isEditable = true
    var disabledCursor: NSCursor?
    var maximumResizeWidth = Int.max

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
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        applyPlaceholderStyle(style)
    }

    func configureLoadedImage(_ image: NSImage, cacheKey: String, style: BlockInputStyle, resizeDimensions: BlockInputImageDimensions?) {
        isHidden = false
        loadedCacheKey = cacheKey
        imageView.image = image
        self.resizeDimensions = resizeDimensions
        imageView.isHidden = false
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        applyLoadedStyle(style)
    }

    func reuseLoadedImage(cacheKey: String, style: BlockInputStyle, resizeDimensions: BlockInputImageDimensions?) -> Bool {
        guard loadedCacheKey == cacheKey,
              imageView.image != nil else {
            return false
        }
        isHidden = false
        self.resizeDimensions = resizeDimensions
        imageView.isHidden = false
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        applyLoadedStyle(style)
        return true
    }

    func setSelectionBorderColor(_ color: NSColor?) {
        selectionBorderColor = color
        updateBorderLayer()
    }

    func configureFailure(style: BlockInputStyle) {
        isHidden = false
        loadedCacheKey = nil
        imageView.image = nil
        imageView.isHidden = true
        statusLabel.stringValue = "Image failed to load"
        statusLabel.isHidden = false
        applyPlaceholderStyle(style)
    }

    func resetForReuse() {
        loadedCacheKey = nil
        imageView.image = nil
        imageView.isHidden = true
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        isHidden = true
        toolTip = nil
        setAccessibilityLabel(nil)
        isEditable = true
        disabledCursor = nil
        surfaceBorderColor = nil
        selectionBorderColor = nil
        if resizeStart == nil {
            resizeDimensions = nil
            maximumResizeWidth = Int.max
            onResize = nil
        } else {
            // SwiftUI hosts may reconfigure/reuse the row while AppKit still sends drag events to this mouse-down view.
            // Keep the active resize callback alive until mouse-up so the gesture can finish against the current block.
            cleansUpDeferredResizeStateOnMouseUp = true
        }
        updateBorderLayer()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !isEditable, let disabledCursor {
            addCursorRect(bounds, cursor: disabledCursor)
        }
        guard isEditable, resizeDimensions != nil else {
            return
        }
        addCursorRect(rightResizeHitRect, cursor: .resizeLeftRight)
        addCursorRect(bottomResizeHitRect, cursor: .resizeUpDown)
    }

    override func cursorUpdate(with event: NSEvent) {
        if !isEditable {
            disabledCursor?.set()
            return
        }
        if let cursor = resizeCursor(at: convert(event.locationInWindow, from: nil)) {
            cursor.set()
            return
        }
        super.cursorUpdate(with: event)
    }

    override func layout() {
        super.layout()
        updateImageAlignment()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden,
              alphaValue > 0,
              hitBounds.contains(point) else {
            return nil
        }
        // Keep mouse handling on the image surface instead of its image/label children so resize and selection share
        // one path for both loaded and placeholder states.
        return self
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        blockItem?.view.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditable,
              let dimensions = resizeDimensions,
              let edge = resizeEdge(at: convert(event.locationInWindow, from: nil)) else {
            blockItem?.beginBlockSelectionDrag()
            blockItem?.requestSelectCurrentBlock()
            return
        }
        let displayedDimensions = displayedResizeDimensions(for: dimensions)
        cleansUpDeferredResizeStateOnMouseUp = false
        resizeStart = ResizeState(
            edge: edge,
            origin: event.locationInWindow,
            dimensions: displayedDimensions,
            aspectRatio: CGFloat(displayedDimensions.width) / CGFloat(displayedDimensions.height)
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditable, let resizeStart else {
            _ = blockItem?.updateBlockSelectionDrag(with: event)
            return
        }
        let resized = resizedDimensions(for: event, resizeStart: resizeStart)
        guard resized != resizeDimensions else {
            return
        }
        resizeDimensions = resized
        onResize?(resized.width, resized.height)
    }

    override func mouseUp(with event: NSEvent) {
        resizeStart = nil
        if cleansUpDeferredResizeStateOnMouseUp, isHidden {
            resizeDimensions = nil
            maximumResizeWidth = Int.max
            onResize = nil
        }
        cleansUpDeferredResizeStateOnMouseUp = false
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
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func applyPlaceholderStyle(_ style: BlockInputStyle) {
        layer?.backgroundColor = (style.imageBlock.placeholderColor ?? NSColor.quaternaryLabelColor.withAlphaComponent(0.28)).cgColor
        applyBorderStyle(style)
        layer?.cornerRadius = style.imageBlock.cornerRadius ?? 6
    }

    private func applyLoadedStyle(_ style: BlockInputStyle) {
        layer?.backgroundColor = NSColor.clear.cgColor
        applyBorderStyle(style)
        layer?.cornerRadius = style.imageBlock.cornerRadius ?? 6
    }

    var loadedImageForTesting: NSImage? {
        imageView.image
    }

    var statusTextForTesting: String {
        statusLabel.stringValue
    }

    var imageAlignmentForTesting: NSImageAlignment {
        imageView.imageAlignment
    }

    private func updateImageAlignment() {
        imageView.imageAlignment = userInterfaceLayoutDirection == .rightToLeft ? .alignRight : .alignLeft
    }

    private func resizeEdge(at point: NSPoint) -> ResizeEdge? {
        if rightResizeHitRect.contains(point) {
            return .right
        }
        if bottomResizeHitRect.contains(point) {
            return .bottom
        }
        return nil
    }

    func containsResizeHitTarget(_ point: NSPoint) -> Bool {
        isEditable && (rightResizeHitRect.contains(point) || bottomResizeHitRect.contains(point))
    }

    func resizeCursor(at point: NSPoint) -> NSCursor? {
        guard isEditable else {
            return nil
        }
        switch resizeEdge(at: point) {
        case .right:
            return .resizeLeftRight
        case .bottom:
            return .resizeUpDown
        case nil:
            return nil
        }
    }

    var rightResizeCursorRect: NSRect {
        rightResizeHitRect
    }

    var bottomResizeCursorRect: NSRect {
        bottomResizeHitRect
    }

    private var hitBounds: NSRect {
        guard resizeDimensions != nil else {
            return bounds
        }
        return NSRect(
            x: bounds.minX,
            y: bounds.minY - imageResizeHitOutset,
            width: bounds.width + imageResizeHitOutset,
            height: bounds.height + (2 * imageResizeHitOutset)
        )
    }

    private var rightResizeHitRect: NSRect {
        NSRect(
            x: bounds.maxX - imageResizeHitThickness,
            y: bounds.minY - imageResizeHitOutset,
            width: imageResizeHitThickness + imageResizeHitOutset,
            height: bounds.height + (2 * imageResizeHitOutset)
        )
    }

    private var bottomResizeHitRect: NSRect {
        NSRect(
            x: bounds.minX,
            y: bounds.minY - imageResizeHitOutset,
            width: bounds.width,
            height: imageResizeHitThickness + imageResizeHitOutset
        )
    }

    private func applyBorderStyle(_ style: BlockInputStyle) {
        surfaceBorderColor = style.imageBlock.borderColor
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

    private func displayedResizeDimensions(for dimensions: BlockInputImageDimensions) -> BlockInputImageDimensions {
        let width = max(CGFloat(dimensions.width), 1)
        let height = max(CGFloat(dimensions.height), 1)
        guard bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0 else {
            return dimensions
        }
        // Resize gestures operate in rendered editor coordinates. Without this scale-down, a huge source image must be
        // dragged hundreds or thousands of points before the visible full-width rendering changes.
        let scale = min(bounds.width / width, bounds.height / height)
        guard scale.isFinite,
              scale > 0 else {
            return dimensions
        }
        return BlockInputImageDimensions(
            width: max(1, Int((width * scale).rounded())),
            height: max(1, Int((height * scale).rounded()))
        )
    }

    private func resizedDimensions(for event: NSEvent, resizeStart: ResizeState) -> BlockInputImageDimensions {
        let minimumDimension: CGFloat = 24
        let aspectRatio = max(resizeStart.aspectRatio, 0.01)
        let maximumWidth = max(minimumDimension, CGFloat(maximumResizeWidth))
        let deltaX = event.locationInWindow.x - resizeStart.origin.x
        let deltaY = event.locationInWindow.y - resizeStart.origin.y
        let proposedSize: NSSize
        switch resizeStart.edge {
        case .right:
            let width = CGFloat(resizeStart.dimensions.width) + deltaX
            proposedSize = NSSize(width: width, height: width / aspectRatio)
        case .bottom:
            let height = CGFloat(resizeStart.dimensions.height) - deltaY
            proposedSize = NSSize(width: height * aspectRatio, height: height)
        }
        let clampedSize = clampedProportionalSize(
            proposedSize,
            aspectRatio: aspectRatio,
            minimumDimension: minimumDimension,
            maximumWidth: maximumWidth
        )
        return BlockInputImageDimensions(
            width: Int(clampedSize.width.rounded()),
            height: Int(clampedSize.height.rounded())
        )
    }

    private func clampedProportionalSize(
        _ size: NSSize,
        aspectRatio: CGFloat,
        minimumDimension: CGFloat,
        maximumWidth: CGFloat
    ) -> NSSize {
        var width = min(max(size.width, minimumDimension), maximumWidth)
        var height = width / aspectRatio
        if height < minimumDimension {
            height = minimumDimension
            width = min(max(height * aspectRatio, minimumDimension), maximumWidth)
            height = width / aspectRatio
        }
        return NSSize(width: width, height: height)
    }
}

private struct ResizeState {
    var edge: ResizeEdge
    var origin: NSPoint
    var dimensions: BlockInputImageDimensions
    var aspectRatio: CGFloat
}

private enum ResizeEdge {
    case right
    case bottom
}

private let imageResizeHitThickness: CGFloat = 8
private let imageResizeHitOutset: CGFloat = 4
