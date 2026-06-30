import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImageBlockRenderingTests: XCTestCase {
    func testImageHeightUsesModelDimensionsAndTableLikeVerticalSpacing() {
        let block = BlockInputBlock(
            kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 200, height: 100))
        )

        let height = BlockInputBlockItem.height(for: block, textWidth: 360)

        XCTAssertEqual(height, 112)
    }

    func testImageHeightUsesConfiguredPlaceholderAspectRatioBeforeDimensionsResolve() {
        let block = BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        let style = BlockInputStyle(imageBlock: BlockInputImageBlockStyle(placeholderAspectRatio: 1))

        let height = BlockInputBlockItem.height(for: block, textWidth: 360, style: style)

        XCTAssertEqual(height, 372)
    }

    func testImageHeightUsesExplicitWidthBeforeHeightResolves() {
        let block = BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 80)))
        let style = BlockInputStyle(imageBlock: BlockInputImageBlockStyle(placeholderAspectRatio: 1))

        let height = BlockInputBlockItem.height(for: block, textWidth: 360, style: style)

        XCTAssertEqual(height, 92)
    }

    func testImageBlockUsesModelWidthForRenderedSurface() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 80, height: 40)))
        ])

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView

        XCTAssertEqual(imageView.frame.width, 80, accuracy: 0.5)
        XCTAssertEqual(imageView.frame.minX, item.scrollView.frame.minX + BlockInputBlockItem.imageSurfaceHorizontalInset, accuracy: 0.5)
    }

    func testImageBlockDefaultSurfaceUsesMatchingHorizontalInsets() throws {
        let paragraphMounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(kind: .paragraph, text: "Plain text")
        ])
        let paragraphItem = try XCTUnwrap(paragraphMounted.view.visibleBlockItemForTesting(at: 0))
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let leadingInset = imageView.frame.minX - item.scrollView.frame.minX
        let trailingInset = item.scrollView.frame.maxX - imageView.frame.maxX

        XCTAssertEqual(imageView.frame.minX, try textGlyphLeadingX(in: paragraphItem), accuracy: 0.5)
        XCTAssertEqual(leadingInset, BlockInputBlockItem.imageSurfaceHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(trailingInset, leadingInset, accuracy: 0.5)
    }

    func testImageBlockStartAlignsRenderedSurfaceInRightToLeftLayout() throws {
        let block = BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 80, height: 40)))
        let mounted = makeMountedBlockInputView(blocks: [block])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        item.view.userInterfaceLayoutDirection = .rightToLeft
        item.updateImageBlockLayout(for: block)
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        XCTAssertEqual(item.testingImageBlockView.frame.width, 80, accuracy: 0.5)
        XCTAssertEqual(
            item.testingImageBlockView.frame.maxX,
            item.scrollView.frame.maxX - BlockInputBlockItem.imageSurfaceHorizontalInset,
            accuracy: 0.5
        )
    }

    func testImageBlockDrawsExplicitBorderStyle() throws {
        let imageView = BlockInputImageBlockView()
        let style = BlockInputStyle(imageBlock: BlockInputImageBlockStyle(borderColor: .red))

        imageView.configureLoadedImage(NSImage(size: NSSize(width: 1, height: 1)), cacheKey: "test", style: style, resizeDimensions: nil)

        XCTAssertEqual(imageView.layer?.borderWidth, 1)
        XCTAssertEqual(imageView.layer?.borderColor, NSColor.red.cgColor)
    }

    func testSelectedImageBlockDrawsSelectionBorderOverSurfaceStyle() throws {
        let style = BlockInputStyle(
            selectionBackgroundColor: .systemGreen,
            imageBlock: BlockInputImageBlockStyle(borderColor: .red)
        )
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 80, height: 40))),
            allowsReordering: true,
            style: style,
            isSelected: true,
            delegate: BlockInputView()
        )

        XCTAssertTrue(item.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(item.testingImageBlockView.layer?.borderWidth, 2)
        XCTAssertEqual(item.testingImageBlockView.layer?.borderColor, NSColor.systemGreen.cgColor)

        item.setBlockSelection(false)

        XCTAssertEqual(item.testingImageBlockView.layer?.borderWidth, 1)
        XCTAssertEqual(item.testingImageBlockView.layer?.borderColor, NSColor.red.cgColor)
    }

    func testClickingImageSurfaceSelectsImageBlock() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let imageCenter = NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(imageCenter, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let windowPoint = imageView.convert(imageCenter, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: windowPoint, windowNumber: mounted.window.windowNumber))
        hitView.mouseUp(with: try mouseUpEvent(location: windowPoint, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(mounted.view.selection, .blocks([imageID]))
        XCTAssertEqual(hitView.layer?.borderWidth, 2)
    }

    func testImageSurfaceContextMenuProvidesDeleteImageAction() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let imageCenter = NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(imageCenter, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let event = try rightMouseDownEvent(
            location: imageView.convert(imageCenter, to: nil),
            windowNumber: mounted.window.windowNumber
        )

        XCTAssertEqual(hitView.menu(for: event)?.items.map(\.title), ["Delete Image"])
    }

    func testImageBlockShowsPlaceholderBeforeLoadCompletes() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
            ]),
            imageLoader: DelayedImageLoader()
        ))

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView

        XCTAssertFalse(imageView.isHidden)
        XCTAssertNil(imageView.loadedImageForTesting)
        XCTAssertEqual(imageView.statusTextForTesting, "")
        XCTAssertNotNil(imageView.layer?.backgroundColor)
    }

    func testReconfiguringLoadingImageKeepsPlaceholderWithoutShowingCancellationFailure() async throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png")))
            ]),
            imageLoader: DelayedImageLoader()
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        mounted.view.configureBlockItem(item, block: mounted.view.document.blocks[0])
        try await Task.sleep(nanoseconds: 25_000_000)

        XCTAssertNil(item.testingImageBlockView.loadedImageForTesting)
        XCTAssertEqual(item.testingImageBlockView.statusTextForTesting, "")
    }

    func testImageResizeIsDisabledUntilDimensionsAreKnown() throws {
        let unknown = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png"))),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let known = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 320, height: 180))),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        XCTAssertNil(unknown.testingImageBlockView.resizeDimensions)
        XCTAssertEqual(known.testingImageBlockView.resizeDimensions, BlockInputImageDimensions(width: 320, height: 180))
    }

    func testImageResizeStartsFromRenderedWidthForOversizedImage() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 4000, height: 3000)))
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        var resizedDimensions: BlockInputImageDimensions?
        imageView.onResize = { width, height in
            resizedDimensions = BlockInputImageDimensions(width: width, height: height)
        }
        let scale = min(imageView.bounds.width / 4000, imageView.bounds.height / 3000)
        let renderedStart = BlockInputImageDimensions(
            width: Int((4000 * scale).rounded()),
            height: Int((3000 * scale).rounded())
        )
        let startLocation = imageView.convert(
            NSPoint(x: imageView.bounds.maxX - 1, y: imageView.bounds.midY),
            to: nil
        )

        imageView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        imageView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))

        XCTAssertEqual(
            resizedDimensions,
            BlockInputImageDimensions(width: renderedStart.width - 100, height: Int((CGFloat(renderedStart.width - 100) * 0.75).rounded()))
        )
    }

    func testImageRightResizePreservesAspectRatioAndUpdatesBlockHeight() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(
                source: "https://example.com/image.png",
                width: 400,
                height: 200
            )))
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let originalHeight = item.view.frame.height
        let startLocation = imageView.convert(
            NSPoint(x: imageView.bounds.maxX - 1, y: imageView.bounds.midY),
            to: nil
        )

        imageView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        imageView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        imageView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        mounted.view.collectionView.layoutSubtreeIfNeeded()
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 300, height: 150, sourceStyle: .html))
        )
        XCTAssertLessThan(updatedItem.view.frame.height, originalHeight)
        XCTAssertEqual(updatedItem.view.frame.height, 162, accuracy: 0.5)
        XCTAssertEqual(updatedItem.testingImageBlockView.frame.height, 150, accuracy: 0.5)
    }

    func testImageResizeKeepsLoadedImageVisibleWhileModelUpdates() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(
                    source: "https://example.com/image.png",
                    width: 400,
                    height: 200
                )))
            ]),
            imageLoader: DelayedImageLoader()
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        try await waitForLoadedImage(in: imageView)
        let startLocation = imageView.convert(
            NSPoint(x: imageView.bounds.maxX - 1, y: imageView.bounds.midY),
            to: nil
        )

        imageView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        imageView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        XCTAssertNotNil(updatedItem.testingImageBlockView.loadedImageForTesting)
        XCTAssertEqual(updatedItem.testingImageBlockView.statusTextForTesting, "")
    }

    func testImageBlockDisplaysLoadedImage() async throws {
        let imageURL = try temporaryGIFURL()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(source: imageURL.absoluteString)))
            ])
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        try await waitForLoadedImage(in: item.testingImageBlockView)

        XCTAssertNotNil(item.testingImageBlockView.loadedImageForTesting)
        XCTAssertEqual(item.testingImageBlockView.resizeDimensions, BlockInputImageDimensions(width: 1, height: 1))
        XCTAssertEqual(item.testingImageBlockView.layer?.borderWidth, 0)
        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: imageURL.absoluteString, width: 1, height: 1))
        )
        XCTAssertEqual(item.testingImageBlockView.statusTextForTesting, "")
    }

    func testImageBlockPreservesExplicitWidthWhenResolvingHeight() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(
                    source: "https://example.com/wide.png",
                    width: 80,
                    sourceStyle: .html
                )))
            ]),
            imageLoader: WideImageLoader()
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        try await waitForLoadedImage(in: item.testingImageBlockView)
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/wide.png", width: 80, height: 40, sourceStyle: .html))
        )
        XCTAssertEqual(updatedItem.testingImageBlockView.frame.width, 80, accuracy: 0.5)
    }

    func testResolvedTallImageUpdatesScrollableContentHeight() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/tall.png")))
            ]),
            imageLoader: TallImageLoader()
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        try await waitForLoadedImage(in: item.testingImageBlockView)
        mounted.view.collectionView.layoutSubtreeIfNeeded()
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let contentHeight = mounted.view.collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0

        XCTAssertGreaterThan(updatedItem.view.frame.height, mounted.view.collectionView.visibleRect.height)
        XCTAssertGreaterThanOrEqual(contentHeight, updatedItem.view.frame.maxY - 0.5)
    }

    func testImageReplacementUpdatesScrollableContentHeight() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 100, height: 100)))
        ])
        let originalContentHeight = mounted.view.collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
        let tallBlock = BlockInputBlock(
            id: imageID,
            kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 100, height: 2_000))
        )

        XCTAssertTrue(mounted.view.applyGranularBlockReplacement(tallBlock, at: 0, selection: .blocks([imageID])))
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let contentHeight = mounted.view.collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0

        XCTAssertGreaterThan(contentHeight, originalContentHeight)
        XCTAssertGreaterThanOrEqual(contentHeight, updatedItem.view.frame.maxY - 0.5)
    }

    func testImageBlockShowsFailureWhenRemoteLoadingIsDisabled() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png")))
            ]),
            allowsRemoteImageLoading: false
        ))

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        try await waitForStatusText(in: item.testingImageBlockView)
        XCTAssertNil(item.testingImageBlockView.loadedImageForTesting)
        XCTAssertEqual(item.testingImageBlockView.statusTextForTesting, "Image failed to load")
    }

    func testClickingImageSelectsItAndDeleteRemovesOnlyClickedDuplicateID() throws {
        let sharedID = BlockInputBlockID(rawValue: "shared")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: sharedID, kind: .image(BlockInputImage(source: "https://example.com/first.png"))),
            BlockInputBlock(id: "middle", text: "Middle"),
            BlockInputBlock(id: sharedID, kind: .image(BlockInputImage(source: "https://example.com/second.png")))
        ])
        let secondItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))

        secondItem.mouseDown(with: try mouseDownEvent(windowNumber: mounted.window.windowNumber))
        mounted.view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "middle", utf16Offset: 6)))
        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertEqual(mounted.view.document.blocks[0].id, sharedID)
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .image(BlockInputImage(source: "https://example.com/first.png")))
        XCTAssertEqual(mounted.view.document.blocks[1].id, "middle")
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

    private func waitForStatusText(in imageView: BlockInputImageBlockView) async throws {
        for _ in 0..<20 {
            if !imageView.statusTextForTesting.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func textGlyphLeadingX(in item: BlockInputBlockItem) throws -> CGFloat {
        let textView = try XCTUnwrap(item.testingTextView)
        let textContainer = try XCTUnwrap(textView.textContainer)
        return item.scrollView.frame.minX + textView.textContainerInset.width + textContainer.lineFragmentPadding
    }

    private func temporaryGIFURL() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")
        try ImmediateImageLoader.imageData().write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private struct ImmediateImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try BlockInputLoadedImage(
            data: Self.imageData(),
            dimensions: BlockInputImageDimensions(width: 1, height: 1)
        )
    }

    static func imageData() throws -> Data {
        guard let data = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==") else {
            throw ImageLoaderTestError.invalidFixture
        }
        return data
    }
}

private struct DelayedImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try await Task.sleep(nanoseconds: 250_000_000)
        return try await ImmediateImageLoader().loadImage(request)
    }
}

private struct TallImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try BlockInputLoadedImage(
            data: ImmediateImageLoader.imageData(),
            dimensions: BlockInputImageDimensions(width: 100, height: 2_000)
        )
    }
}

private struct WideImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try BlockInputLoadedImage(
            data: ImmediateImageLoader.imageData(),
            dimensions: BlockInputImageDimensions(width: 400, height: 200)
        )
    }
}

private enum ImageLoaderTestError: Error {
    case invalidFixture
}
