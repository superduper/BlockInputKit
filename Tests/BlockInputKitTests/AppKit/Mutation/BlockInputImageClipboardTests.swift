import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImageClipboardTests: XCTestCase {
    func testImageBlockCopyWithoutDimensionsUsesMarkdownImage() throws {
        let image = BlockInputImage(
            source: "https://example.com/image.png",
            altText: "bike",
            sourceStyle: .html
        )

        XCTAssertEqual(try copiedString(for: image), "![bike](https://example.com/image.png)")
    }

    func testImageBlockCopyWithWidthUsesHTMLImage() throws {
        let image = BlockInputImage(
            source: "https://example.com/image.png",
            altText: "bike",
            width: 320,
            sourceStyle: .markdown
        )

        XCTAssertEqual(try copiedString(for: image), #"<img src="https://example.com/image.png" alt="bike" width="320" />"#)
    }

    func testImageBlockCopyWithHeightUsesHTMLImage() throws {
        let image = BlockInputImage(
            source: "https://example.com/image.png",
            altText: "bike",
            height: 180,
            sourceStyle: .markdown
        )

        XCTAssertEqual(try copiedString(for: image), #"<img src="https://example.com/image.png" alt="bike" height="180" />"#)
    }

    func testImageBlockCopyWithWidthAndHeightUsesHTMLImage() throws {
        let image = BlockInputImage(
            source: "https://example.com/image.png",
            altText: "bike",
            width: 320,
            height: 180,
            sourceStyle: .markdown
        )

        XCTAssertEqual(
            try copiedString(for: image),
            #"<img src="https://example.com/image.png" alt="bike" width="320" height="180" />"#
        )
    }

    func testMixedSelectionContainingImageUsesClipboardImageRepresentation() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "before", text: "Before"),
            BlockInputBlock(
                id: imageID,
                kind: .image(BlockInputImage(
                    source: "https://example.com/image.png",
                    altText: "bike",
                    sourceStyle: .html
                ))
            ),
            BlockInputBlock(id: "after", text: "After")
        ])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(blockIDs: [imageID])), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        try withCleanPasteboard { pasteboard in
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))
            XCTAssertEqual(pasteboard.string(forType: .string), "![bike](https://example.com/image.png)")
        }
    }

    func testCutImageBlockUsesClipboardImageRepresentation() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(
                id: imageID,
                kind: .image(BlockInputImage(source: "https://example.com/image.png", altText: "bike", sourceStyle: .html))
            )
        ])
        mounted.view.applySelection(.blocks([imageID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        try withCleanPasteboard { pasteboard in
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandXEvent()))
            XCTAssertEqual(pasteboard.string(forType: .string), "![bike](https://example.com/image.png)")
        }
        XCTAssertEqual(mounted.view.document.blocks, [BlockInputBlock(id: imageID, text: "")])
    }

    private func copiedString(for image: BlockInputImage) throws -> String? {
        let blockID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .image(image))
        ])
        mounted.view.applySelection(.blocks([blockID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        return try withCleanPasteboard { pasteboard in
            XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandCEvent()))
            return pasteboard.string(forType: .string)
        }
    }

    private func withCleanPasteboard<T>(_ body: (NSPasteboard) throws -> T) rethrows -> T {
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
        return try body(pasteboard)
    }
}
