import Foundation

extension BlockInputBlockItem {
    /// The source-string range of a file chip label's trailing extension (including the leading dot), or nil when there
    /// is none worth hiding.
    ///
    /// Operates on the SOURCE substring of `contentRange` (UTF-16, escaping intact) so the returned range is in source
    /// coordinates — not the unescaped label — and the render and height passes hide exactly the same characters. The
    /// dot must not be the first content character, and there must be at least one extension character after it.
    static func chipHiddenExtensionRange(in source: String, contentRange: NSRange) -> NSRange? {
        let nsSource = source as NSString
        guard contentRange.length > 0, NSMaxRange(contentRange) <= nsSource.length else {
            return nil
        }
        let content = nsSource.substring(with: contentRange) as NSString
        let dotRange = content.range(of: ".", options: .backwards)
        guard dotRange.location != NSNotFound,
              dotRange.location > 0,
              dotRange.location < content.length - 1 else {
            return nil
        }
        return NSRange(
            location: contentRange.location + dotRange.location,
            length: contentRange.length - dotRange.location
        )
    }
}
