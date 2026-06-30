import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImageResizeRenderingTests: XCTestCase {
    func testResizingLoadedRelativeImageKeepsLoadedSurface() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(source: "image.gif", width: 80, height: 80)))
            ]),
            imageLoader: ResizeImmediateImageLoader(),
            imageBaseURL: try XCTUnwrap(URL(string: "https://assets.example/images/"))
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView
        try await waitForLoadedImage(in: imageView)

        imageView.onResize?(120, 120)

        XCTAssertNotNil(imageView.loadedImageForTesting)
        XCTAssertEqual(imageView.statusTextForTesting, "")
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .image(BlockInputImage(
            source: "image.gif",
            width: 120,
            height: 120,
            sourceStyle: .html
        )))
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

private struct ResizeImmediateImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try BlockInputLoadedImage(
            data: imageData(),
            dimensions: BlockInputImageDimensions(width: 1, height: 1)
        )
    }

    private func imageData() throws -> Data {
        guard let data = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==") else {
            throw ResizeImageLoaderTestError.invalidFixture
        }
        return data
    }
}

private enum ResizeImageLoaderTestError: Error {
    case invalidFixture
}
