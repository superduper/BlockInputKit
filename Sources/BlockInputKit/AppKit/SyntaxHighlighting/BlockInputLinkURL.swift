import AppKit

/// URL validation and escaping rules for inline Markdown links.
///
/// Keeping this policy centralized makes paste, context menus, rendering, and
/// the link editor agree on which destinations become actionable editor links.
enum BlockInputLinkURL {
    static let supportedSchemes: Set<String> = ["http", "https", "file"]

    /// Returns a URL only when the destination is non-empty, single-line, and uses a supported actionable scheme.
    static func supportedURL(from string: String, allowsCustomSchemes: Bool = false, fileBaseURL: URL? = nil) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else {
            return nil
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else {
            guard let fileBaseURL else {
                return nil
            }
            return URL(fileURLWithPath: trimmed, relativeTo: fileBaseURL).absoluteURL
        }
        guard allowsCustomSchemes || supportedSchemes.contains(scheme) else {
            return nil
        }
        switch scheme {
        case "http", "https":
            guard url.host?.isEmpty == false else {
                return nil
            }
        case "file":
            guard url.isFileURL, !url.path.isEmpty else {
                return nil
            }
        default:
            guard allowsCustomSchemes else {
                return nil
            }
        }
        return url
    }

    /// Extracts a supported URL from string, URL, and file-URL pasteboard representations.
    static func supportedURLString(from pasteboard: NSPasteboard = .general) -> String? {
        if let string = pasteboard.string(forType: .URL),
           supportedURL(from: string) != nil {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let string = pasteboard.string(forType: .fileURL),
           supportedURL(from: string) != nil {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let string = pasteboard.string(forType: .string),
           supportedURL(from: string) != nil {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let url = pasteboard.readObjects(forClasses: [NSURL.self])?
            .compactMap({ $0 as? URL })
            .first(where: { supportedURL(from: $0.absoluteString) != nil }) else {
            return nil
        }
        return url.absoluteString
    }

    static func markdownLink(label: String, destination: String) -> String {
        markdownLink(escapedLabel: escapedLabel(label), destination: destination)
    }

    /// Builds Markdown source from a label that was already escaped by the caller.
    static func markdownLink(escapedLabel: String, destination: String) -> String {
        "[\(escapedLabel)](\(escapedDestination(destination)))"
    }

    static func markdownDestination(from source: String, resolvedURL: URL) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: trimmed)?.scheme != nil else {
            return trimmed
        }
        return resolvedURL.absoluteString
    }

    /// Escapes label delimiters that would otherwise become nested link syntax.
    static func escapedLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    /// Escapes destination delimiters so literal parentheses survive the row-local link scanner.
    static func escapedDestination(_ destination: String) -> String {
        destination.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }
}

extension String {
    var blockInputUnescapedLinkLabel: String {
        replacingOccurrences(of: "\\[", with: "[")
            .replacingOccurrences(of: "\\]", with: "]")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    var blockInputUnescapedLinkDestination: String {
        replacingOccurrences(of: "\\(", with: "(")
            .replacingOccurrences(of: "\\)", with: ")")
            .replacingOccurrences(of: "\\<", with: "<")
            .replacingOccurrences(of: "\\>", with: ">")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
