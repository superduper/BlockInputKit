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
}
