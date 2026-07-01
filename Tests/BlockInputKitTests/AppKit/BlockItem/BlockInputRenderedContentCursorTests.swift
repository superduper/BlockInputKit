import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputRenderedContentCursorTests: XCTestCase {
    func testHostedViewClaimsArrowCursorRect() {
        let host = BlockInputRenderedContentBlockView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 60)
        )
        host.isEditable = true
        let inner = NSView(frame: host.bounds)
        host.configureHostedView(inner, cacheKey: "k", style: .default)
        XCTAssertTrue(host.hasArrowCursorRectForTesting)
    }

    func testNoHostedViewDoesNotClaimArrowCursorRect() {
        let host = BlockInputRenderedContentBlockView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 60)
        )
        host.isEditable = true
        XCTAssertFalse(host.hasArrowCursorRectForTesting)
    }
}
