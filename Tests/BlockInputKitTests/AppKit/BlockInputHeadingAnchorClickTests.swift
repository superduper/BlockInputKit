import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputHeadingAnchorClickTests: XCTestCase {
    private func doc() -> BlockInputDocument {
        var blocks = [BlockInputBlock(id: "intro", kind: .heading(level: 1), text: "Intro")]
        blocks += (0..<30).map { BlockInputBlock(id: BlockInputBlockID(rawValue: "p\($0)"), text: "para \($0)") }
        blocks.append(BlockInputBlock(id: "target", kind: .heading(level: 2), text: "Foo Bar"))
        return BlockInputDocument(blocks: blocks)
    }

    func testAnchorClickScrollsToHeadingWithNoHostHandler() throws {
        let (view, _) = makeMountedBlockInputView(document: doc())  // no inlineLinkClickHandler set
        // Simulate the editor-default branch resolving "#foo-bar".
        let scrolled = view.handleHeadingAnchorClickForTesting(destination: try XCTUnwrap(URL(string: "#foo-bar")))
        XCTAssertTrue(scrolled)
    }

    func testUnknownAnchorDoesNotScroll() throws {
        let (view, _) = makeMountedBlockInputView(document: doc())
        XCTAssertFalse(view.handleHeadingAnchorClickForTesting(destination: try XCTUnwrap(URL(string: "#nope"))))
    }

    func testDisabledFlagSkipsAnchor() throws {
        var config = BlockInputConfiguration(document: doc())
        config.headingAnchorsEnabled = false
        let (view, _) = makeMountedBlockInputView(configuration: config)
        XCTAssertFalse(view.handleHeadingAnchorClickForTesting(destination: try XCTUnwrap(URL(string: "#foo-bar"))))
    }

    func testEditorDefaultFallsThroughToAnchorJump() throws {
        // Proves that when a host handler returns .editorDefault the editor still performs the anchor
        // jump (the "super()" path). Uses `applyEditorDefaultActionForTesting` to reach the production
        // routing branch without synthesising an NSEvent (see seam comment for rationale).
        let (view, _) = makeMountedBlockInputView(document: doc())
        let url = try XCTUnwrap(URL(string: "#foo-bar"))
        let scrolled = view.applyEditorDefaultActionForTesting(
            action: .editorDefault,
            kind: .plainLink,
            destination: url
        )
        XCTAssertTrue(scrolled)
    }

    // MARK: - Interaction parity

    /// Verifies that when `headingAnchorsEnabled` is true the TEXT VIEW's own hit/hover path
    /// (`linkRangesForCurrentText`) treats a `[label](#slug)` link as a link-range — i.e. the
    /// pointer-interaction path (hand cursor, hover popover, click routing) sees the anchor link.
    /// This covers the `allowsAnchorLinks` gap in `inlineMarkdownRangesForCurrentText()`.
    func testAnchorLinkAppearsInTextViewLinkRangesWhenEnabled() throws {
        var config = BlockInputConfiguration(document: anchorParityDoc())
        config.headingAnchorsEnabled = true
        let (view, _) = makeMountedBlockInputView(configuration: config)
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertFalse(
            textView.linkRangesForCurrentText().isEmpty,
            "Expected [go](#bar) to appear as a link range in the text view's hit/hover path when headingAnchorsEnabled"
        )
    }

    /// Control: with `headingAnchorsEnabled` false and no `inlineLinkClickHandler`, the anchor link
    /// must NOT appear as a link range (it renders as plain text).
    func testAnchorLinkAbsentFromTextViewLinkRangesWhenDisabled() throws {
        var config = BlockInputConfiguration(document: anchorParityDoc())
        config.headingAnchorsEnabled = false
        // no inlineLinkClickHandler set → allowsAnchorLinks == false
        let (view, _) = makeMountedBlockInputView(configuration: config)
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertTrue(
            textView.linkRangesForCurrentText().isEmpty,
            "Expected [go](#bar) NOT to appear as a link range when headingAnchorsEnabled is false"
        )
    }

    // MARK: - Helpers

    /// A minimal document with a paragraph containing an anchor link followed by a heading target.
    private func anchorParityDoc() -> BlockInputDocument {
        BlockInputDocument(blocks: [
            BlockInputBlock(id: "para", text: "[go](#bar)"),
            BlockInputBlock(id: "heading", kind: .heading(level: 1), text: "Bar")
        ])
    }
}
