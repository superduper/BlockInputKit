import XCTest
@testable import BlockInputKit

final class BlockInputCodeParsingTests: XCTestCase {
    func testInlineCodeRangesSeparateContentFromSingleBacktickDelimiters() {
        let ranges = BlockInputCodeParsing.inlineCodeRanges(in: "Use `git status` here")

        XCTAssertEqual(ranges, [
            BlockInputInlineCodeRange(
                fullRange: NSRange(location: 4, length: 12),
                contentRange: NSRange(location: 5, length: 10),
                delimiterRanges: [
                    NSRange(location: 4, length: 1),
                    NSRange(location: 15, length: 1)
                ]
            )
        ])
    }

    func testInlineCodeRangesIgnoreUnmatchedAndEmptySpans() {
        XCTAssertEqual(BlockInputCodeParsing.inlineCodeRanges(in: "Use `git status"), [])
        XCTAssertEqual(BlockInputCodeParsing.inlineCodeRanges(in: "Use `` here"), [])
    }

    func testInlineCodeRangesDoNotCrossLineBoundaries() {
        XCTAssertEqual(BlockInputCodeParsing.inlineCodeRanges(in: "Use `git\nstatus` here"), [])
    }

    func testInlineCodeRangesIgnoreMultiBacktickDelimiters() {
        XCTAssertEqual(BlockInputCodeParsing.inlineCodeRanges(in: "Use ``git status`` here"), [])
    }

    func testInlineCodeRangesFindMultipleSpans() {
        let ranges = BlockInputCodeParsing.inlineCodeRanges(in: "`one` and `two`")

        XCTAssertEqual(ranges.map(\.contentRange), [
            NSRange(location: 1, length: 3),
            NSRange(location: 11, length: 3)
        ])
    }

    func testCodeFenceOpeningParsesOptionalLanguage() {
        XCTAssertEqual(BlockInputCodeParsing.codeFenceOpening(in: "```"), BlockInputCodeFenceOpening(language: nil))
        XCTAssertEqual(BlockInputCodeParsing.codeFenceOpening(in: "```swift"), BlockInputCodeFenceOpening(language: "swift"))
        XCTAssertEqual(BlockInputCodeParsing.codeFenceOpening(in: "``` swift "), BlockInputCodeFenceOpening(language: "swift"))
        XCTAssertEqual(BlockInputCodeParsing.codeFenceOpening(in: "  ```swift  "), BlockInputCodeFenceOpening(language: "swift"))
    }

    func testCodeFenceOpeningRejectsNonFenceTextAndLongerFences() {
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "before ```swift"))
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "`swift"))
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "````swift"))
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "``` `swift"))
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "```swift`"))
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "```\nswift"))
    }
}
