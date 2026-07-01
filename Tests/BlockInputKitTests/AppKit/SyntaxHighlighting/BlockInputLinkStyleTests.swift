import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputLinkStyleTests: XCTestCase {
    func testDefaultsMatchSystemLinkColor() {
        let style = BlockInputStyle.default
        XCTAssertEqual(style.linkForegroundColor, NSColor.linkColor)
        XCTAssertEqual(style.linkUnderlineColor, NSColor.linkColor)
    }

    func testCustomLinkColorIsSettable() {
        var style = BlockInputStyle.default
        style.linkForegroundColor = .systemPurple
        XCTAssertEqual(style.linkForegroundColor, .systemPurple)
    }
}
