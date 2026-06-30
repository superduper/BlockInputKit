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
}
