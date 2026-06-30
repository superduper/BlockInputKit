import XCTest
@testable import BlockInputKit

final class BlockInputHeadingSlugTests: XCTestCase {
    func testBasic() { XCTAssertEqual(BlockInputHeadingSlug.make("Foo Bar"), "foo-bar") }
    func testPunctuationStripped() { XCTAssertEqual(BlockInputHeadingSlug.make("Hello, World!"), "hello-world") }
    func testCollapsesAndTrimsDashes() { XCTAssertEqual(BlockInputHeadingSlug.make("  A  --  B  "), "a-b") }
    func testKeepsDigits() { XCTAssertEqual(BlockInputHeadingSlug.make("Step 2"), "step-2") }
    func testEmptyForPunctuationOnly() { XCTAssertEqual(BlockInputHeadingSlug.make("!!!"), "") }
}
