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
}
