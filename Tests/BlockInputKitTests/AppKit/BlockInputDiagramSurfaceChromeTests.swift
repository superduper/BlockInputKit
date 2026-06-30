import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputDiagramSurfaceChromeTests: XCTestCase {
    func testCloseAndFullscreenButtonsAreSameHeight() {
        let chrome = BlockInputDiagramSurfaceChrome()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        chrome.addToTopRight(of: host)
        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(chrome.closeButtonHeightForTesting, 0)
        XCTAssertEqual(chrome.closeButtonHeightForTesting,
                       chrome.fullscreenButtonHeightForTesting,
                       accuracy: 0.5,
                       "the ✕ and Full screen buttons must render at the same height")
        XCTAssertEqual(chrome.closeButtonMidYForTesting,
                       chrome.fullscreenButtonMidYForTesting,
                       accuracy: 0.5,
                       "the ✕ and Full screen buttons must be vertically centered together")
    }

    func testFullscreenButtonHiddenWhileFullscreen() {
        let chrome = BlockInputDiagramSurfaceChrome()
        XCTAssertEqual(chrome.fullscreenButtonTitleForTesting, "Full screen")
        XCTAssertFalse(chrome.isFullscreenButtonHiddenForTesting, "shown when not fullscreen")
        // While fullscreen only ✕ remains (Esc exits fullscreen), so the Full screen button hides.
        chrome.setFullscreen(true)
        XCTAssertTrue(chrome.isFullscreenButtonHiddenForTesting, "hidden while fullscreen")
        chrome.setFullscreen(false)
        XCTAssertFalse(chrome.isFullscreenButtonHiddenForTesting, "shown again on exit")
    }
}
