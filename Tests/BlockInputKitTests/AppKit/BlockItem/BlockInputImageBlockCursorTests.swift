import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImageBlockCursorTests: XCTestCase {
    func testImageBlockResizeCursorPrefersResizeEdges() {
        let imageView = BlockInputImageBlockView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        imageView.configureLoadedImage(
            NSImage(size: NSSize(width: 120, height: 80)),
            cacheKey: "test",
            style: .default,
            resizeDimensions: BlockInputImageDimensions(width: 120, height: 80)
        )

        XCTAssertEqual(imageView.resizeCursor(at: NSPoint(x: 118, y: 40)), .resizeLeftRight)
        XCTAssertEqual(imageView.resizeCursor(at: NSPoint(x: 60, y: 2)), .resizeUpDown)
        XCTAssertEqual(imageView.resizeCursor(at: NSPoint(x: 118, y: 2)), .resizeLeftRight)
        XCTAssertNil(imageView.resizeCursor(at: NSPoint(x: 60, y: 40)))

        imageView.isEditable = false

        XCTAssertNil(imageView.resizeCursor(at: NSPoint(x: 118, y: 40)))
    }
}
