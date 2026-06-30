import Foundation

extension BlockInputBlock {
    func copiedVisibleInlineLinkText(in range: NSRange, fileBaseURL: URL? = nil) -> String? {
        guard supportsInlineLinkCopy else {
            return nil
        }
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        let linkRanges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: inlineCodeRanges,
            fileBaseURL: fileBaseURL
        )
            .filter { $0.style == .link }
        guard linkRanges.contains(where: { $0.fullRange.intersectionLength(with: range) > 0 }) else {
            return nil
        }
        let source = text as NSString
        let selectedEnd = NSMaxRange(range)
        var copiedText = ""
        var cursor = range.location
        for linkRange in linkRanges where linkRange.fullRange.intersectionLength(with: range) > 0 {
            if cursor < linkRange.fullRange.location {
                let plainEnd = min(linkRange.fullRange.location, selectedEnd)
                copiedText += source.substring(with: NSRange(location: cursor, length: plainEnd - cursor))
                cursor = plainEnd
            }
            let selectedContentRange = NSIntersectionRange(range, linkRange.contentRange)
            if selectedContentRange.length > 0 {
                copiedText += copiedMarkdownLinkText(for: linkRange, selectedContentRange: selectedContentRange)
            }
            cursor = max(cursor, min(NSMaxRange(linkRange.fullRange), selectedEnd))
            guard cursor < selectedEnd else {
                break
            }
        }
        if cursor < selectedEnd {
            copiedText += source.substring(with: NSRange(location: cursor, length: selectedEnd - cursor))
        }
        return copiedText.isEmpty ? nil : copiedText
    }

    private func copiedMarkdownLinkText(
        for linkRange: BlockInputInlineMarkdownRange,
        selectedContentRange: NSRange
    ) -> String {
        let source = text as NSString
        if selectedContentRange == linkRange.contentRange {
            return source.substring(with: linkRange.fullRange)
        }
        let copiedLabel = source.substring(with: selectedContentRange).blockInputUnescapedLinkLabel
        let destination = linkRange.linkRawDestination ?? linkRange.linkDestination?.absoluteString ?? ""
        return BlockInputLinkURL.markdownLink(label: copiedLabel, destination: destination)
    }

    private var supportsInlineLinkCopy: Bool {
        switch kind {
        case .paragraph, .heading, .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return false
        }
    }
}
