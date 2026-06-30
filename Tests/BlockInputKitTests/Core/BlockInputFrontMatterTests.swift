import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputFrontMatterTests: XCTestCase {
    func testFrontMatterBlocksPreserveSourceTextAndNormalizeIndentation() throws {
        let source = "title: Demo\n  nested: true\n"
        let block = BlockInputBlock(id: "front", kind: .frontMatter, text: source, indentationLevel: 3)

        XCTAssertEqual(block.text, source)
        XCTAssertEqual(block.indentationLevel, 0)
        XCTAssertFalse(BlockInputDocument(blocks: [block]).isEffectivelyEmpty)

        let encoded = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(BlockInputBlock.self, from: encoded)

        XCTAssertEqual(decoded.kind, .frontMatter)
        XCTAssertEqual(decoded.text, source)
        XCTAssertEqual(decoded.indentationLevel, 0)
    }

    func testFrontMatterValidationIssuesAreAdvisoryAndLineBased() {
        let block = BlockInputBlock(kind: .frontMatter, text: """
        : missing
          orphan
        title: Demo
        title: Duplicate
        ---
        invalid
        """)

        XCTAssertEqual(block.frontMatterValidationIssues, [
            BlockInputFrontMatterValidationIssue(lineIndex: 0, kind: .emptyKey),
            BlockInputFrontMatterValidationIssue(lineIndex: 1, kind: .orphanIndentedLine),
            BlockInputFrontMatterValidationIssue(lineIndex: 3, kind: .duplicateKey),
            BlockInputFrontMatterValidationIssue(lineIndex: 4, kind: .delimiterInBody),
            BlockInputFrontMatterValidationIssue(lineIndex: 5, kind: .invalidTopLevelLine)
        ])
    }

    func testFrontMatterValidationFlagsEmptyScalarValuesButAllowsContinuations() {
        let block = BlockInputBlock(kind: .frontMatter, text: """
        name:
        tags:
          - swift
        description:
          nested: true
        model: test
        """)

        XCTAssertEqual(block.frontMatterValidationIssues, [
            BlockInputFrontMatterValidationIssue(lineIndex: 0, kind: .emptyValue)
        ])
    }

    func testEmptyFrontMatterCanExitToParagraphOrDelete() {
        let frontID = BlockInputBlockID(rawValue: "front")
        var returnDocument = BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter)
        ])

        let returnSelection = returnDocument.handleReturn(in: frontID)

        XCTAssertEqual(returnDocument.blocks[0].kind, .paragraph)
        XCTAssertEqual(returnSelection, .cursor(BlockInputCursor(blockID: frontID, utf16Offset: 0)))

        var deleteDocument = BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter),
            BlockInputBlock(id: "body", text: "Body")
        ])

        let deleteSelection = deleteDocument.deleteEmptyBlockForBackspaceOrDelete(blockID: frontID)

        XCTAssertEqual(deleteDocument.blocks.map(\.id), ["body"])
        XCTAssertEqual(deleteSelection, .cursor(BlockInputCursor(blockID: "body", utf16Offset: 0)))
    }

    func testFrontMatterMidBlockBlankLineReturnInsertsNewlineWithoutExiting() {
        // A blank line in the MIDDLE of an inline block must never escape; Return inserts a newline.
        let frontID = BlockInputBlockID(rawValue: "front")
        let prefix = "title: Demo\n"
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "\(prefix)\nslug: demo")
        ])

        let selection = document.handleReturn(in: frontID, utf16Offset: (prefix as NSString).length)

        XCTAssertEqual(document.blocks.map(\.kind), [.frontMatter])
        XCTAssertEqual(document.blocks.map(\.text), ["title: Demo\n\n\nslug: demo"])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: frontID, utf16Offset: (prefix as NSString).length + 1)))
    }

    func testFrontMatterEscapesAfterTwoTrailingBlankLinesAtEnd() {
        // Two trailing blank lines plus a caret at the very end escape to a paragraph below,
        // dropping the trailing blanks; real content above is preserved as frontmatter.
        let frontID = BlockInputBlockID(rawValue: "front")
        let text = "title: Demo\n\n"
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: text)
        ])

        let selection = document.handleReturn(in: frontID, utf16Offset: (text as NSString).length)

        XCTAssertEqual(document.blocks.map(\.kind), [.frontMatter, .paragraph])
        XCTAssertEqual(document.blocks.map(\.text), ["title: Demo", ""])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: document.blocks[1].id, utf16Offset: 0)))
    }

    func testUnwrapFrontMatterRevealsDelimitedMarkdownForRecovery() {
        let frontID = BlockInputBlockID(rawValue: "front")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "title: Demo")
        ])

        let selection = document.unwrapBlockToParagraph(blockID: frontID)

        XCTAssertEqual(document.blocks[0].kind, .paragraph)
        XCTAssertEqual(document.blocks[0].text, "---\ntitle: Demo\n---")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: frontID, utf16Offset: 4)))
    }

    func testParagraphDoesNotMergeIntoFrontMatter() {
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: paragraphID, text: "Body")
        ])

        XCTAssertNil(document.mergeBlockIntoPrevious(blockID: paragraphID))
        XCTAssertEqual(document.blocks.map(\.text), ["title: Demo", "Body"])
    }

    func testMixedSelectionDoesNotMergeBodyTextIntoFrontMatter() {
        let frontID = BlockInputBlockID(rawValue: "front")
        let bodyID = BlockInputBlockID(rawValue: "body")
        let frontText = "title: Demo\nslug: demo"
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: frontText),
            BlockInputBlock(id: bodyID, text: "Body paragraph")
        ])

        let cursor = document.deleteMixedSelection(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(
                blockID: frontID,
                range: NSRange(location: 7, length: (frontText as NSString).length - 7)
            ),
            trailingTextRange: BlockInputTextRange(
                blockID: bodyID,
                range: NSRange(location: 0, length: 5)
            )
        ))

        XCTAssertEqual(cursor, BlockInputCursor(blockID: frontID, utf16Offset: 7))
        XCTAssertEqual(document.blocks.map(\.kind), [.frontMatter, .paragraph])
        XCTAssertEqual(document.blocks.map(\.text), ["title: ", "paragraph"])
    }

    func testMixedSelectionDoesNotMergeMisplacedFrontMatterIntoBodyText() {
        let bodyID = BlockInputBlockID(rawValue: "body")
        let frontID = BlockInputBlockID(rawValue: "front")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: bodyID, text: "Body paragraph"),
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "title: Demo")
        ])

        let cursor = document.deleteMixedSelection(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(
                blockID: bodyID,
                range: NSRange(location: 5, length: 9)
            ),
            trailingTextRange: BlockInputTextRange(
                blockID: frontID,
                range: NSRange(location: 0, length: 7)
            )
        ))

        XCTAssertEqual(cursor, BlockInputCursor(blockID: bodyID, utf16Offset: 5))
        XCTAssertEqual(document.blocks.map(\.kind), [.paragraph, .frontMatter])
        XCTAssertEqual(document.blocks.map(\.text), ["Body ", "Demo"])
    }

    func testFrontMatterCannotBeMovedAwayFromDocumentStart() {
        let frontID = BlockInputBlockID(rawValue: "front")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "body", text: "Body")
        ])

        XCTAssertNil(document.moveBlock(blockID: frontID, to: 1))
        XCTAssertNil(document.moveBlock(blockID: "body", to: 0))
        XCTAssertEqual(document.blocks.map(\.id), [frontID, "body"])
    }

    func testNonLeadingFrontMatterCanBeMovedBackToDocumentStart() {
        let frontID = BlockInputBlockID(rawValue: "front")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "body", text: "Body"),
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "title: Demo")
        ])

        let selection = document.moveBlock(blockID: frontID, to: 0)

        XCTAssertEqual(document.blocks.map(\.id), [frontID, "body"])
        XCTAssertEqual(selection, .blocks([frontID]))
    }

    func testDuplicateFrontMatterCannotDisplaceExistingLeadingFrontMatter() {
        let leadingID = BlockInputBlockID(rawValue: "leading")
        let duplicateID = BlockInputBlockID(rawValue: "duplicate")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: leadingID, kind: .frontMatter, text: "title: Leading"),
            BlockInputBlock(id: "body", text: "Body"),
            BlockInputBlock(id: duplicateID, kind: .frontMatter, text: "title: Duplicate")
        ])

        XCTAssertNil(document.moveBlock(blockID: duplicateID, to: 0))
        XCTAssertEqual(document.blocks.map(\.id), [leadingID, "body", duplicateID])
    }
}
