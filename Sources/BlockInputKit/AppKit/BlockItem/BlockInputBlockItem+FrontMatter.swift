import AppKit

/// Noninteractive separator rendered at the bottom of a frontmatter block.
final class BlockInputFrontMatterDividerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

extension BlockInputBlockItem {
    /// Applies lightweight key/value styling without parsing or mutating YAML.
    ///
    /// The source text stays delimiter-free and host-owned; this only makes
    /// top-level `key: value` lines easier to scan in the built-in editor.
    func applyFrontMatterKeyValueAttributes(for block: BlockInputBlock, textStorage: NSTextStorage) {
        guard block.kind == .frontMatter else {
            return
        }
        for line in Self.frontMatterLineRanges(in: textStorage.string) {
            guard line.range.length > 0,
                  !line.text.trimmingCharacters(in: .whitespaces).isEmpty,
                  !line.text.trimmingCharacters(in: .whitespaces).hasPrefix("#"),
                  line.text.first?.isWhitespace != true,
                  let colonOffset = (line.text as NSString).range(of: ":").nilIfNotFound?.location,
                  colonOffset > 0 else {
                continue
            }
            textStorage.addAttribute(
                .foregroundColor,
                value: readOnlyForegroundColor(.systemBlue, for: block.kind),
                range: NSRange(location: line.range.location, length: colonOffset)
            )
            textStorage.addAttribute(
                .foregroundColor,
                value: readOnlyForegroundColor(.secondaryLabelColor, for: block.kind),
                range: NSRange(location: line.range.location + colonOffset, length: 1)
            )
        }
    }

    /// Applies advisory frontmatter warnings after the normal text attributes.
    ///
    /// Reconfiguration resets the text storage first, so only the current
    /// invalid lines receive warning color and underline attributes.
    func applyFrontMatterValidationAttributes(for block: BlockInputBlock, textStorage: NSTextStorage) {
        guard block.kind == .frontMatter else {
            return
        }
        let issues = block.frontMatterValidationIssues
        guard !issues.isEmpty else {
            return
        }
        let lineRanges = Self.frontMatterLineRanges(in: textStorage.string)
        for issue in issues where lineRanges.indices.contains(issue.lineIndex) {
            let range = Self.frontMatterValidationWarningRange(for: lineRanges[issue.lineIndex])
            guard range.length > 0 else {
                continue
            }
            textStorage.addAttribute(
                .foregroundColor,
                value: readOnlyForegroundColor(.systemOrange, for: block.kind),
                range: range
            )
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    private static func frontMatterValidationWarningRange(for line: FrontMatterLineRange) -> NSRange {
        let textStorage = line.text as NSString
        guard line.range.length > 0,
              line.text.first?.isWhitespace != true,
              let colonOffset = textStorage.range(of: ":").nilIfNotFound?.location,
              colonOffset > 0 else {
            return line.range
        }
        let key = textStorage.substring(to: colonOffset).trimmingCharacters(in: .whitespaces)
        let keyLength = (key as NSString).length
        guard keyLength > 0 else {
            return line.range
        }
        // Keep delimiter styling stable: warnings on key/value-shaped lines
        // mark only the key name, never the colon delimiter.
        return NSRange(location: line.range.location, length: keyLength)
    }

    private static func frontMatterLineRanges(in text: String) -> [FrontMatterLineRange] {
        let textStorage = text as NSString
        guard textStorage.length > 0 else {
            return [FrontMatterLineRange(range: NSRange(location: 0, length: 0), text: "")]
        }
        var ranges: [FrontMatterLineRange] = []
        var offset = 0
        while offset < textStorage.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            textStorage.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: offset, length: 0)
            )
            let range = NSRange(location: lineStart, length: contentsEnd - lineStart)
            ranges.append(FrontMatterLineRange(range: range, text: textStorage.substring(with: range)))
            offset = lineEnd
        }
        if textStorage.character(at: textStorage.length - 1).isLineEnding {
            ranges.append(FrontMatterLineRange(range: NSRange(location: textStorage.length, length: 0), text: ""))
        }
        return ranges
    }

    private struct FrontMatterLineRange {
        var range: NSRange
        var text: String
    }
}

private extension NSRange {
    var nilIfNotFound: NSRange? {
        location == NSNotFound ? nil : self
    }
}
