import Foundation

/// Image content rendered as a standalone block.
public struct BlockInputImage: Equatable, Codable, Sendable {
    /// Original image source string from Markdown, HTML, insertion, or file drop.
    ///
    /// Relative sources are preserved here for Markdown export. Hosts can resolve
    /// them for loading with `BlockInputConfiguration.imageBaseURL`.
    public var source: String
    /// Alternative text used for Markdown/HTML export and accessibility.
    public var altText: String
    /// Persisted display width in points or pixels, when explicitly known.
    ///
    /// A `nil` value means the width is undefined in the document model.
    public var width: Int? {
        didSet {
            width = width.flatMap(Self.validDimension)
        }
    }
    /// Persisted display height in points or pixels, when explicitly known.
    ///
    /// A `nil` value means the height is undefined in the document model.
    public var height: Int? {
        didSet {
            height = height.flatMap(Self.validDimension)
        }
    }
    /// Preferred export style for this image when it has not been resized.
    public var sourceStyle: SourceStyle

    /// Creates an image block payload.
    public init(
        source: String,
        altText: String = "",
        width: Int? = nil,
        height: Int? = nil,
        sourceStyle: SourceStyle = .markdown
    ) {
        self.source = source
        self.altText = altText
        self.width = width.flatMap(Self.validDimension)
        self.height = height.flatMap(Self.validDimension)
        self.sourceStyle = sourceStyle
    }

    /// Syntax style to prefer when exporting an untouched image block.
    public enum SourceStyle: String, Codable, Sendable {
        /// Export as Markdown image syntax when no dimensions are persisted.
        case markdown
        /// Export as an HTML `<img>` tag.
        case html
    }

    private static func validDimension(_ value: Int) -> Int? {
        value > 0 ? value : nil
    }
}

public extension BlockInputImage {
    /// Resolves the image source against an optional base URL.
    func resolvedURL(relativeTo baseURL: URL?) -> URL? {
        if let absoluteURL = URL(string: source), absoluteURL.scheme != nil {
            return absoluteURL
        }
        if let baseURL {
            return URL(string: source, relativeTo: baseURL)?.absoluteURL
        }
        return URL(string: source)
    }

    /// Returns a stable cache key for a source and image loading policy.
    func cacheKey(
        resolvedURL: URL,
        loaderVersion: String = "default-v1",
        maximumPixelDimension: Int
    ) -> String {
        [
            loaderVersion,
            resolvedURL.absoluteString,
            String(maximumPixelDimension)
        ].joined(separator: "|")
    }
}
