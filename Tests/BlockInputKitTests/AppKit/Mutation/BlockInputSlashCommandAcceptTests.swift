import XCTest
import AppKit
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

    @MainActor
    func testConfigurationHandlerIsPlumbedToView() {
        var configuration = BlockInputConfiguration(document: BlockInputDocument(markdown: "hello"))
        configuration.onSlashCommandAccepted = { _ in .none }
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        view.configure(configuration)
        XCTAssertNotNil(view.onSlashCommandAcceptedForTesting)
    }

    @MainActor
    func testReplaceWithMarkdownInsertsCodeBlockAndClearsToken() {
        var configuration = BlockInputConfiguration(document: BlockInputDocument(markdown: "/toc"))
        configuration.onSlashCommandAccepted = { _ in .replaceWithMarkdown("```toc\n```") }
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        view.configure(configuration)
        let blockID = view.documentForTesting.blocks[0].id
        let suggestion = BlockInputCompletionSuggestion.slashCommand(
            id: "toc", title: "TOC", uri: "demo://toc", label: "toc", insertionStyle: .rawToken)

        _ = view.acceptCompletionSuggestion(
            suggestion, in: blockID, replacing: NSRange(location: 0, length: 4))

        let kinds = view.documentForTesting.blocks.map(\.kind)
        XCTAssertTrue(kinds.contains(.code(language: "toc")),
                      "expected a code(toc) block, got \(kinds)")
        XCTAssertFalse(view.documentForTesting.markdown.contains("/toc"),
                       "the typed /toc token must be gone")
    }

    @MainActor
    func testNoneConsumesWithoutInserting() {
        var configuration = BlockInputConfiguration(document: BlockInputDocument(markdown: "/toc"))
        configuration.onSlashCommandAccepted = { _ in .none }
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        view.configure(configuration)
        let blockID = view.documentForTesting.blocks[0].id
        let suggestion = BlockInputCompletionSuggestion.slashCommand(
            id: "toc", title: "TOC", uri: "demo://toc", label: "toc", insertionStyle: .rawToken)
        let before = view.documentForTesting.markdown

        let result = view.acceptCompletionSuggestion(
            suggestion, in: blockID, replacing: NSRange(location: 0, length: 4))

        XCTAssertNil(result)
        XCTAssertEqual(view.documentForTesting.markdown, before)
    }

    @MainActor
    func testInsertTextDefaultWhenNoHandler() {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        view.configure(BlockInputConfiguration(document: BlockInputDocument(markdown: "")))
        let blockID = view.documentForTesting.blocks[0].id
        let suggestion = BlockInputCompletionSuggestion.slashCommand(
            id: "h", title: "Heading", uri: "demo://h", label: "heading", insertionStyle: .rawToken)

        _ = view.acceptCompletionSuggestion(
            suggestion, in: blockID, replacing: NSRange(location: 0, length: 0))

        XCTAssertTrue(view.documentForTesting.blocks[0].text.contains(suggestion.insertionText))
    }

    @MainActor
    func testReplaceWithMarkdownUndoRestoresOriginal() {
        var configuration = BlockInputConfiguration(document: BlockInputDocument(markdown: "/toc"))
        configuration.onSlashCommandAccepted = { _ in .replaceWithMarkdown("```toc\n```") }
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        view.configure(configuration)
        let blockID = view.documentForTesting.blocks[0].id
        let suggestion = BlockInputCompletionSuggestion.slashCommand(
            id: "toc", title: "TOC", uri: "demo://toc", label: "toc", insertionStyle: .rawToken)
        let before = view.documentForTesting.markdown

        _ = view.acceptCompletionSuggestion(
            suggestion, in: blockID, replacing: NSRange(location: 0, length: 4))
        XCTAssertTrue(
            view.documentForTesting.blocks.map(\.kind).contains(.code(language: "toc")),
            "expected a code(toc) block after accept")

        // Single structural edit: token-clear and block insertion are combined.
        view.undoStructuralEdit()

        XCTAssertEqual(
            view.documentForTesting.markdown.trimmingCharacters(in: .whitespacesAndNewlines),
            before.trimmingCharacters(in: .whitespacesAndNewlines),
            "full undo must restore the original /toc text — no silent mutation")
    }

    @MainActor
    func testHandlerNotCalledForMentionTrigger() {
        var called = false
        var configuration = BlockInputConfiguration(document: BlockInputDocument(markdown: ""))
        configuration.onSlashCommandAccepted = { _ in called = true; return .none }
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        view.configure(configuration)
        let blockID = view.documentForTesting.blocks[0].id
        let mention = BlockInputCompletionSuggestion(
            id: "m", title: "Someone", insertionText: "@someone", trigger: .mention)

        _ = view.acceptCompletionSuggestion(mention, in: blockID, replacing: NSRange(location: 0, length: 0))

        XCTAssertFalse(called, "handler must be gated to .slashCommand trigger")
    }

    @MainActor
    func testReplaceWithMarkdownInMultiBlockDocLeavesNoStrayParagraph() {
        // Three-paragraph document: "before", "/toc", "after" as separate blocks.
        let doc = BlockInputDocument(markdown: "before\n\n/toc\n\nafter")
        var configuration = BlockInputConfiguration(document: doc)
        configuration.onSlashCommandAccepted = { _ in .replaceWithMarkdown("```toc\n```") }
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        view.configure(configuration)

        // Locate the block whose text is "/toc".
        let blocks = view.documentForTesting.blocks
        guard let tocBlock = blocks.first(where: { $0.text == "/toc" }) else {
            XCTFail("expected a block with text '/toc', got \(blocks.map(\.text))")
            return
        }
        let suggestion = BlockInputCompletionSuggestion.slashCommand(
            id: "toc", title: "TOC", uri: "demo://toc", label: "toc", insertionStyle: .rawToken)

        _ = view.acceptCompletionSuggestion(
            suggestion, in: tocBlock.id, replacing: NSRange(location: 0, length: 4))

        let resultBlocks = view.documentForTesting.blocks
        let debugDesc = resultBlocks.map { "kind=\($0.kind) text=\($0.text.debugDescription)" }
        XCTAssertEqual(resultBlocks.count, 3,
                       "expected 3 blocks (before / code / after), got \(resultBlocks.count): \(debugDesc)")
        let kinds = resultBlocks.map(\.kind)
        XCTAssertTrue(kinds.contains(.code(language: "toc")),
                      "expected a code(toc) block, got \(kinds)")
        // No stray empty paragraph: the owning block must have been replaced, not left behind.
        XCTAssertFalse(resultBlocks.contains(where: { $0.kind == .paragraph && $0.isEmpty }),
                       "no empty paragraph should remain — stray empty block above code block")
        XCTAssertEqual(resultBlocks[0].text, "before", "first block should be 'before'")
        XCTAssertEqual(resultBlocks[2].text, "after", "last block should be 'after'")
    }

    @MainActor
    func testAcceptContextReceivesExpectedFields() {
        var captured: BlockInputSlashCommandAcceptContext?
        var configuration = BlockInputConfiguration(document: BlockInputDocument(markdown: "/toc"))
        configuration.onSlashCommandAccepted = { context in
            captured = context
            return .none
        }
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        view.configure(configuration)
        let blockID = view.documentForTesting.blocks[0].id
        let suggestion = BlockInputCompletionSuggestion.slashCommand(
            title: "TOC", uri: "demo://toc", label: "toc", insertionStyle: .rawToken)
        let range = NSRange(location: 0, length: 4)

        _ = view.acceptCompletionSuggestion(suggestion, in: blockID, replacing: range)

        XCTAssertEqual(captured?.suggestion.id, "demo://toc",
                       "context must expose the accepted suggestion (id matches uri)")
        XCTAssertEqual(captured?.blockID, blockID,
                       "context must expose the block the suggestion was accepted in")
        XCTAssertEqual(captured?.replacementRange, range,
                       "context must expose the replacement range passed to acceptCompletionSuggestion")
    }
}
