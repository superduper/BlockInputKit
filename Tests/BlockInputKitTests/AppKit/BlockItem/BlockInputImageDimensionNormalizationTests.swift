import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImageDimensionTests: XCTestCase {
    func testLoadedImageContentStartAlignsInsideSurface() throws {
        let imageView = BlockInputImageBlockView()
        imageView.configureLoadedImage(NSImage(size: NSSize(width: 1, height: 1)), cacheKey: "test", style: .default, resizeDimensions: nil)

        imageView.userInterfaceLayoutDirection = .leftToRight
        imageView.layoutSubtreeIfNeeded()
        XCTAssertEqual(imageView.imageAlignmentForTesting, .alignLeft)

        imageView.userInterfaceLayoutDirection = .rightToLeft
        imageView.layoutSubtreeIfNeeded()
        XCTAssertEqual(imageView.imageAlignmentForTesting, .alignRight)
    }

    func testRepairsMismatchedWidthAndHeightUsingLargerWidth() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(
                    source: "https://example.com/wide.png",
                    width: 300,
                    height: 40,
                    sourceStyle: .html
                )))
            ]),
            imageLoader: DimensionNormalizationImageLoader()
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        try await waitForLoadedImage(in: item.testingImageBlockView)
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/wide.png", width: 300, height: 150, sourceStyle: .html))
        )
        XCTAssertEqual(updatedItem.testingImageBlockView.frame.width, 300, accuracy: 0.5)
        XCTAssertEqual(updatedItem.testingImageBlockView.frame.height, 150, accuracy: 0.5)
    }

    func testRepairsMismatchedWidthAndHeightUsingLargerHeight() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(
                    source: "https://example.com/wide.png",
                    width: 20,
                    height: 300,
                    sourceStyle: .html
                )))
            ]),
            imageLoader: DimensionNormalizationImageLoader()
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        try await waitForLoadedImage(in: item.testingImageBlockView)

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/wide.png", width: 600, height: 300, sourceStyle: .html))
        )
    }

    func testRepairsOnePointMismatch() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(
                    source: "https://example.com/wide.png",
                    width: 50,
                    height: 26,
                    sourceStyle: .html
                )))
            ]),
            imageLoader: DimensionNormalizationImageLoader()
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        try await waitForLoadedImage(in: item.testingImageBlockView)

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/wide.png", width: 50, height: 25, sourceStyle: .html))
        )
    }

    func testPreservesMatchingWidthAndHeightAfterLoad() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(
                    source: "https://example.com/wide.png",
                    width: 300,
                    height: 150,
                    sourceStyle: .html
                )))
            ]),
            imageLoader: DimensionNormalizationImageLoader()
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        try await waitForLoadedImage(in: item.testingImageBlockView)

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/wide.png", width: 300, height: 150, sourceStyle: .html))
        )
    }

    func testRightResizeUsesResolvedAspectRatio() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(
                    source: "https://example.com/wide.png",
                    width: 200,
                    height: 40,
                    sourceStyle: .html
                )))
            ]),
            imageLoader: DimensionNormalizationImageLoader()
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        try await waitForLoadedImage(in: imageView)
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 50, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/wide.png", width: 150, height: 75, sourceStyle: .html))
        )
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

private struct DimensionNormalizationImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        guard let data = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==") else {
            throw DimensionNormalizationImageLoaderError.invalidFixture
        }
        return BlockInputLoadedImage(
            data: data,
            dimensions: BlockInputImageDimensions(width: 400, height: 200)
        )
    }
}

private enum DimensionNormalizationImageLoaderError: Error {
    case invalidFixture
}
