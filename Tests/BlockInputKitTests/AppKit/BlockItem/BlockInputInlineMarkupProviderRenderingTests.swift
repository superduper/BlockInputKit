import AppKit
import XCTest
@testable import BlockInputKit

/// Proves the generic custom-inline-markup seam end to end without any wikilink involvement: a trivial provider matching
/// `@@x@@` (visible `x`, hidden `@@` pairs) reaches the scanner from configuration, its visible content is styled
/// (foreground + single underline) via the generic `.customMarkup` branch, and its `@@` delimiters are hidden via the
/// shared `.blockInputHiddenDelimiter` null-glyph mechanism.
@MainActor
final class BlockInputInlineMarkupRenderTests: XCTestCase {
    func testRegisteredProviderStylesContentAndHidesDelimitersOnMountedView() throws {
        let provider = AtAtMarkupProvider()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: "See @@Note@@ now")]),
            inlineMarkupProviders: [provider]
        ))
        let textView = try textView(in: mounted.view)
        let storage = try XCTUnwrap(textView.textStorage)
        let text = "See @@Note@@ now"

        // The visible `Note` is styled with the descriptor's foreground + single underline.
        let contentLocation = (text as NSString).range(of: "Note").location
        let attributes = storage.attributes(at: contentLocation, effectiveRange: nil)
        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, AtAtMarkupProvider.foreground)
        XCTAssertEqual(attributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)

        // Both `@@` runs are hidden via the shared null-glyph delimiter mechanism.
        XCTAssertEqual(hiddenRanges(in: storage).map { (text as NSString).substring(with: $0) }, ["@@", "@@"])
    }

    func testProviderSpanRendersWithoutWikilinkInvolvement() throws {
        let provider = AtAtMarkupProvider()
        let storage = NSTextStorage(string: "See @@Note@@ now")
        BlockInputBlockItem.applyInlineMarkdownAttributes(
            for: BlockInputBlock(id: "b", kind: .paragraph, text: "See @@Note@@ now"),
            textStorage: storage,
            style: .default,
            inlineMarkupProviders: [provider]
        )
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: "See @@Note@@ now",
            inlineMarkupProviders: [provider]
        )
        let customMarkup = try XCTUnwrap(ranges.first { range in
            if case .customMarkup = range.style { return true }
            return false
        })
        XCTAssertEqual((("See @@Note@@ now") as NSString).substring(with: customMarkup.contentRange), "Note")
        // Exactly one custom markup span (the `@@` provider's); no built-in grammar claims any of this text.
        XCTAssertEqual(ranges.filter { if case .customMarkup = $0.style { return true } else { return false } }.count, 1)
    }

    // MARK: - Helpers

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func hiddenRanges(in storage: NSTextStorage) -> [NSRange] {
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.blockInputHiddenDelimiter, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value as? Bool == true {
                ranges.append(range)
            }
        }
        return ranges
    }
}

/// Trivial test provider: matches `@@<content>@@` with the `@@` pairs hidden and `<content>` visible.
private struct AtAtMarkupProvider: BlockInputInlineMarkupProvider {
    static let foreground = NSColor.systemPink
    let identifier = "atat"

    func spans(in text: String, excluding excludedRanges: [NSRange]) -> [BlockInputInlineMarkupSpan] {
        let nsText = text as NSString
        var spans: [BlockInputInlineMarkupSpan] = []
        var searchLocation = 0
        while searchLocation < nsText.length {
            let openRange = nsText.range(
                of: "@@",
                options: [],
                range: NSRange(location: searchLocation, length: nsText.length - searchLocation)
            )
            guard openRange.location != NSNotFound else {
                break
            }
            let afterOpen = NSMaxRange(openRange)
            let closeRange = nsText.range(
                of: "@@",
                options: [],
                range: NSRange(location: afterOpen, length: nsText.length - afterOpen)
            )
            guard closeRange.location != NSNotFound, closeRange.location > afterOpen else {
                searchLocation = afterOpen
                continue
            }
            let contentRange = NSRange(location: afterOpen, length: closeRange.location - afterOpen)
            let fullRange = NSRange(location: openRange.location, length: NSMaxRange(closeRange) - openRange.location)
            spans.append(BlockInputInlineMarkupSpan(
                fullRange: fullRange,
                contentRange: contentRange,
                hiddenRanges: [openRange, closeRange],
                style: BlockInputInlineMarkupStyle(foregroundColor: AtAtMarkupProvider.foreground, underlines: true),
                payload: BlockInputInlineMarkupPayload(primary: nsText.substring(with: contentRange))
            ))
            searchLocation = NSMaxRange(closeRange)
        }
        return spans
    }
}
