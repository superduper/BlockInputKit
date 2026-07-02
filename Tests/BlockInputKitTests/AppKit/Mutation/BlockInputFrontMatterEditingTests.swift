import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputFrontMatterEditingTests: XCTestCase {
    func testEditingFrontMatterPublishesSnapshotWithKindAndRawBody() throws {
        let frontID = BlockInputBlockID(rawValue: "front")
        var publishedDocument: BlockInputDocument?
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: frontID, kind: .frontMatter, text: "title: Demo")
            ]),
            onDocumentChange: { publishedDocument = $0 }
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "title: Demo\n  nested: true"
        textView.setSelectedRange(NSRange(location: 26, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(publishedDocument?.blocks[0].kind, .frontMatter)
        XCTAssertEqual(publishedDocument?.blocks[0].text, "title: Demo\n  nested: true")
    }

    func testDeleteInEmptyFrontMatterTextViewDeletesBlock() throws {
        let frontID = BlockInputBlockID(rawValue: "front")
        let bodyID = BlockInputBlockID(rawValue: "body")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter),
            BlockInputBlock(id: bodyID, text: "Body")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [bodyID])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: bodyID, utf16Offset: 0)))
    }

    func testDeleteInNonEmptyFrontMatterTextViewRevealsDelimitedMarkdown() throws {
        let frontID = BlockInputBlockID(rawValue: "front")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "title: Demo")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(mounted.view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "---\ntitle: Demo\n---")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: frontID, utf16Offset: 4)))
    }

    func testReturnOnEmptyFrontMatterLineInsertsLineEndingWithoutExitingBlock() throws {
        let frontID = BlockInputBlockID(rawValue: "front")
        let prefix = "title: Demo\n"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "\(prefix)\nslug: demo")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let offset = (prefix as NSString).length
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: frontID, utf16Offset: offset)), notify: false)

        mounted.view.insertBlockBelowCurrentBlock()

        // A blank line in the middle of front matter never escapes the block; only two trailing
        // blank lines at the very end do (see emptyInlineLineRemovalRangeForReturn).
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.frontMatter])
        XCTAssertEqual(mounted.view.document.blocks[0].text, "title: Demo\n\n\nslug: demo")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: frontID, utf16Offset: offset + 1)))
    }

    func testReturnAfterTwoTrailingBlankLinesExitsFrontMatterToParagraphBelow() throws {
        let frontID = BlockInputBlockID(rawValue: "front")
        let text = "title: Demo\n\n"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let offset = (text as NSString).length
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: frontID, utf16Offset: offset)), notify: false)

        mounted.view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.frontMatter, .paragraph])
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["title: Demo", ""])
        let insertedID = mounted.view.document.blocks[1].id
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: insertedID, utf16Offset: 0)))
    }

    func testCompletionInsertionRevalidatesFrontMatterWarningAttributes() throws {
        let frontID = BlockInputBlockID(rawValue: "front")
        let initialText = "title: Demo"
        let insertedText = "\nbad line"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: initialText)
        ])
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: frontID, utf16Offset: (initialText as NSString).length)),
            notify: false
        )

        let selection = mounted.view.acceptCompletionSuggestion(
            BlockInputCompletionSuggestion(id: "invalid", title: "Invalid", insertionText: insertedText, trigger: .mention),
            in: frontID
        )

        let resultingText = initialText + insertedText
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let invalidLineLocation = ("\(initialText)\n" as NSString).length
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: frontID, utf16Offset: (resultingText as NSString).length)))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: invalidLineLocation, effectiveRange: nil) as? NSColor, .systemOrange)
        XCTAssertNotNil(textStorage.attribute(.underlineStyle, at: invalidLineLocation, effectiveRange: nil))
    }

    func testClearingFrontMatterValueRevalidatesWarningAttributes() throws {
        let frontID = BlockInputBlockID(rawValue: "front")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "model: test")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "model:"
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "model:")
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemOrange)
        XCTAssertNotNil(textStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: 5, effectiveRange: nil))
    }
}
