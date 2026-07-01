import XCTest
@testable import BlockInputKit

final class BlockInputInlineAnchorLinkTests: XCTestCase {
    private func linkRanges(_ text: String, anchors: Bool) -> [BlockInputInlineMarkdownRange] {
        BlockInputInlineMarkdownParsing.linkRanges(
            in: text as NSString,
            excluding: BlockInputExcludedRangeLookup(textLength: (text as NSString).length, ranges: []),
            fileBaseURL: nil,
            allowsAnchorLinks: anchors
        )
    }

    func testAnchorLinkStyledWhenAllowed() {
        let ranges = linkRanges("[foo](#bar)", anchors: true)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges.first?.style, .link)
        XCTAssertEqual(ranges.first?.linkDestination?.fragment, "bar")
    }

    func testAnchorLinkNotStyledWhenDisallowed() {
        XCTAssertTrue(linkRanges("[foo](#bar)", anchors: false).isEmpty)
    }

    func testHttpLinkStillStyledRegardless() {
        XCTAssertEqual(linkRanges("[x](https://a.com)", anchors: false).first?.style, .link)
    }

    @MainActor
    func testMountedAnchorLinkClickScrollsToHeading() throws {
        let doc = BlockInputDocument(blocks: [
            BlockInputBlock(id: "p", kind: .paragraph, text: "[go](#bar)"),
            BlockInputBlock(id: "h", kind: .heading(level: 1), text: "Bar")
        ])
        var config = BlockInputConfiguration(document: doc)
        config.headingAnchorsEnabled = true
        let (view, _) = makeMountedBlockInputView(configuration: config)
        // When headingAnchorsEnabled is true the paragraph's [go](#bar) must resolve.
        XCTAssertTrue(view.handleHeadingAnchorClickForTesting(destination: try XCTUnwrap(URL(string: "#bar"))))
    }
}
