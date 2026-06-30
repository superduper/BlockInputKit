import AppKit
import Foundation

/// Request passed to a host-supplied block content renderer.
///
/// A renderer turns a block's `source` into presentable content — for example a
/// fenced ` ```mermaid ` body into a diagram image. The request is content-source
/// agnostic so future attachment renderers (PDF, video) can reuse the same seam.
public struct BlockInputBlockContentRequest: Sendable {
    /// Resolver key identifying which renderer should handle this block,
    /// e.g. `"code.mermaid"` for a Mermaid fenced code block.
    public var contentIdentifier: String
    /// Block payload to render. For code blocks this is the fenced body text.
    public var source: String
    /// Column width the rendered content should scale to fit.
    public var targetWidth: CGFloat
    /// Backing-store scale used to rasterize image-mode content.
    public var pixelScale: CGFloat
    /// Host-stable identity for caching and staleness checks (typically a source hash).
    public var cacheKey: String
    /// Optional base URL for resolving relative references.
    public var baseURL: URL?

    /// Creates a block content render request.
    public init(
        contentIdentifier: String,
        source: String,
        targetWidth: CGFloat,
        pixelScale: CGFloat,
        cacheKey: String,
        baseURL: URL? = nil
    ) {
        self.contentIdentifier = contentIdentifier
        self.source = source
        self.targetWidth = targetWidth
        self.pixelScale = pixelScale
        self.cacheKey = cacheKey
        self.baseURL = baseURL
    }
}

/// Rasterized content returned by an image-mode renderer.
public struct BlockInputRenderedImage: Sendable {
    /// Encoded image bytes (e.g. PNG).
    public var data: Data
    /// Natural pixel dimensions used to derive the block's aspect ratio and height.
    public var dimensions: BlockInputImageDimensions

    /// Creates rendered image bytes with resolved dimensions.
    public init(data: Data, dimensions: BlockInputImageDimensions) {
        self.data = data
        self.dimensions = dimensions
    }
}

/// Describes a request to zoom a rendered-content block. Carries the already-rendered image (shown
/// instantly) plus the source needed for a host to build a live interactive view (e.g. a Mermaid WebView).
public struct BlockInputRenderedContentExpansion: Sendable {
    /// Resolver key for the content (e.g. `"code.mermaid"`).
    public var contentIdentifier: String
    /// The block's source text (e.g. the fenced diagram body).
    public var source: String
    /// The currently rendered image, shown immediately while any live view loads.
    public var image: BlockInputSendableImage

    /// Creates an expansion request.
    public init(contentIdentifier: String, source: String, image: BlockInputSendableImage) {
        self.contentIdentifier = contentIdentifier
        self.source = source
        self.image = image
    }
}

/// Context passed to ``BlockInputConfiguration/renderedContentZoomProvider`` to build a live zoom view.
public struct BlockInputRenderedContentZoomContext: Sendable {
    /// Resolver key for the content (e.g. `"code.mermaid"`).
    public var contentIdentifier: String
    /// The block's source text to render live.
    public var source: String

    /// Creates a zoom context.
    public init(contentIdentifier: String, source: String) {
        self.contentIdentifier = contentIdentifier
        self.source = source
    }
}

/// A main-actor `NSImage` wrapper that is safe to carry across `Sendable` boundaries.
public struct BlockInputSendableImage: @unchecked Sendable {
    /// The wrapped image. NSImage is effectively immutable here (rendered output), so cross-actor use is safe.
    public let image: NSImage

    /// Wraps a rendered image.
    public init(_ image: NSImage) {
        self.image = image
    }
}

/// Content produced by a block content renderer.
///
/// Image-mode (`image`) carries `Sendable` bytes and is used by snapshot renderers
/// such as Mermaid/KaTeX/HTML. View-mode (`view`) vends a live `NSView` and is
/// reserved for future interactive attachment renderers (PDF, video); its factory
/// is `@MainActor` because `NSView` is not `Sendable`.
public enum BlockInputRenderedContent: Sendable {
    /// Static rasterized content (e.g. a snapshot diagram).
    case image(BlockInputRenderedImage)
    /// Live interactive content vended on the main actor, with intrinsic dimensions that drive the
    /// block's scale-to-fit height (e.g. a vector SVG view, or a future PDF/video view).
    case view(dimensions: BlockInputImageDimensions, factory: @MainActor @Sendable () -> NSView)
}

/// Host-customizable block content rendering behavior.
///
/// A renderer claims the content identifiers it can handle via `canRender(contentIdentifier:)`
/// and produces content asynchronously. The seam mirrors ``BlockInputImageLoading`` but is
/// generalized over both the content source and the output mode.
public protocol BlockInputBlockContentRendering: Sendable {
    /// Renders content for a block request. Image-mode renderers complete off-main;
    /// view-mode renderers return a main-actor view factory.
    func render(_ request: BlockInputBlockContentRequest) async throws -> BlockInputRenderedContent
    /// Cheap, pure check for whether this renderer handles a content identifier.
    func canRender(contentIdentifier: String) -> Bool
}

/// Ordered set of block content renderers with first-match resolution.
public struct BlockInputBlockContentRendererRegistry: Sendable {
    /// Renderers consulted in order; the first whose `canRender` returns true wins.
    public var renderers: [any BlockInputBlockContentRendering]

    /// Creates a registry from an ordered list of renderers.
    public init(renderers: [any BlockInputBlockContentRendering] = []) {
        self.renderers = renderers
    }

    /// Returns the first renderer that handles the given content identifier, if any.
    public func renderer(for contentIdentifier: String) -> (any BlockInputBlockContentRendering)? {
        renderers.first { $0.canRender(contentIdentifier: contentIdentifier) }
    }

    /// Whether any registered renderer handles the given content identifier.
    public func canRender(contentIdentifier: String) -> Bool {
        renderer(for: contentIdentifier) != nil
    }
}

/// Default renderer used when no host renderer is registered. It never claims content.
public struct BlockInputUnavailableContentRenderer: BlockInputBlockContentRendering {
    /// Creates the unavailable renderer.
    public init() {}

    public func canRender(contentIdentifier: String) -> Bool { false }

    public func render(_ request: BlockInputBlockContentRequest) async throws -> BlockInputRenderedContent {
        throw BlockInputBlockContentRenderingError.noRendererRegistered
    }
}

/// Error thrown by block content rendering.
public enum BlockInputBlockContentRenderingError: Error, Equatable, Sendable, LocalizedError {
    /// No registered renderer claimed the requested content identifier.
    case noRendererRegistered
    /// The renderer failed to produce content for the request (non-diagnostic: blank snapshot, bad dimensions).
    case renderFailed
    /// The renderer failed and returned a diagnostic message from the underlying engine (e.g. a Mermaid
    /// parse error). The message is the raw engine string, verbatim — callers must not truncate or wrap it.
    case renderFailedWithMessage(String)

    public var errorDescription: String? {
        switch self {
        case .noRendererRegistered:
            return "No renderer is registered for this content."
        case .renderFailed:
            return "The renderer could not produce an image for this content."
        case .renderFailedWithMessage(let message):
            return message
        }
    }
}
