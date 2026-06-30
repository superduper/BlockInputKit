import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputBlockItemImageInlineChipTests: XCTestCase {
    func testInlineMarkdownRendersImageFileLinksAsChipsWhenSelectionIsOutsideSource() throws {
        let text = "Open ![H05A0402](file:///tmp/H05A0402.jpg) today"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let contentOffset = contentLocation("H05A0402", in: text)
        let markerOffset = (text as NSString).range(of: "!").location
        let openingBracketOffset = (text as NSString).range(of: "[").location
        let destinationOffset = (text as NSString).range(of: "file:///tmp").location

        XCTAssertEqual(
            (textStorage.attribute(.link, at: contentOffset, effectiveRange: nil) as? URL)?.absoluteString,
            "file:///tmp/H05A0402.jpg"
        )
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: contentOffset, effectiveRange: nil))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentOffset, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertTrue(try font(at: contentOffset, in: textStorage).isFixedPitch)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: markerOffset, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: openingBracketOffset, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: destinationOffset, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(item.testingTextView?.string, text)
    }

    private func font(at location: Int, in textStorage: NSTextStorage) throws -> NSFont {
        try XCTUnwrap(textStorage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    }

    private func contentLocation(_ content: String, in text: String) -> Int {
        (text as NSString).range(of: content).location
    }
}
