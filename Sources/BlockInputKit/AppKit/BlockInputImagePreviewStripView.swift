import AppKit
import ImageIO

struct BlockInputImagePreviewOccurrence: Equatable {
    var blockID: BlockInputBlockID
    var sourceRange: NSRange
    var sourceText: String
    var image: BlockInputImage
}

final class BlockInputImagePreviewStripView: NSView {
    var onOpen: ((BlockInputImagePreviewOccurrence) -> Void)?
    var onRemove: ((BlockInputImagePreviewOccurrence) -> Void)?

    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private var tileViews: [BlockInputImagePreviewTileView] = []
    private var items: [BlockInputImagePreviewOccurrence] = []
    private var style = BlockInputImagePreviewStripStyle()
    private var imageLoadingContext = BlockInputImageBlockLoadingContext()
    private var imageLoadingSignature = BlockInputImagePreviewLoadingSignature(context: BlockInputImageBlockLoadingContext())

    var isEmpty: Bool {
        items.isEmpty
    }

    var itemCountForTesting: Int {
        items.count
    }

    var firstRemoveButtonImageSizeForTesting: NSSize? {
        tileViews.first?.removeButtonImageSizeForTesting
    }

    var firstLoadedImagePixelSizeForTesting: NSSize? {
        tileViews.first?.loadedImagePixelSizeForTesting
    }

    var hasHorizontalScrollerForTesting: Bool {
        scrollView.hasHorizontalScroller
    }

    var scrollViewDrawsBackgroundForTesting: Bool {
        scrollView.drawsBackground
    }

    var clipViewDrawsBackgroundForTesting: Bool {
        scrollView.contentView.drawsBackground
    }

    var clipViewBackgroundColorForTesting: NSColor {
        scrollView.contentView.backgroundColor
    }

    func openFirstTileForTesting() {
        tileViews.first?.performPrimaryAction()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layout() {
        super.layout()
        layoutTiles()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
        tileViews.forEach { $0.applyAppearance() }
    }

    func configureStyle(_ style: BlockInputImagePreviewStripStyle) {
        let reloadsImages = self.style.thumbnailSize != style.thumbnailSize
        self.style = style
        applyAppearance()
        tileViews.forEach { $0.configureStyle(style, reloadsImage: reloadsImages) }
        needsLayout = true
    }

    func configureImageLoading(_ context: BlockInputImageBlockLoadingContext) {
        let signature = BlockInputImagePreviewLoadingSignature(context: context)
        let shouldReload = signature != imageLoadingSignature
        imageLoadingContext = context
        imageLoadingSignature = signature
        tileViews.forEach { $0.configureImageLoading(context, reloadsImage: shouldReload) }
    }

    func configureItems(_ items: [BlockInputImagePreviewOccurrence]) {
        guard self.items != items else {
            return
        }
        self.items = items
        rebuildTiles()
    }

    private func setup() {
        wantsLayer = true
        isHidden = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = contentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyAppearance()
    }

    private func applyAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = style.backgroundColor?.cgColor
        }
    }

    private func rebuildTiles() {
        tileViews.forEach { $0.removeFromSuperview() }
        tileViews = items.map { item in
            let tile = BlockInputImagePreviewTileView()
            tile.configure(item: item, style: style, imageLoadingContext: imageLoadingContext)
            tile.onOpen = { [weak self] occurrence in
                self?.onOpen?(occurrence)
            }
            tile.onRemove = { [weak self] occurrence in
                self?.onRemove?(occurrence)
            }
            contentView.addSubview(tile)
            return tile
        }
        needsLayout = true
    }

    private func layoutTiles() {
        let insets = style.contentInsets
        var tileX = insets.left
        let tileSize = style.thumbnailSize
        let tileY = max(insets.top, (bounds.height - tileSize.height) / 2)
        for tile in tileViews {
            tile.frame = NSRect(origin: NSPoint(x: tileX, y: tileY), size: tileSize)
            tileX += tileSize.width + style.interItemSpacing
        }
        let contentWidth = max(tileX - style.interItemSpacing + insets.right, bounds.width)
        contentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: bounds.height)
    }
}

private final class BlockInputImagePreviewTileView: NSView {
    var onOpen: ((BlockInputImagePreviewOccurrence) -> Void)?
    var onRemove: ((BlockInputImagePreviewOccurrence) -> Void)?

    private let imageView = NSImageView()
    private let removeButton = NSButton()
    private var item: BlockInputImagePreviewOccurrence?
    private var style = BlockInputImagePreviewStripStyle()
    private var imageLoadingContext = BlockInputImageBlockLoadingContext()
    private var loadTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        loadTask?.cancel()
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        let buttonStyle = style.removeButton
        removeButton.isHidden = !buttonStyle.isVisible
        let size = buttonStyle.size
        removeButton.frame = NSRect(
            x: bounds.maxX - size.width - buttonStyle.edgeInset,
            y: bounds.maxY - size.height - buttonStyle.edgeInset,
            width: size.width,
            height: size.height
        )
        applyAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard item != nil else {
            super.mouseDown(with: event)
            return
        }
        performPrimaryAction()
    }

    override func accessibilityPerformPress() -> Bool {
        guard item != nil else {
            return false
        }
        performPrimaryAction()
        return true
    }

    func configure(
        item: BlockInputImagePreviewOccurrence,
        style: BlockInputImagePreviewStripStyle,
        imageLoadingContext: BlockInputImageBlockLoadingContext
    ) {
        self.item = item
        self.style = style
        self.imageLoadingContext = imageLoadingContext
        configureStyle(style)
        configureImageLoading(imageLoadingContext)
        let accessibilityName = item.image.altText.isEmpty ? item.image.source : item.image.altText
        setAccessibilityLabel("Open image \(accessibilityName)")
        startLoad()
    }

    func performPrimaryAction() {
        guard let item else {
            return
        }
        onOpen?(item)
    }

    func configureStyle(_ style: BlockInputImagePreviewStripStyle, reloadsImage: Bool = false) {
        self.style = style
        needsLayout = true
        applyAppearance()
        if reloadsImage {
            startLoad()
        }
    }

    func configureImageLoading(_ context: BlockInputImageBlockLoadingContext) {
        configureImageLoading(context, reloadsImage: false)
    }

    func configureImageLoading(_ context: BlockInputImageBlockLoadingContext, reloadsImage: Bool) {
        imageLoadingContext = context
        if reloadsImage {
            startLoad()
        }
    }

    func applyAppearance() {
        layer?.cornerRadius = style.cornerRadius
        layer?.borderWidth = style.borderWidth
        layer?.borderColor = style.borderColor?.cgColor
        imageView.layer?.cornerRadius = style.cornerRadius
        removeButton.contentTintColor = style.removeButton.symbolColor
        removeButton.layer?.backgroundColor = style.removeButton.backgroundColor.cgColor
        removeButton.layer?.borderColor = style.removeButton.borderColor?.cgColor
        removeButton.layer?.borderWidth = style.removeButton.borderWidth
        removeButton.layer?.cornerRadius = style.removeButton.cornerRadius
        removeButton.layer?.shadowColor = style.removeButton.shadowColor?.cgColor
        removeButton.layer?.shadowOpacity = style.removeButton.shadowColor == nil ? 0 : style.removeButton.shadowOpacity
        removeButton.layer?.shadowRadius = style.removeButton.shadowRadius
        removeButton.layer?.shadowOffset = style.removeButton.shadowOffset
        applyRemoveButtonSymbolStyle()
    }

    private func setup() {
        wantsLayer = true
        setAccessibilityRole(.button)
        imageView.wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.layer?.masksToBounds = true
        addSubview(imageView)

        removeButton.isBordered = false
        removeButton.setButtonType(.momentaryChange)
        removeButton.target = self
        removeButton.action = #selector(removeButtonClicked)
        removeButton.imagePosition = .imageOnly
        removeButton.wantsLayer = true
        removeButton.setAccessibilityLabel("Remove image")
        applyRemoveButtonSymbolStyle()
        addSubview(removeButton)
    }

    private func applyRemoveButtonSymbolStyle() {
        let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove image")
        if let pointSize = style.removeButton.symbolPointSize {
            image?.size = NSSize(width: pointSize, height: pointSize)
        }
        removeButton.image = image
    }

    private func startLoad() {
        loadTask?.cancel()
        imageView.image = nil
        guard let item,
              let resolvedURL = item.image.resolvedURL(relativeTo: imageLoadingContext.baseURL),
              allowsLoading(resolvedURL) else {
            return
        }
        let request = BlockInputImageLoadRequest(
            image: item.image,
            resolvedURL: resolvedURL,
            cacheKey: item.image.cacheKey(
                resolvedURL: resolvedURL,
                loaderVersion: "preview-strip-v1",
                maximumPixelDimension: imageLoadingContext.maximumPixelDimension
            ),
            maxSourceBytes: imageLoadingContext.maximumSourceBytes,
            maxPixelDimension: imageLoadingContext.maximumPixelDimension,
            diskCache: imageLoadingContext.diskCache
        )
        let loader = imageLoadingContext.loader
        let displayScale = thumbnailDisplayScale()
        let maxThumbnailPixelDimension = maxThumbnailPixelDimension(displayScale: displayScale)
        loadTask = Task { [weak self] in
            do {
                let loaded = try await loader.loadImage(request)
                guard !Task.isCancelled,
                      let image = Self.thumbnailImage(
                          from: loaded.data,
                          maxPixelDimension: maxThumbnailPixelDimension,
                          displayScale: displayScale
                      ) else {
                    return
                }
                await MainActor.run {
                    self?.imageView.image = image
                }
            } catch {
            }
        }
    }

    private func allowsLoading(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return true
        }
        return imageLoadingContext.allowsRemoteLoading
    }

    private func thumbnailDisplayScale() -> CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func maxThumbnailPixelDimension(displayScale: CGFloat) -> Int {
        let largestPointDimension = max(style.thumbnailSize.width, style.thumbnailSize.height)
        return max(1, Int(ceil(largestPointDimension * displayScale)))
    }

    private static func thumbnailImage(
        from data: Data,
        maxPixelDimension: Int,
        displayScale: CGFloat
    ) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return NSImage(data: data)
        }
        let scale = max(1, displayScale)
        let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
    }

    @objc
    private func removeButtonClicked() {
        guard let item else {
            return
        }
        onRemove?(item)
    }

    var removeButtonImageSizeForTesting: NSSize? {
        removeButton.image?.size
    }

    var loadedImagePixelSizeForTesting: NSSize? {
        guard let image = imageView.image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return NSSize(width: cgImage.width, height: cgImage.height)
    }
}

private struct BlockInputImagePreviewLoadingSignature: Equatable {
    var loaderType: ObjectIdentifier
    var diskCacheType: ObjectIdentifier?
    var baseURL: URL?
    var allowsRemoteLoading: Bool
    var maximumSourceBytes: Int
    var maximumPixelDimension: Int

    init(context: BlockInputImageBlockLoadingContext) {
        loaderType = ObjectIdentifier(type(of: context.loader))
        diskCacheType = context.diskCache.map { ObjectIdentifier(type(of: $0)) }
        baseURL = context.baseURL
        allowsRemoteLoading = context.allowsRemoteLoading
        maximumSourceBytes = context.maximumSourceBytes
        maximumPixelDimension = context.maximumPixelDimension
    }
}
