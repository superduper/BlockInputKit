import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImageCaretTests: XCTestCase {
    func testClickingImageGuttersPlacesImageCaret() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 120, height: 80)))
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let topPoint = item.view.convert(NSPoint(x: imageView.frame.midX, y: imageView.frame.maxY + 2), to: nil)
        let bottomPoint = item.view.convert(NSPoint(x: imageView.frame.midX, y: imageView.frame.minY - 5), to: nil)

        item.view.mouseDown(with: try mouseDownEvent(location: topPoint, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 0)))
        XCTAssertFalse(item.testingImageCaretView.isHidden)
        XCTAssertEqual(item.testingImageCaretView.accessibilityLabel(), "Before image")
        XCTAssertEqual(item.testingImageCaretView.frame.maxX, imageView.frame.minX, accuracy: 0.5)
        XCTAssertEqual(item.testingImageCaretView.frame.minY, imageView.frame.minY, accuracy: 0.5)
        XCTAssertEqual(item.testingImageCaretView.frame.height, imageView.frame.height, accuracy: 0.5)

        item.view.mouseDown(with: try mouseDownEvent(location: bottomPoint, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
        XCTAssertFalse(item.testingImageCaretView.isHidden)
        XCTAssertEqual(item.testingImageCaretView.accessibilityLabel(), "After image")
        XCTAssertEqual(item.testingImageCaretView.frame.minX, imageView.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(item.testingImageCaretView.frame.minY, imageView.frame.minY, accuracy: 0.5)
        XCTAssertEqual(item.testingImageCaretView.frame.height, imageView.frame.height, accuracy: 0.5)
    }

    func testClickingImageSideGuttersPlacesFullHeightImageCaret() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 120, height: 80)))
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let leftPoint = item.view.convert(NSPoint(x: imageView.frame.minX - 2, y: imageView.frame.midY), to: nil)
        let rightPoint = item.view.convert(NSPoint(x: imageView.frame.maxX + 6, y: imageView.frame.midY), to: nil)

        item.view.mouseDown(with: try mouseDownEvent(location: leftPoint, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 0)))
        XCTAssertEqual(item.testingImageCaretView.frame.maxX, imageView.frame.minX, accuracy: 0.5)
        XCTAssertEqual(item.testingImageCaretView.frame.height, imageView.frame.height, accuracy: 0.5)

        item.view.mouseDown(with: try mouseDownEvent(location: rightPoint, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
        XCTAssertEqual(item.testingImageCaretView.frame.minX, imageView.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(item.testingImageCaretView.frame.height, imageView.frame.height, accuracy: 0.5)
    }

    func testClickingRightToLeftImageSideGuttersUsesVisualBeforeAndAfter() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let block = BlockInputBlock(
            id: imageID,
            kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 120, height: 80))
        )
        let mounted = makeMountedBlockInputView(blocks: [block])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        item.view.userInterfaceLayoutDirection = .rightToLeft
        item.updateImageBlockLayout(for: block)
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()
        let imageView = item.testingImageBlockView
        let rightPoint = item.view.convert(NSPoint(x: imageView.frame.maxX + 6, y: imageView.frame.midY), to: nil)
        let leftPoint = item.view.convert(NSPoint(x: imageView.frame.minX - 2, y: imageView.frame.midY), to: nil)

        item.view.mouseDown(with: try mouseDownEvent(location: rightPoint, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 0)))
        XCTAssertEqual(item.testingImageCaretView.frame.minX, imageView.frame.maxX, accuracy: 0.5)

        item.view.mouseDown(with: try mouseDownEvent(location: leftPoint, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
        XCTAssertEqual(item.testingImageCaretView.frame.maxX, imageView.frame.minX, accuracy: 0.5)
    }

    func testLeftAndRightFromSelectedImagePlaceBoundaryCaret() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        mounted.view.applySelection(.blocks([imageID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 123, characters: "\u{F702}"))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 0)))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertTrue(item.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(item.testingImageCaretView.frame.maxX, item.testingImageBlockView.frame.minX, accuracy: 0.5)
        XCTAssertEqual(item.testingImageCaretView.frame.height, item.testingImageBlockView.frame.height, accuracy: 0.5)

        mounted.view.applySelection(.blocks([imageID]), notify: false)
        mounted.view.keyDown(with: try plainRightEvent())

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
        XCTAssertEqual(item.testingImageCaretView.frame.minX, item.testingImageBlockView.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(item.testingImageCaretView.frame.height, item.testingImageBlockView.frame.height, accuracy: 0.5)
    }

    func testArrowingFromSelectedLoadedImageDoesNotReloadImageSurface() async throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
            ]),
            imageLoader: CaretImmediateImageLoader()
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        try await waitForLoadedImage(in: item.testingImageBlockView)
        mounted.view.applySelection(.blocks([imageID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try plainRightEvent())

        XCTAssertNotNil(item.testingImageBlockView.loadedImageForTesting)
        XCTAssertEqual(item.testingImageBlockView.statusTextForTesting, "")
    }

    func testMovingVerticallyIntoLoadingImagePlacesBoundaryCaretWithoutShowingFailure() async throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "above", text: "Above"),
                BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png"))),
                BlockInputBlock(id: "below", text: "Below")
            ]),
            imageLoader: CaretDelayedImageLoader()
        ))
        let imageItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let topTextView = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
        topTextView.setSelectedRange(NSRange(location: 5, length: 0))

        topTextView.doCommand(by: #selector(NSResponder.moveDown(_:)))
        try await Task.sleep(nanoseconds: 25_000_000)

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 0)))
        XCTAssertEqual(imageItem.testingImageBlockView.statusTextForTesting, "")
        XCTAssertFalse(imageItem.testingImageCaretView.isHidden)
        XCTAssertEqual(imageItem.testingImageCaretView.accessibilityLabel(), "Before image")

        let bottomTextView = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2)?.testingTextView)
        bottomTextView.setSelectedRange(NSRange(location: 0, length: 0))

        bottomTextView.doCommand(by: #selector(NSResponder.moveUp(_:)))
        try await Task.sleep(nanoseconds: 25_000_000)

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
        XCTAssertEqual(imageItem.testingImageBlockView.statusTextForTesting, "")
        XCTAssertFalse(imageItem.testingImageCaretView.isHidden)
        XCTAssertEqual(imageItem.testingImageCaretView.accessibilityLabel(), "After image")
    }

    func testMovingVerticallyFromImageCaretToHorizontalRuleSelectsRule() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let upperRuleID = BlockInputBlockID(rawValue: "upper-rule")
        let lowerRuleID = BlockInputBlockID(rawValue: "lower-rule")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: upperRuleID, kind: .horizontalRule),
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png"))),
            BlockInputBlock(id: lowerRuleID, kind: .horizontalRule)
        ])
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 0)), notify: false)
        mounted.view.keyDown(with: try plainUpEvent())

        XCTAssertEqual(mounted.view.selection, .blocks([upperRuleID]))

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)), notify: false)
        mounted.view.keyDown(with: try plainDownEvent())

        XCTAssertEqual(mounted.view.selection, .blocks([lowerRuleID]))
    }

    func testDeleteAtBeforeImageCaretMovesCaretToPreviousTextBlock() throws {
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: paragraphID, text: "Above"),
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 0)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: paragraphID, utf16Offset: 5)))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
    }

    func testDeleteAtBeforeImageCaretMovesCaretAfterPreviousImage() throws {
        let firstImageID = BlockInputBlockID(rawValue: "first-image")
        let secondImageID = BlockInputBlockID(rawValue: "second-image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstImageID, kind: .image(BlockInputImage(source: "https://example.com/first.png"))),
            BlockInputBlock(id: secondImageID, kind: .image(BlockInputImage(source: "https://example.com/second.png")))
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: secondImageID, utf16Offset: 0)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstImageID, utf16Offset: 1)))
        XCTAssertEqual(mounted.view.visibleBlockItemForTesting(at: 0)?.testingImageCaretView.accessibilityLabel(), "After image")
    }

    func testLeftAndRightFromSelectedDuplicateImagePlaceCaretOnSelectedRow() throws {
        let sharedID = BlockInputBlockID(rawValue: "shared")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: sharedID, kind: .image(BlockInputImage(source: "https://example.com/first.png", width: 120, height: 80))),
            BlockInputBlock(id: "middle", text: "Middle"),
            BlockInputBlock(id: sharedID, kind: .image(BlockInputImage(source: "https://example.com/second.png", width: 120, height: 80)))
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        secondItem.mouseDown(with: try mouseDownEvent(windowNumber: mounted.window.windowNumber))
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try plainRightEvent())

        XCTAssertTrue(firstItem.testingImageCaretView.isHidden)
        XCTAssertFalse(secondItem.testingImageCaretView.isHidden)
        XCTAssertEqual(secondItem.testingImageCaretView.accessibilityLabel(), "After image")
    }

    func testReturnBeforeAndAfterImageInsertParagraphs() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])

        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 0)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        mounted.view.keyDown(with: try keyDownEvent(keyCode: 36, characters: "\r"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [
            .paragraph,
            .image(BlockInputImage(source: "https://example.com/image.png"))
        ])

        let movedImageID = mounted.view.document.blocks[1].id
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: movedImageID, utf16Offset: 1)), notify: false)
        mounted.view.keyDown(with: try keyDownEvent(keyCode: 36, characters: "\r"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [
            .paragraph,
            .image(BlockInputImage(source: "https://example.com/image.png")),
            .paragraph
        ])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: mounted.view.document.blocks[2].id, utf16Offset: 0)))
    }

    func testReturnAfterImageThenDeletingInsertedParagraphReturnsCaretAfterImage() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 36, characters: "\r"))
        let insertedTextView = try XCTUnwrap(mounted.window.firstResponder as? BlockInputTextView)
        insertedTextView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [
            .image(BlockInputImage(source: "https://example.com/image.png"))
        ])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
    }

    func testReturnAfterTallImageScrollsInsertedParagraphIntoView() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(
                source: "https://example.com/image.png",
                width: 1_000,
                height: 3_000
            )))
        ])
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)
        let initialVisibleY = mounted.view.collectionView.visibleRect.origin.y

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 36, characters: "\r"))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let insertedFrame = try XCTUnwrap(mounted.view.collectionView.collectionViewLayout?.layoutAttributesForItem(
            at: IndexPath(item: 1, section: 0)
        )?.frame)
        XCTAssertGreaterThan(
            mounted.view.collectionView.visibleRect.origin.y,
            initialVisibleY,
            "visibleRect=\(mounted.view.collectionView.visibleRect) insertedFrame=\(insertedFrame)"
        )
        XCTAssertTrue(
            mounted.view.collectionView.visibleRect.intersects(insertedFrame),
            "visibleRect=\(mounted.view.collectionView.visibleRect) insertedFrame=\(insertedFrame)"
        )
    }

    func testTypingAtImageCaretCreatesAdjacentParagraph() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 0, characters: "A"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["", "A"])
        XCTAssertEqual(mounted.view.document.blocks[1].kind, .paragraph)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: mounted.view.document.blocks[1].id, utf16Offset: 1)))
    }

    func testTabAtImageCaretDoesNotCreateParagraph() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 48, characters: "\t"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [
            .image(BlockInputImage(source: "https://example.com/image.png"))
        ])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
    }

    func testPastingAtImageCaretCreatesAdjacentParagraph() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
        pasteboard.setString("Pasted", forType: .string)
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: imageID, utf16Offset: 0)), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.blockInputPaste(nil)

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Pasted", ""])
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: mounted.view.document.blocks[0].id, utf16Offset: 6)))
    }

    func testDeletingEmptyParagraphAfterImageReturnsCaretAfterImage() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png"))),
            BlockInputBlock(id: paragraphID, text: "")
        ])
        mounted.view.focus(blockID: paragraphID, utf16Offset: 0)

        let selection = mounted.view.deleteCurrentEmptyBlockForBackspaceOrDelete()

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [imageID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: imageID, utf16Offset: 1)))
    }

    private func waitForLoadedImage(in imageView: BlockInputImageBlockView) async throws {
        for _ in 0..<20 {
            if imageView.loadedImageForTesting != nil {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Image did not load.")
    }
}

private struct CaretImmediateImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try BlockInputLoadedImage(
            data: imageData(),
            dimensions: BlockInputImageDimensions(width: 1, height: 1)
        )
    }

    private func imageData() throws -> Data {
        guard let data = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==") else {
            throw CaretImageLoaderTestError.invalidFixture
        }
        return data
    }
}

private struct CaretDelayedImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try await Task.sleep(nanoseconds: 250_000_000)
        return try await CaretImmediateImageLoader().loadImage(request)
    }
}

private enum CaretImageLoaderTestError: Error {
    case invalidFixture
}
