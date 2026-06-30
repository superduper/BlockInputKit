import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImagePreviewStripTests: XCTestCase {
    func testPreviewStripExtractsLoadedImageSyntaxOnly() async throws {
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [
            BlockInputBlock(id: "loaded", text: "Loaded ![Loaded](loaded.png)"),
            BlockInputBlock(id: "code", kind: .code(language: nil), text: "![Code](code.png)"),
            BlockInputBlock(id: "hidden", text: "Hidden ![Hidden](hidden.png)")
        ], initialLimit: 2)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(
            documentStore: store,
            imagePresentation: .textLinksWithPreviewStrip
        ))

        XCTAssertFalse(view.imagePreviewStripView.isHidden)
        XCTAssertEqual(view.imagePreviewStripView.itemCountForTesting, 1)

        try await store.loadNextBlockBatch(limit: 1)

        XCTAssertFalse(view.imagePreviewStripView.isHidden)
        XCTAssertEqual(view.imagePreviewStripView.itemCountForTesting, 2)
    }

    func testPreviewStripStyleControlsPreferredHeight() {
        var style = BlockInputStyle.default
        style.imagePreviewStrip = BlockInputImagePreviewStripStyle(
            thumbnailSize: NSSize(width: 42, height: 38),
            contentInsets: NSEdgeInsets(top: 5, left: 7, bottom: 6, right: 8),
            interItemSpacing: 9,
            backgroundColor: .systemPurple,
            borderColor: .separatorColor,
            borderWidth: 2,
            cornerRadius: 4,
            removeButton: BlockInputImagePreviewRemoveButtonStyle(
                size: NSSize(width: 18, height: 18),
                edgeInset: 3,
                borderWidth: 1,
                shadowRadius: 2
            )
        )
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(text: "![Alt](image.png)")
            ]),
            style: style,
            imagePresentation: .textLinksWithPreviewStrip
        ))

        XCTAssertEqual(view.imagePreviewStripHeightConstraint?.constant, 49)
        XCTAssertEqual(view.imagePreviewStripView.layer?.backgroundColor, NSColor.systemPurple.cgColor)
        XCTAssertFalse(view.imagePreviewStripView.scrollViewDrawsBackgroundForTesting)
        XCTAssertFalse(view.imagePreviewStripView.clipViewDrawsBackgroundForTesting)
        XCTAssertEqual(view.imagePreviewStripView.clipViewBackgroundColorForTesting, .clear)
        XCTAssertEqual(view.imagePreviewStripView.itemCountForTesting, 1)
        XCTAssertTrue(view.imagePreviewStripView.hasHorizontalScrollerForTesting)

        style.imagePreviewStrip.removeButton.symbolPointSize = 17
        view.configure(BlockInputConfiguration(
            document: view.document,
            style: style,
            imagePresentation: .textLinksWithPreviewStrip
        ))

        XCTAssertEqual(view.imagePreviewStripView.firstRemoveButtonImageSizeForTesting, NSSize(width: 17, height: 17))
    }

    func testPreviewStripStyleCanClearBackgroundColor() {
        var style = BlockInputStyle.default
        style.imagePreviewStrip = BlockInputImagePreviewStripStyle(backgroundColor: .systemPurple)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(text: "![Alt](image.png)")
            ]),
            style: style,
            imagePresentation: .textLinksWithPreviewStrip
        ))

        style.imagePreviewStrip.backgroundColor = nil
        view.configure(BlockInputConfiguration(
            document: view.document,
            style: style,
            imagePresentation: .textLinksWithPreviewStrip
        ))

        XCTAssertNil(view.imagePreviewStripView.layer?.backgroundColor)
    }

    func testInsertImageContextInTextLinkPresentationInsertsMarkdownImageText() {
        let blockID = BlockInputBlockID(rawValue: "block")
        let sourceText = "Before  after"
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: sourceText)
            ]),
            imagePresentation: .textLinksWithPreviewStrip
        ))
        let context = BlockInputImageContext(
            blockID: blockID,
            selectedRange: NSRange(location: 7, length: 0),
            sourceText: sourceText,
            anchorWindowRect: .zero
        )

        let selection = view.insertImage(
            BlockInputImage(source: "https://example.com/cat.png", altText: "Cat"),
            context: context
        )

        let expectedText = "Before ![Cat](https://example.com/cat.png) after"
        let expectedOffset = ("Before ![Cat](https://example.com/cat.png)" as NSString).length
        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[0].text, expectedText)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: expectedOffset)))
        XCTAssertEqual(view.imagePreviewStripView.itemCountForTesting, 1)
    }

    func testInsertImageContextInTextLinkPresentationAddsTrailingSpaceWhenInsertedAlone() {
        let blockID = BlockInputBlockID(rawValue: "block")
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "")
            ]),
            imagePresentation: .textLinksWithPreviewStrip
        ))
        let context = BlockInputImageContext(
            blockID: blockID,
            selectedRange: NSRange(location: 0, length: 0),
            sourceText: "",
            anchorWindowRect: .zero
        )

        let selection = view.insertImage(
            BlockInputImage(source: "https://example.com/cat.png", altText: "Cat"),
            context: context
        )

        let expectedText = "![Cat](https://example.com/cat.png) "
        XCTAssertEqual(view.document.blocks[0].text, expectedText)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: (expectedText as NSString).length)))
        XCTAssertEqual(view.imagePreviewStripView.itemCountForTesting, 1)
    }

    func testPreviewStripClickOpensResolvedImageURLThroughLinkOpener() throws {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        var openedURL: URL?
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(text: "Before ![Alt](cat.png) after")
            ]),
            imagePresentation: .textLinksWithPreviewStrip,
            imageBaseURL: try XCTUnwrap(URL(string: "https://example.com/assets/"))
        ))
        view.linkURLOpener = {
            openedURL = $0
            return true
        }

        view.imagePreviewStripView.openFirstTileForTesting()

        XCTAssertEqual(openedURL, try XCTUnwrap(URL(string: "https://example.com/assets/cat.png")))
    }

    func testPreviewStripRemovalAndUndoUseExactSourceRange() {
        let blockID = BlockInputBlockID(rawValue: "block")
        let sourceText = "Before ![Alt](file:///tmp/cat.png) after"
        let imageSource = "![Alt](file:///tmp/cat.png)"
        let range = (sourceText as NSString).range(of: imageSource)
        let undoController = BlockInputUndoController()
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: sourceText)
            ]),
            imagePresentation: .textLinksWithPreviewStrip,
            undoController: undoController
        ))
        let occurrence = BlockInputImagePreviewOccurrence(
            blockID: blockID,
            sourceRange: range,
            sourceText: imageSource,
            image: BlockInputImage(source: "file:///tmp/cat.png", altText: "Alt")
        )

        view.removeImagePreviewOccurrence(occurrence)

        XCTAssertEqual(view.document.blocks[0].text, "Before after")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: range.location)))
        XCTAssertTrue(view.imagePreviewStripView.isEmpty)

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Remove Image")
        XCTAssertEqual(view.document.blocks[0].text, sourceText)
        XCTAssertEqual(view.imagePreviewStripView.itemCountForTesting, 1)
    }

    func testPreviewStripRemovalCollapsesMiddleImageSeparator() {
        let blockID = BlockInputBlockID(rawValue: "block")
        let first = "![First](file:///tmp/first.png)"
        let second = "![Second](file:///tmp/second.png)"
        let third = "![Third](file:///tmp/third.png)"
        let sourceText = "\(first) \(second) \(third) "
        let range = (sourceText as NSString).range(of: second)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: sourceText)
            ]),
            imagePresentation: .textLinksWithPreviewStrip
        ))
        let occurrence = BlockInputImagePreviewOccurrence(
            blockID: blockID,
            sourceRange: range,
            sourceText: second,
            image: BlockInputImage(source: "file:///tmp/second.png", altText: "Second")
        )

        view.removeImagePreviewOccurrence(occurrence)

        XCTAssertEqual(view.document.blocks[0].text, "\(first) \(third) ")
        XCTAssertEqual(view.imagePreviewStripView.itemCountForTesting, 2)
    }

    func testPreviewStripReloadsImagesWhenBaseURLChanges() async throws {
        let loader = RecordingPreviewImageLoader()
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(text: "![Alt](image.png)")
        ])
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(
            document: document,
            imagePresentation: .textLinksWithPreviewStrip,
            imageLoader: loader,
            imageDiskCache: nil,
            imageBaseURL: try XCTUnwrap(URL(string: "https://one.example/assets/"))
        ))

        var resolvedURLs = try await loader.waitForResolvedURLCount(1)

        XCTAssertEqual(resolvedURLs, [try XCTUnwrap(URL(string: "https://one.example/assets/image.png"))])

        view.refreshImagePreviewStrip()
        resolvedURLs = try await loader.waitForResolvedURLCount(1)

        XCTAssertEqual(resolvedURLs.count, 1)

        view.configure(BlockInputConfiguration(
            document: document,
            imagePresentation: .textLinksWithPreviewStrip,
            imageLoader: loader,
            imageDiskCache: nil,
            imageBaseURL: try XCTUnwrap(URL(string: "https://two.example/assets/"))
        ))

        resolvedURLs = try await loader.waitForResolvedURLCount(2)

        XCTAssertEqual(resolvedURLs.last, try XCTUnwrap(URL(string: "https://two.example/assets/image.png")))
    }

    func testPreviewStripDownsamplesLoadedThumbnailToTileSize() async throws {
        let loader = RecordingPreviewImageLoader(imageData: try PreviewImageFixtures.pngData(width: 240, height: 120))
        var style = BlockInputStyle.default
        style.imagePreviewStrip = BlockInputImagePreviewStripStyle(
            thumbnailSize: NSSize(width: 24, height: 24)
        )
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(text: "![Alt](image.png)")
            ]),
            style: style,
            imagePresentation: .textLinksWithPreviewStrip,
            imageLoader: loader,
            imageDiskCache: nil,
            imageBaseURL: try XCTUnwrap(URL(string: "https://example.com/assets/"))
        ))

        let pixelSize = try await waitForLoadedImagePixelSize(in: view)
        let maxPixelDimension = ceil(24 * (NSScreen.main?.backingScaleFactor ?? 2))

        XCTAssertLessThanOrEqual(max(pixelSize.width, pixelSize.height), maxPixelDimension)

        style.imagePreviewStrip = BlockInputImagePreviewStripStyle(
            thumbnailSize: NSSize(width: 12, height: 12)
        )
        view.configure(BlockInputConfiguration(
            document: view.document,
            style: style,
            imagePresentation: .textLinksWithPreviewStrip,
            imageLoader: loader,
            imageDiskCache: nil,
            imageBaseURL: try XCTUnwrap(URL(string: "https://example.com/assets/"))
        ))
        _ = try await loader.waitForResolvedURLCount(2)

        let resizedPixelSize = try await waitForLoadedImagePixelSize(in: view)
        let resizedMaxPixelDimension = ceil(12 * (NSScreen.main?.backingScaleFactor ?? 2))

        XCTAssertLessThanOrEqual(max(resizedPixelSize.width, resizedPixelSize.height), resizedMaxPixelDimension)
    }

    private func waitForLoadedImagePixelSize(in view: BlockInputView) async throws -> NSSize {
        for _ in 0..<100 {
            if let size = view.imagePreviewStripView.firstLoadedImagePixelSizeForTesting {
                return size
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try XCTUnwrap(view.imagePreviewStripView.firstLoadedImagePixelSizeForTesting)
    }
}

private actor RecordingPreviewImageLoader: BlockInputImageLoading {
    private var resolvedURLs: [URL] = []
    private let imageData: Data

    init(imageData: Data = PreviewImageFixtures.transparentPixelData) {
        self.imageData = imageData
    }

    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        resolvedURLs.append(request.resolvedURL)
        return BlockInputLoadedImage(
            data: imageData,
            dimensions: BlockInputImageDimensions(width: 1, height: 1)
        )
    }

    func waitForResolvedURLCount(_ count: Int) async throws -> [URL] {
        for _ in 0..<100 {
            if resolvedURLs.count >= count {
                return resolvedURLs
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return resolvedURLs
    }

}

private enum RecordingPreviewImageLoaderError: Error {
    case invalidFixture
}

private enum PreviewImageFixtures {
    static let transparentPixelData = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==") ?? Data()

    static func pngData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RecordingPreviewImageLoaderError.invalidFixture
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else {
            throw RecordingPreviewImageLoaderError.invalidFixture
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RecordingPreviewImageLoaderError.invalidFixture
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RecordingPreviewImageLoaderError.invalidFixture
        }
        return data as Data
    }
}
