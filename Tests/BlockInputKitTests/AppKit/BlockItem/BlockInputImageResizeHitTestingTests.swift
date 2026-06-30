import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImageResizeHitTestingTests: XCTestCase {
    func testHTMLImageRightResizeHitTargetWorksAfterMarkdownParsing() throws {
        let document = BlockInputDocument(markdown: "<img src=\"https://example.com/image.png\" width=\"400\" height=\"200\" />")
        let mounted = makeMountedBlockInputView(blocks: document.blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 300, height: 150, sourceStyle: .html))
        )
    }

    func testHTMLImageRightResizeHitTargetCanGrowBelowMaximumWidth() throws {
        let document = BlockInputDocument(markdown: "<img src=\"https://example.com/image.png\" width=\"120\" height=\"80\" />")
        let mounted = makeMountedBlockInputView(blocks: document.blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x + 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 220, height: 147, sourceStyle: .html))
        )
    }

    func testSelectedHTMLImageRightResizeHitTargetCanGrowBelowMaximumWidth() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(
                source: "https://example.com/image.png",
                width: 120,
                height: 80,
                sourceStyle: .html
            )))
        ])
        mounted.view.applySelection(.blocks([imageID]), notify: false)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x + 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 220, height: 147, sourceStyle: .html))
        )
    }

    func testLoadedSelectedHTMLImageRightResizeHitTargetCanGrowBelowMaximumWidth() async throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: imageID, kind: .image(BlockInputImage(
                    source: "https://example.com/image.png",
                    width: 120,
                    height: 80,
                    sourceStyle: .html
                )))
            ]),
            imageLoader: ResizeHitTestingImageLoader()
        ))
        mounted.view.applySelection(.blocks([imageID]), notify: false)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        try await waitForLoadedImage(in: imageView)
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x + 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 220, height: 147, sourceStyle: .html))
        )
    }

    func testHTMLImageRightResizeCanGrowThroughWindowEventDispatch() throws {
        let document = BlockInputDocument(markdown: "<img src=\"https://example.com/image.png\" width=\"120\" height=\"80\" />")
        let mounted = makeMountedBlockInputView(blocks: document.blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startLocation = imageView.convert(
            NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY),
            to: nil
        )
        mounted.window.makeKeyAndOrderFront(nil)

        mounted.window.sendEvent(try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        mounted.window.sendEvent(try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x + 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        mounted.window.sendEvent(try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 220, height: 147, sourceStyle: .html))
        )
    }

    func testHTMLImageRightResizeHitTargetIncludesLowerRightOutset() throws {
        let document = BlockInputDocument(markdown: "<img src=\"https://example.com/image.png\" width=\"400\" height=\"200\" />")
        let mounted = makeMountedBlockInputView(blocks: document.blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.minY - 2)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 300, height: 150, sourceStyle: .html))
        )
    }

    func testHTMLImageRightResizeHitTargetIncludesUpperRightOutset() throws {
        let document = BlockInputDocument(markdown: "<img src=\"https://example.com/image.png\" width=\"400\" height=\"200\" />")
        let mounted = makeMountedBlockInputView(blocks: document.blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.maxY + 2)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 300, height: 150, sourceStyle: .html))
        )
    }

    func testHTMLImageRightResizeHitTargetIncludesExternalRightOutset() throws {
        let document = BlockInputDocument(markdown: "<img src=\"https://example.com/image.png\" width=\"400\" height=\"200\" />")
        let mounted = makeMountedBlockInputView(blocks: document.blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startPoint = NSPoint(x: imageView.bounds.maxX + 2, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 300, height: 150, sourceStyle: .html))
        )
    }

    func testFullWidthHTMLImageRightResizeShrinksFromRenderedWidth() throws {
        let document = BlockInputDocument(markdown: "<img src=\"https://example.com/image.png\" width=\"4000\" height=\"3000\" />")
        let mounted = makeMountedBlockInputView(blocks: document.blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)
        let startLocation = imageView.convert(startPoint, to: nil)
        let expectedWidth = Int((imageView.bounds.width - 100).rounded())
        let expectedHeight = Int((CGFloat(expectedWidth) * 0.75).rounded())

        imageView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        imageView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        imageView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: expectedWidth, height: expectedHeight, sourceStyle: .html))
        )
    }

    func testFullWidthHTMLImageRightResizeContinuesAfterMountedItemReconfigures() throws {
        let document = BlockInputDocument(markdown: "<img src=\"https://example.com/image.png\" width=\"4000\" height=\"3000\" />")
        let mounted = makeMountedBlockInputView(blocks: document.blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)
        let expectedFirstWidth = Int((imageView.bounds.width - 40).rounded())
        let expectedFirstHeight = Int((CGFloat(expectedFirstWidth) * 0.75).rounded())
        let expectedSecondWidth = Int((imageView.bounds.width - 100).rounded())
        let expectedSecondHeight = Int((CGFloat(expectedSecondWidth) * 0.75).rounded())

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 40, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(
                source: "https://example.com/image.png",
                width: expectedFirstWidth,
                height: expectedFirstHeight,
                sourceStyle: .html
            ))
        )

        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(
                source: "https://example.com/image.png",
                width: expectedSecondWidth,
                height: expectedSecondHeight,
                sourceStyle: .html
            ))
        )
    }

    func testHTMLImageRightResizeContinuesAfterMountedItemReconfigures() throws {
        let document = BlockInputDocument(markdown: "<img src=\"https://example.com/image.png\" width=\"400\" height=\"200\" />")
        let mounted = makeMountedBlockInputView(blocks: document.blocks)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 40, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 360, height: 180, sourceStyle: .html))
        )

        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 300, height: 150, sourceStyle: .html))
        )
    }

    func testHTMLImageRightResizeContinuesAfterHostReconfigure() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(
                source: "https://example.com/image.png",
                width: 400,
                height: 200,
                sourceStyle: .html
            )))
        ]))
        var configuration = BlockInputConfiguration(documentStore: store)
        let mounted = makeMountedBlockInputView(configuration: configuration)
        configuration = BlockInputConfiguration(documentStore: store)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 40, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        mounted.view.configure(configuration)
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 300, height: 150, sourceStyle: .html))
        )
    }

    func testHTMLImageRightResizeUsesWindowDispatchAfterReorderingImageBlock() throws {
        let imageID = BlockInputBlockID(rawValue: "image")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "before", text: "Before"),
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(
                source: "https://example.com/image.png",
                width: 120,
                height: 80,
                sourceStyle: .html
            ))),
            BlockInputBlock(id: "after", text: "After")
        ])

        XCTAssertNotNil(mounted.view.moveBlock(blockID: imageID, to: 2))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let imageView = item.testingImageBlockView
        let startLocation = imageView.convert(
            NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY),
            to: nil
        )
        mounted.window.makeKeyAndOrderFront(nil)

        mounted.window.sendEvent(try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        mounted.window.sendEvent(try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x + 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        mounted.window.sendEvent(try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[2].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 220, height: 147, sourceStyle: .html))
        )
    }

    func testImageRightResizeHitTargetIncludesVisibleRightEdge() throws {
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
        let startPoint = NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY)
        let hitPoint = item.view.convert(startPoint, from: imageView)
        let hitView = try XCTUnwrap(item.view.hitTest(hitPoint) as? BlockInputImageBlockView)
        let startLocation = imageView.convert(startPoint, to: nil)

        hitView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        hitView.mouseDragged(with: try mouseDraggedEvent(
            location: NSPoint(x: startLocation.x - 100, y: startLocation.y),
            windowNumber: mounted.window.windowNumber
        ))
        hitView.mouseUp(with: try mouseUpEvent(location: startLocation, windowNumber: mounted.window.windowNumber))

        XCTAssertEqual(
            mounted.view.document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", width: 300, height: 150, sourceStyle: .html))
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

private struct ResizeHitTestingImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        guard let data = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==") else {
            throw ResizeHitTestingImageLoaderError.invalidFixture
        }
        return BlockInputLoadedImage(
            data: data,
            dimensions: BlockInputImageDimensions(width: 120, height: 80)
        )
    }
}

private enum ResizeHitTestingImageLoaderError: Error {
    case invalidFixture
}
