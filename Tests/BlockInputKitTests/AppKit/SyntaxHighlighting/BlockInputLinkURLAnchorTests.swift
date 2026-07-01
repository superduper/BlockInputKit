import XCTest
@testable import BlockInputKit

final class BlockInputLinkURLAnchorTests: XCTestCase {
    func testAcceptsBareFragmentWhenAllowed() {
        let url = BlockInputLinkURL.supportedURL(from: "#bar", allowsAnchorLinks: true)
        XCTAssertEqual(url?.fragment, "bar")
    }

    func testRejectsBareFragmentWhenNotAllowed() {
        XCTAssertNil(BlockInputLinkURL.supportedURL(from: "#bar", allowsAnchorLinks: false))
    }

    func testEmptyFragmentIsNotALink() {
        XCTAssertNil(BlockInputLinkURL.supportedURL(from: "#", allowsAnchorLinks: true))
    }

    func testSchemedUrlWithFragmentTakesSchemePath() {
        // A real URL with a scheme must NOT be swallowed by the anchor branch.
        let url = BlockInputLinkURL.supportedURL(from: "https://example.com#f", allowsAnchorLinks: true)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "example.com")
    }

    func testMultilineAnchorRejected() {
        XCTAssertNil(BlockInputLinkURL.supportedURL(from: "#a\nb", allowsAnchorLinks: true))
    }
}
