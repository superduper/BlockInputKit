import AppKit
import XCTest
@testable import BlockInputKit

/// Committed font zoom scales images too: `imageDisplaySize(zoomScale:)` grows the image with the text
/// until it fills the available width (browser/PDF behavior), and `baseFontScale` derives that factor.
@MainActor
final class BlockInputImageZoomScaleTests: XCTestCase {
    private let image = BlockInputImage(source: "https://example.com/image.png", width: 100, height: 50)

    func testZoomScaleEnlargesImageBelowContainerWidth() {
        let base = BlockInputBlockItem.imageDisplaySize(for: image, textWidth: 800, defaultAspectRatio: 16.0 / 9.0)
        let zoomed = BlockInputBlockItem.imageDisplaySize(
            for: image, textWidth: 800, defaultAspectRatio: 16.0 / 9.0, zoomScale: 1.5
        )
        XCTAssertEqual(zoomed.width, base.width * 1.5, accuracy: 0.5)
        XCTAssertEqual(zoomed.height, base.height * 1.5, accuracy: 0.5)
    }

    func testZoomScaleClampsToAvailableWidth() {
        // A huge zoom cannot exceed the container width.
        let zoomed = BlockInputBlockItem.imageDisplaySize(
            for: image, textWidth: 120, defaultAspectRatio: 16.0 / 9.0, zoomScale: 10
        )
        XCTAssertLessThanOrEqual(zoomed.width, 120 + 0.5)
    }

    func testDefaultZoomScaleIsUnchanged() {
        let base = BlockInputBlockItem.imageDisplaySize(for: image, textWidth: 800, defaultAspectRatio: 16.0 / 9.0)
        let explicitOne = BlockInputBlockItem.imageDisplaySize(
            for: image, textWidth: 800, defaultAspectRatio: 16.0 / 9.0, zoomScale: 1
        )
        XCTAssertEqual(base, explicitOne)
    }

    func testBaseFontScaleMatchesFontRatio() {
        XCTAssertEqual(BlockInputBlockItem.baseFontScale(for: .default), 1, accuracy: 0.0001)
        let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
        var style = BlockInputStyle.default
        style.baseText.font = NSFont.systemFont(ofSize: bodySize * 2)
        XCTAssertEqual(BlockInputBlockItem.baseFontScale(for: style), 2, accuracy: 0.0001)
    }

    func testImageHeightGrowsWithZoom() {
        let base = BlockInputBlockItem.imageHeight(for: image, textWidth: 800, defaultAspectRatio: 16.0 / 9.0)
        let zoomed = BlockInputBlockItem.imageHeight(
            for: image, textWidth: 800, defaultAspectRatio: 16.0 / 9.0, zoomScale: 1.5
        )
        XCTAssertGreaterThan(zoomed, base)
    }
}
