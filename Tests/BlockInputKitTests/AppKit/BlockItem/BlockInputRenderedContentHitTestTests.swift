import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputRenderedContentHitTestTests: XCTestCase {
    func testClickRoutesIntoHostedView() {
        let host = BlockInputRenderedContentBlockView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 60)
        )
        let inner = NSView(frame: host.bounds)  // fills the surface
        host.configureHostedView(inner, cacheKey: "k", style: .default)
        // A point in the content area (away from any button corner) should route to the hosted view,
        // not the host itself.
        let contentPoint = NSPoint(x: 20, y: 30)  // in host's own coords per hitTest convention
        let hit = host.hitTest(contentPoint)
        XCTAssertTrue(
            hit === inner || (inner.isDescendant(of: host) && hit?.isDescendant(of: inner) == true),
            "content-area hit should be the hosted view (or its descendant), got \(String(describing: hit))"
        )
    }

    func testWithoutHostedViewReturnsSelf() {
        let host = BlockInputRenderedContentBlockView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 60)
        )
        // No hosted view: content-area hit returns the host (unchanged behavior).
        XCTAssertTrue(host.hitTest(NSPoint(x: 20, y: 30)) === host)
    }
}
