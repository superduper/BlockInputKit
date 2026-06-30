// Tests/BlockInputKitTests/AppKit/BlockInputContentSurfaceScaffoldTests.swift
import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputContentSurfaceScaffoldTests: XCTestCase {
    func testHostsContentAndDismissesFromMargin() throws {
        let scaffold = BlockInputContentSurfaceScaffold(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let content = NSView()
        scaffold.setContentView(content)
        scaffold.layoutSubtreeIfNeeded()
        XCTAssertTrue(content.isDescendant(of: scaffold), "content is hosted in the card")

        var dismissed = false
        scaffold.onDismiss = { dismissed = true }
        // A click on the dim margin (top-left corner, outside the inset card) dismisses.
        scaffold.handleMarginClickForTesting(at: NSPoint(x: 2, y: 2))
        XCTAssertTrue(dismissed)
    }

    func testDoneButtonDismisses() {
        let scaffold = BlockInputContentSurfaceScaffold(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        var dismissed = false
        scaffold.onDismiss = { dismissed = true }
        scaffold.triggerDoneForTesting()
        XCTAssertTrue(dismissed)
    }
}
