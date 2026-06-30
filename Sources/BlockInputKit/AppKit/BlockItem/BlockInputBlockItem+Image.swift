import AppKit

struct BlockInputImageBlockLoadingContext {
    var loader: any BlockInputImageLoading
    var diskCache: (any BlockInputImageDiskCaching)?
    var baseURL: URL?
    var allowsRemoteLoading: Bool
    var maximumSourceBytes: Int
    var maximumPixelDimension: Int

    init(
        loader: any BlockInputImageLoading = BlockInputDefaultImageLoader(),
        diskCache: (any BlockInputImageDiskCaching)? = nil,
        baseURL: URL? = nil,
        allowsRemoteLoading: Bool = true,
        maximumSourceBytes: Int = 20 * 1024 * 1024,
        maximumPixelDimension: Int = 8_192
    ) {
        self.loader = loader
        self.diskCache = diskCache
        self.baseURL = baseURL
        self.allowsRemoteLoading = allowsRemoteLoading
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumPixelDimension = maximumPixelDimension
    }
}

extension BlockInputBlockItem {
    static let minimumImageDisplayDimension: CGFloat = 24

    static func imageHeight(
        for image: BlockInputImage,
        textWidth: CGFloat,
        defaultAspectRatio: CGFloat,
        blockVerticalInsetMultiplier: CGFloat = 1,
        zoomScale: CGFloat = 1
    ) -> CGFloat {
        let contentHeight = imageDisplaySize(
            for: image,
            textWidth: textWidth,
            defaultAspectRatio: defaultAspectRatio,
            zoomScale: zoomScale
        ).height
        return max(44, ceil(contentHeight)) + (scaledImageExternalVerticalInset(for: blockVerticalInsetMultiplier) * 2)
    }

    static func imageDisplaySize(
        for image: BlockInputImage,
        textWidth: CGFloat,
        defaultAspectRatio: CGFloat,
        zoomScale: CGFloat = 1
    ) -> NSSize {
        let availableWidth = max(textWidth, 120)
        let aspectRatio = max(defaultAspectRatio, 0.01)
        let scale = zoomScale.isFinite ? max(zoomScale, 0.01) : 1
        let sourceWidth: CGFloat
        let sourceHeight: CGFloat
        switch (image.width, image.height) {
        case let (width?, height?):
            sourceWidth = CGFloat(width)
            sourceHeight = CGFloat(height)
        case let (width?, nil):
            sourceWidth = CGFloat(width)
            sourceHeight = sourceWidth / aspectRatio
        case let (nil, height?):
            sourceHeight = CGFloat(height)
            sourceWidth = sourceHeight * aspectRatio
        case (nil, nil):
            sourceWidth = availableWidth
            sourceHeight = availableWidth / aspectRatio
        }
        // Scale the intrinsic size by the zoom factor before clamping to the container, so zoomed images
        // grow with the text until they fill the available width, matching browser/PDF zoom behavior.
        return constrainedImageDisplaySize(
            width: sourceWidth * scale,
            height: sourceHeight * scale,
            availableWidth: availableWidth
        )
    }

    func configureImageBlockIfNeeded(for block: BlockInputBlock) {
        guard case let .image(image) = block.kind else {
            cancelImageLoad()
            imageBlockView.resetForReuse()
            return
        }
        imageBlockView.toolTip = image.altText.isEmpty ? image.source : image.altText
        imageBlockView.setAccessibilityLabel(image.altText.isEmpty ? image.source : image.altText)
        imageBlockView.resizeDimensions = image.resizeDimensions
        imageBlockView.onResize = { [weak self] width, height in
            guard let self else {
                return
            }
            self.delegate?.blockItem(self, blockID: block.id, didResizeImageToWidth: width, height: height)
        }
        guard let resolvedURL = image.resolvedURL(relativeTo: imageLoadingContext.baseURL),
              allowsLoading(resolvedURL) else {
            cancelImageLoad()
            imageBlockView.configureFailure(style: style)
            return
        }
        let cacheKey = image.cacheKey(
            resolvedURL: resolvedURL,
            maximumPixelDimension: imageLoadingContext.maximumPixelDimension
        )
        if imageBlockView.reuseLoadedImage(cacheKey: cacheKey, style: style, resizeDimensions: image.resizeDimensions) {
            cancelImageLoad()
            return
        }
        if imageLoadCacheKey == cacheKey, imageLoadTask != nil {
            return
        }
        cancelImageLoad()
        imageBlockView.configurePlaceholder(style: style)
        startImageLoad(for: image, resolvedURL: resolvedURL, cacheKey: cacheKey, blockID: block.id)
    }

    private func cancelImageLoad() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        imageLoadCacheKey = nil
    }

    private func startImageLoad(
        for image: BlockInputImage,
        resolvedURL: URL,
        cacheKey: String,
        blockID: BlockInputBlockID
    ) {
        let request = BlockInputImageLoadRequest(
            image: image,
            resolvedURL: resolvedURL,
            cacheKey: cacheKey,
            maxSourceBytes: imageLoadingContext.maximumSourceBytes,
            maxPixelDimension: imageLoadingContext.maximumPixelDimension,
            diskCache: imageLoadingContext.diskCache
        )
        let loader = imageLoadingContext.loader
        imageLoadCacheKey = cacheKey
        imageLoadTask = Task { [weak self] in
            do {
                let loaded = try await loader.loadImage(request)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.finishImageLoad(loaded, request: request, blockID: blockID)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.finishImageLoadFailure(blockID: blockID, cacheKey: cacheKey)
                }
            }
        }
    }

    private func finishImageLoad(
        _ loaded: BlockInputLoadedImage,
        request: BlockInputImageLoadRequest,
        blockID: BlockInputBlockID
    ) {
        guard renderedBlock?.id == blockID,
              imageLoadCacheKey == request.cacheKey else {
            return
        }
        imageLoadTask = nil
        imageLoadCacheKey = nil
        guard let nsImage = NSImage(data: loaded.data) else {
            imageBlockView.configureFailure(style: style)
            return
        }
        let resolvedDimensions = request.image.resolvedResizeDimensions(using: loaded.dimensions)
        imageBlockView.configureLoadedImage(
            nsImage,
            cacheKey: request.cacheKey,
            style: style,
            resizeDimensions: resolvedDimensions
        )
        if request.image.resizeDimensions != resolvedDimensions {
            delegate?.blockItem(
                self,
                blockID: blockID,
                didResolveImageDimensions: resolvedDimensions
            )
        }
    }

    private func finishImageLoadFailure(blockID: BlockInputBlockID, cacheKey: String) {
        guard renderedBlock?.id == blockID,
              imageLoadCacheKey == cacheKey else {
            return
        }
        imageLoadTask = nil
        imageLoadCacheKey = nil
        imageBlockView.configureFailure(style: style)
    }

    private func allowsLoading(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return true
        }
        return imageLoadingContext.allowsRemoteLoading
    }

    func updateImageBlockLayout(for block: BlockInputBlock) {
        guard case let .image(image) = block.kind else {
            return
        }
        let itemWidth = view.bounds.width > 0 ? view.bounds.width : 0
        let scrollViewWidth = Self.textScrollViewWidth(
            for: itemWidth,
            block: block,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        )
        let textWidth = Self.measuredTextWidth(
            for: itemWidth,
            block: block,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        )
        let displaySize = Self.imageDisplaySize(
            for: image,
            textWidth: textWidth,
            defaultAspectRatio: style.imageBlock.placeholderAspectRatio ?? 16.0 / 9.0,
            zoomScale: Self.baseFontScale(for: style)
        )
        imageBlockWidthConstraint?.constant = displaySize.width
        imageBlockView.maximumResizeWidth = max(24, Int(max(textWidth, 120).rounded()))
        imageBlockLeadingConstraint?.constant = imageHorizontalOffset(
            displayWidth: displaySize.width,
            contentWidth: textWidth,
            containerWidth: scrollViewWidth
        )
        updateImageCaretFrame()
    }

    func setImageCaretOffset(_ offset: Int?) {
        guard let offset,
              isImageBlock,
              offset >= 0,
              offset <= 1 else {
            imageCaretOffset = nil
            imageCaretView.isHidden = true
            imageCaretView.setAccessibilityLabel(nil)
            return
        }
        imageCaretOffset = offset
        imageCaretView.isHidden = false
        imageCaretView.alphaValue = 1
        imageCaretView.layer?.backgroundColor = NSColor.keyboardFocusIndicatorColor.cgColor
        imageCaretView.setAccessibilityLabel(offset == 0 ? "Before image" : "After image")
        updateImageCaretFrame()
    }

    func updateImageCaretFrame() {
        guard let imageCaretOffset,
              isImageBlock,
              !imageBlockView.isHidden else {
            imageCaretView.isHidden = true
            return
        }
        let caretWidth: CGFloat = 2
        let caretHeight = imageBlockView.frame.height
        let caretX = imageCaretX(offset: imageCaretOffset, width: caretWidth)
        imageCaretView.frame = NSRect(x: caretX, y: imageBlockView.frame.minY, width: caretWidth, height: caretHeight)
        imageCaretView.isHidden = false
    }

    func imageCaretOffset(containing rootPoint: NSPoint) -> Int? {
        guard isImageBlock,
              !imageBlockView.isHidden,
              imageResizeHitView(containing: rootPoint) == nil else {
            return nil
        }
        let topZone = NSRect(
            x: imageBlockView.frame.minX,
            y: imageBlockView.frame.maxY,
            width: imageBlockView.frame.width,
            height: max(
                view.bounds.maxY - imageBlockView.frame.maxY,
                Self.scaledImageExternalVerticalInset(for: blockVerticalInsetMultiplier)
            )
        )
        let bottomZone = NSRect(
            x: imageBlockView.frame.minX,
            y: view.bounds.minY,
            width: imageBlockView.frame.width,
            height: max(
                imageBlockView.frame.minY - view.bounds.minY,
                Self.scaledImageExternalVerticalInset(for: blockVerticalInsetMultiplier)
            )
        )
        if topZone.contains(rootPoint) {
            return 0
        }
        if bottomZone.contains(rootPoint) {
            return 1
        }
        let sideZones = imageSideCaretZones()
        let leadingZone = sideZones.leading
        let trailingZone = sideZones.trailing
        if leadingZone.contains(rootPoint) {
            return 0
        }
        if trailingZone.contains(rootPoint) {
            return 1
        }
        return nil
    }

    private func imageSideCaretZones() -> (leading: NSRect, trailing: NSRect) {
        let leftZone = NSRect(
            x: view.bounds.minX,
            y: imageBlockView.frame.minY,
            width: max(imageBlockView.frame.minX - view.bounds.minX, Self.imageSurfaceHorizontalInset),
            height: imageBlockView.frame.height
        )
        let rightZone = NSRect(
            x: imageBlockView.frame.maxX,
            y: imageBlockView.frame.minY,
            width: max(view.bounds.maxX - imageBlockView.frame.maxX, Self.imageSurfaceHorizontalInset),
            height: imageBlockView.frame.height
        )
        return view.userInterfaceLayoutDirection == .rightToLeft
            ? (leading: rightZone, trailing: leftZone)
            : (leading: leftZone, trailing: rightZone)
    }

    private func imageCaretX(offset: Int, width: CGFloat) -> CGFloat {
        switch (offset, view.userInterfaceLayoutDirection) {
        case (0, .rightToLeft), (1, .leftToRight):
            return min(imageBlockView.frame.maxX, view.bounds.maxX - width)
        default:
            return max(imageBlockView.frame.minX - width, view.bounds.minX)
        }
    }

    private func imageHorizontalOffset(displayWidth: CGFloat, contentWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let startInset = Self.imageSurfaceHorizontalInset
        guard view.userInterfaceLayoutDirection == .rightToLeft else {
            return startInset
        }
        let boundedContentWidth = min(contentWidth, max(containerWidth - (2 * startInset), 0))
        return startInset + max(boundedContentWidth - displayWidth, 0)
    }

    func imageResizeHitView(containing rootPoint: NSPoint) -> BlockInputImageBlockView? {
        guard !imageBlockView.isHidden,
              imageBlockView.resizeDimensions != nil else {
            return nil
        }
        let imagePoint = imageBlockView.convert(rootPoint, from: view)
        return imageBlockView.containsResizeHitTarget(imagePoint) ? imageBlockView : nil
    }

    func addImageResizeCursorRects(to rootView: NSView) {
        guard !imageBlockView.isHidden,
              imageBlockView.resizeDimensions != nil else {
            return
        }
        rootView.addCursorRect(rootView.convert(imageBlockView.rightResizeCursorRect, from: imageBlockView), cursor: .resizeLeftRight)
        rootView.addCursorRect(rootView.convert(imageBlockView.bottomResizeCursorRect, from: imageBlockView), cursor: .resizeUpDown)
    }

    func imageResizeCursor(at rootPoint: NSPoint) -> NSCursor? {
        guard !imageBlockView.isHidden,
              imageBlockView.resizeDimensions != nil else {
            return nil
        }
        return imageBlockView.resizeCursor(at: imageBlockView.convert(rootPoint, from: view))
    }

    private static func constrainedImageDisplaySize(
        width: CGFloat,
        height: CGFloat,
        availableWidth: CGFloat
    ) -> NSSize {
        let safeWidth = max(width, minimumImageDisplayDimension)
        let safeHeight = max(height, minimumImageDisplayDimension)
        let scale = min(availableWidth / safeWidth, 1)
        return NSSize(
            width: ceil(safeWidth * scale),
            height: ceil(safeHeight * scale)
        )
    }
}

private extension BlockInputImage {
    var resizeDimensions: BlockInputImageDimensions? {
        guard let width, let height else {
            return nil
        }
        return BlockInputImageDimensions(width: width, height: height)
    }

    func resolvedResizeDimensions(using naturalDimensions: BlockInputImageDimensions) -> BlockInputImageDimensions {
        let naturalWidth = max(CGFloat(naturalDimensions.width), 1)
        let naturalHeight = max(CGFloat(naturalDimensions.height), 1)
        switch (width, height) {
        case let (width?, height?):
            return normalizedDimensions(width: width, height: height, naturalWidth: naturalWidth, naturalHeight: naturalHeight)
        case let (width?, nil):
            let resolvedHeight = CGFloat(width) * naturalHeight / naturalWidth
            return BlockInputImageDimensions(width: width, height: Int(resolvedHeight.rounded()))
        case let (nil, height?):
            let resolvedWidth = CGFloat(height) * naturalWidth / naturalHeight
            return BlockInputImageDimensions(width: Int(resolvedWidth.rounded()), height: height)
        case (nil, nil):
            return naturalDimensions
        }
    }

    private func normalizedDimensions(
        width: Int,
        height: Int,
        naturalWidth: CGFloat,
        naturalHeight: CGFloat
    ) -> BlockInputImageDimensions {
        let resolvedHeight = Int((CGFloat(width) * naturalHeight / naturalWidth).rounded())
        let resolvedWidth = Int((CGFloat(height) * naturalWidth / naturalHeight).rounded())
        if resolvedHeight == height || resolvedWidth == width {
            return BlockInputImageDimensions(width: width, height: height)
        }
        // Raw Markdown edits cannot tell which attribute changed. Treat the larger explicit dimension as intentional
        // and repair the other side so the rendered image and subsequent resize gestures use the natural aspect ratio.
        if width >= height {
            return BlockInputImageDimensions(width: width, height: max(resolvedHeight, 1))
        }
        return BlockInputImageDimensions(width: max(resolvedWidth, 1), height: height)
    }
}
