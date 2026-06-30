import AppKit
import CryptoKit

/// Value-type context threaded into a block item carrying the renderer registry and a lookup for
/// already-resolved render dimensions (used for synchronous height measurement on reuse).
struct BlockInputContentRenderingContext {
    var renderers: BlockInputBlockContentRendererRegistry
    var pixelScale: CGFloat
    var baseURL: URL?
    /// Whether the host configured a diagram editor (`interactiveBlockContentProvider`), so the surface shows ✏️.
    var isBlockContentEditingAvailable: Bool
    private var resolvedDimensionsLookup: @MainActor (BlockInputBlockID) -> BlockInputImageDimensions?

    init(
        renderers: BlockInputBlockContentRendererRegistry = BlockInputBlockContentRendererRegistry(),
        pixelScale: CGFloat = 2,
        baseURL: URL? = nil,
        isBlockContentEditingAvailable: Bool = false,
        resolvedDimensionsLookup: @escaping @MainActor (BlockInputBlockID) -> BlockInputImageDimensions? = { _ in nil }
    ) {
        self.renderers = renderers
        self.pixelScale = pixelScale
        self.baseURL = baseURL
        self.isBlockContentEditingAvailable = isBlockContentEditingAvailable
        self.resolvedDimensionsLookup = resolvedDimensionsLookup
    }

    @MainActor
    func resolvedDimensions(for blockID: BlockInputBlockID) -> BlockInputImageDimensions? {
        resolvedDimensionsLookup(blockID)
    }
}

extension BlockInputBlockItem {
    func configureRenderedContentIfNeeded(for block: BlockInputBlock) {
        guard let identifier = block.renderedContentIdentifier,
              let renderer = blockContentRenderingContext.renderers.renderer(for: identifier) else {
            cancelRenderedContent()
            renderedContentView.resetForReuse()
            return
        }
        renderedContentView.isEditable = isEditable
        renderedContentView.disabledCursor = disabledCursor
        renderedContentView.setAccessibilityLabel(identifier)
        renderedContentView.onExpand = { [weak self] in
            guard let self, let image = self.renderedContentView.renderedImage else {
                return
            }
            let expansion = BlockInputRenderedContentExpansion(
                contentIdentifier: identifier,
                source: block.text,
                image: BlockInputSendableImage(image)
            )
            self.delegate?.blockItem(self, blockID: block.id, didRequestExpandRenderedContent: expansion)
        }
        renderedContentView.isEditAvailable = blockContentRenderingContext.isBlockContentEditingAvailable
        renderedContentView.onEdit = { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.blockItem(self, blockID: block.id, didRequestEditBlockContent: identifier)
        }
        renderedContentView.onFixWithAI = { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.blockItem(self, blockID: block.id, didRequestFixBlockContent: identifier)
        }
        let cacheKey = Self.renderedContentCacheKey(identifier: identifier, source: block.text)
        if renderedContentView.reuseRenderedImage(cacheKey: cacheKey, style: style) {
            cancelRenderedContent()
            return
        }
        if renderedContentCacheKey == cacheKey, renderedContentTask != nil {
            return
        }
        cancelRenderedContent()
        renderedContentView.configurePlaceholder(style: style)
        startRenderedContent(renderer: renderer, identifier: identifier, source: block.text, cacheKey: cacheKey, blockID: block.id)
    }

    func cancelRenderedContent() {
        renderedContentTask?.cancel()
        renderedContentTask = nil
        renderedContentCacheKey = nil
    }

    /// Clears the cached render key so the next configuration re-renders even if the block text is unchanged.
    func invalidateRenderedContentCache() {
        cancelRenderedContent()
    }

    private func startRenderedContent(
        renderer: any BlockInputBlockContentRendering,
        identifier: String,
        source: String,
        cacheKey: String,
        blockID: BlockInputBlockID
    ) {
        let request = BlockInputBlockContentRequest(
            contentIdentifier: identifier,
            source: source,
            targetWidth: max(renderedContentTargetWidth, 120),
            pixelScale: blockContentRenderingContext.pixelScale,
            cacheKey: cacheKey,
            baseURL: blockContentRenderingContext.baseURL
        )
        renderedContentCacheKey = cacheKey
        renderedContentTask = Task { [weak self] in
            do {
                let content = try await renderer.render(request)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.finishRenderedContent(content, request: request, blockID: blockID)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                await MainActor.run {
                    self?.finishRenderedContentFailure(blockID: blockID, cacheKey: cacheKey, message: message)
                }
            }
        }
    }

    private func finishRenderedContent(
        _ content: BlockInputRenderedContent,
        request: BlockInputBlockContentRequest,
        blockID: BlockInputBlockID
    ) {
        guard renderedBlock?.id == blockID,
              renderedContentCacheKey == request.cacheKey else {
            return
        }
        renderedContentTask = nil
        renderedContentCacheKey = nil
        switch content {
        case let .image(rendered):
            applyRenderedImage(rendered, request: request, blockID: blockID)
        case let .view(dimensions, factory):
            applyHostedView(factory(), dimensions: dimensions, request: request, blockID: blockID)
        }
    }

    private func applyHostedView(
        _ hostedView: NSView,
        dimensions: BlockInputImageDimensions,
        request: BlockInputBlockContentRequest,
        blockID: BlockInputBlockID
    ) {
        renderedContentView.configureHostedView(hostedView, cacheKey: request.cacheKey, style: style)
        delegate?.blockItem(self, blockID: blockID, didResolveRenderedContentDimensions: dimensions)
    }

    private func applyRenderedImage(
        _ rendered: BlockInputRenderedImage,
        request: BlockInputBlockContentRequest,
        blockID: BlockInputBlockID
    ) {
        guard let nsImage = NSImage(data: rendered.data) else {
            renderedContentView.configureFailure(
                style: style,
                source: renderedBlock?.text ?? "",
                errorMessage: "Rendered image could not be decoded."
            )
            return
        }
        // The PNG bitmap is oversampled for Retina crispness; pin the NSImage's point size to the logical
        // dimensions so it renders at the correct on-screen size (and stays crisp) rather than 1pt-per-pixel.
        nsImage.size = NSSize(width: rendered.dimensions.width, height: rendered.dimensions.height)
        renderedContentView.configureRenderedImage(nsImage, cacheKey: request.cacheKey, style: style)
        delegate?.blockItem(self, blockID: blockID, didResolveRenderedContentDimensions: rendered.dimensions)
    }

    private func finishRenderedContentFailure(blockID: BlockInputBlockID, cacheKey: String, message: String?) {
        guard renderedBlock?.id == blockID,
              renderedContentCacheKey == cacheKey else {
            return
        }
        renderedContentTask = nil
        renderedContentCacheKey = nil
        renderedContentView.configureFailure(style: style, source: renderedBlock?.text ?? "", errorMessage: message)
        // Drop any stale resolved size and re-measure so the failure surface gets a sane height instead of
        // keeping a previously-resolved (now wrong) diagram height.
        delegate?.blockItemDidFailToRenderContent(self, blockID: blockID)
    }

    private var renderedContentTargetWidth: CGFloat {
        let itemWidth = view.bounds.width > 0 ? view.bounds.width : 0
        guard let renderedBlock else {
            return itemWidth
        }
        return Self.measuredTextWidth(
            for: itemWidth,
            block: renderedBlock,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        )
    }

    static func renderedContentCacheKey(identifier: String, source: String) -> String {
        let digest = SHA256.hash(data: Data(source.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(identifier)|\(hash)"
    }
}
