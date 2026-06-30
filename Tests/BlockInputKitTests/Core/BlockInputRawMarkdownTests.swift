import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputRawMarkdownTests: XCTestCase {
    func testRawMarkdownBlocksPreserveSourceTextAndNormalizeIndentation() throws {
        let source = "| Name |\n| --- |"
        let block = BlockInputBlock(id: "raw", kind: .rawMarkdown, text: source, indentationLevel: 3)

        XCTAssertEqual(block.text, source)
        XCTAssertEqual(block.indentationLevel, 0)

        let encoded = try JSONEncoder().encode(block)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payload["indentationLevel"] = 2
        let staleEncoded = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(BlockInputBlock.self, from: staleEncoded)

        XCTAssertEqual(decoded.kind, .rawMarkdown)
        XCTAssertEqual(decoded.text, source)
        XCTAssertEqual(decoded.indentationLevel, 0)
    }
}
