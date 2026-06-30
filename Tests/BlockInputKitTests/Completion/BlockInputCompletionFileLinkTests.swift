import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputCompletionFileLinkTests: XCTestCase {
    func testFileLinkSuggestionBuildsEscapedMarkdownLinkFollowedBySpace() {
        let suggestion = BlockInputCompletionSuggestion.fileLink(
            label: "../Docs/[Draft] (1).md",
            fileURL: URL(fileURLWithPath: "/tmp/Docs/[Draft] (1).md"),
            detailText: "/tmp/Docs"
        )

        XCTAssertEqual(suggestion.title, "../Docs/[Draft] (1).md")
        XCTAssertEqual(suggestion.insertionText, "[../Docs/\\[Draft\\] (1).md](file:///tmp/Docs/%5BDraft%5D%20\\(1\\).md) ")
        XCTAssertNil(suggestion.exactMatchText)
        XCTAssertEqual(suggestion.trigger, .mention)
        XCTAssertEqual(suggestion.iconSystemName, "doc.text")
        XCTAssertEqual(suggestion.detailText, "/tmp/Docs")
    }

    func testFileLinkSuggestionDefaultsLabelToFileName() {
        let suggestion = BlockInputCompletionSuggestion.fileLink(
            fileURL: URL(fileURLWithPath: "/tmp/Docs/[Draft] (1).md")
        )

        XCTAssertEqual(suggestion.title, "[Draft] (1).md")
        XCTAssertEqual(suggestion.insertionText, "[\\[Draft\\] (1).md](file:///tmp/Docs/%5BDraft%5D%20\\(1\\).md) ")
    }

    @MainActor
    func testAcceptFileLinkCompletionInsertsHelperTextVerbatimBeforeExistingWhitespace() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Open @read docs")
        ])))

        let selection = view.acceptCompletionSuggestion(
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md")),
            in: blockID,
            replacing: NSRange(location: 5, length: 5)
        )

        let acceptedPrefix = "Open [README.md](file:///tmp/README.md) "
        let expectedText = acceptedPrefix + " docs"
        XCTAssertEqual(view.document.blocks[0].text, expectedText)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: (acceptedPrefix as NSString).length
        )))
    }
}
