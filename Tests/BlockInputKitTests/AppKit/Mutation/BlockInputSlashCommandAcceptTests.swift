import XCTest
@testable import BlockInputKit

final class BlockInputSlashCommandAcceptTests: XCTestCase {
    func testAcceptActionIsEquatable() {
        XCTAssertEqual(BlockInputSlashCommandAcceptAction.insertText, .insertText)
        XCTAssertEqual(
            BlockInputSlashCommandAcceptAction.replaceWithMarkdown("```toc\n```"),
            .replaceWithMarkdown("```toc\n```")
        )
        XCTAssertNotEqual(BlockInputSlashCommandAcceptAction.insertText, .none)
    }

    func testAcceptContextExposesFields() {
        let suggestion = BlockInputCompletionSuggestion.slashCommand(
            id: "toc", title: "Table of Contents", uri: "demo://commands/toc",
            label: "toc", insertionStyle: .rawToken
        )
        let context = BlockInputSlashCommandAcceptContext(
            suggestion: suggestion,
            blockID: BlockInputBlockID(rawValue: "test"),
            replacementRange: NSRange(location: 0, length: 4)
        )
        XCTAssertEqual(context.suggestion.id, "toc")
        XCTAssertEqual(context.replacementRange, NSRange(location: 0, length: 4))
    }
}
