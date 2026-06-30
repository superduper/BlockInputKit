import XCTest
@testable import BlockInputKit

final class BlockInputSlashCommandCompletionTests: XCTestCase {
    func testSlashCommandSuggestionBuildsMarkdownWithNormalizedSlashLabel() {
        let suggestion = BlockInputCompletionSuggestion.slashCommand(
            title: "Insert table",
            subtitle: "Blocks",
            uri: "demo-command://insert/table?size=2x2",
            label: "table",
            detailText: "Command"
        )

        XCTAssertEqual(suggestion.id, "demo-command://insert/table?size=2x2")
        XCTAssertEqual(suggestion.title, "Insert table")
        XCTAssertEqual(suggestion.subtitle, "Blocks")
        XCTAssertEqual(suggestion.insertionText, "[/table](demo-command://insert/table?size=2x2) ")
        XCTAssertEqual(suggestion.exactMatchText, "/table")
        XCTAssertEqual(suggestion.trigger, .slashCommand)
        XCTAssertEqual(suggestion.iconSystemName, "command")
        XCTAssertEqual(suggestion.detailText, "Command")
    }

    func testSlashCommandSuggestionPreservesExistingSlashLabelAndHostURI() {
        let suggestion = BlockInputCompletionSuggestion.slashCommand(
            id: "command:custom",
            title: "Custom",
            uri: "host-app://run/(custom)",
            label: "/custom"
        )

        XCTAssertEqual(suggestion.id, "command:custom")
        XCTAssertEqual(suggestion.insertionText, "[/custom](host-app://run/\\(custom\\)) ")
        XCTAssertEqual(suggestion.exactMatchText, "/custom")
    }

    func testSlashCommandSuggestionCanInsertRawToken() {
        let suggestion = BlockInputCompletionSuggestion.slashCommand(
            title: "Review GitHub PR",
            uri: "host-app://commands/review-github-pr",
            label: "review-github-pr",
            insertionStyle: .rawToken
        )

        XCTAssertEqual(suggestion.insertionText, "/review-github-pr ")
        XCTAssertEqual(suggestion.exactMatchText, "/review-github-pr")
    }
}
