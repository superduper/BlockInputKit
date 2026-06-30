import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputSlashCompletionPopupTests: XCTestCase {
    func testSlashCommandTokenOpensAtDocumentStartAndBuildsContext() async throws {
        let provider = slashProvider()

        let mounted = try await startCompletion(text: "/tab", provider: provider)

        XCTAssertNotNil(mounted.view.completionPopupView)
        XCTAssertEqual(provider.lastContext?.trigger, .slashCommand)
        XCTAssertEqual(provider.lastContext?.query, "tab")
        XCTAssertEqual(provider.lastContext?.rawQuery, "tab")
        XCTAssertEqual(provider.lastContext?.replacementRange, NSRange(location: 0, length: 4))
        XCTAssertNil(provider.lastContext?.fileQuery)
    }

    func testDocumentStartAvailabilityRejectsLaterBlocksAndLeadingText() async throws {
        let provider = slashProvider()

        let leadingText = try await startCompletion(text: "Run /tab", provider: provider)
        XCTAssertNil(leadingText.view.completionPopupView)

        let secondBlock = try await startCompletion(
            blocks: [
                BlockInputBlock(id: "first", text: "First"),
                BlockInputBlock(id: "second", text: "/tab")
            ],
            selectedBlockIndex: 1,
            provider: provider
        )
        XCTAssertNil(secondBlock.view.completionPopupView)
    }

    func testAnywhereAvailabilityUsesMentionTokenBoundaries() async throws {
        let provider = slashProvider()

        let afterBoundary = try await startCompletion(
            text: "Run /tab",
            provider: provider,
            slashCommandAvailability: .anywhere
        )
        XCTAssertNotNil(afterBoundary.view.completionPopupView)
        XCTAssertEqual(provider.lastContext?.replacementRange, NSRange(location: 4, length: 4))

        let insideWord = try await startCompletion(
            text: "path/to",
            provider: provider,
            slashCommandAvailability: .anywhere
        )
        XCTAssertNil(insideWord.view.completionPopupView)
    }

    func testAcceptingSlashCommandCompletionInsertsChipMarkdownAndRestoresFocus() async throws {
        let provider = slashProvider()
        let mounted = try await startCompletion(text: "/tab", provider: provider)

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        let expectedText = "[/table](host-app://commands/table) "
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [expectedText])
        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(
            blockID: "block",
            utf16Offset: (expectedText as NSString).length
        )))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)

        _ = mounted.view.undoTextEditInActiveBlock()
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["/tab"])
    }

    func testAcceptingRawSlashCommandCompletionPreservesRawMarkdown() async throws {
        let provider = slashProvider(insertionStyle: .rawToken)
        let mounted = try await startCompletion(text: "/tab", provider: provider)

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["/table "])
        XCTAssertEqual(mounted.view.document.markdown, "/table ")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: 7)))

        _ = mounted.view.undoTextEditInActiveBlock()
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["/tab"])
    }

    func testRawSlashCommandCompletionUsesUTF16ReplacementRange() async throws {
        let provider = slashProvider(insertionStyle: .rawToken)
        let mounted = try await startCompletion(
            text: "🙂 /tab",
            provider: provider,
            selectedOffset: ("🙂 /tab" as NSString).length,
            slashCommandAvailability: .anywhere
        )

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["🙂 /table "])
    }

    func testSlashCommandPopupDoesNotOpenInsideInlineCodeLinksOrUnsupportedBlocks() async throws {
        let provider = slashProvider()

        let inlineCode = try await startCompletion(text: "Use `/table`", provider: provider, selectedOffset: 12)
        XCTAssertNil(inlineCode.view.completionPopupView)

        let link = try await startCompletion(text: "Open [/table](host-app://commands/table)", provider: provider, selectedOffset: 12)
        XCTAssertNil(link.view.completionPopupView)

        let code = try await startCompletion(text: "/table", provider: provider, kind: .code(language: nil))
        XCTAssertNil(code.view.completionPopupView)
    }

    private func slashProvider(insertionStyle: BlockInputSlashCommandInsertionStyle = .markdownLink) -> PopupCompletionProvider {
        PopupCompletionProvider(suggestions: [
            .slashCommand(title: "Table", uri: "host-app://commands/table", label: "table", insertionStyle: insertionStyle)
        ])
    }

    private func startCompletion(
        text: String,
        provider: (any BlockInputCompletionProvider)?,
        selectedOffset: Int? = nil,
        slashCommandAvailability: BlockInputSlashCommandAvailability = .documentStart,
        kind: BlockInputBlockKind = .paragraph
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        try await startCompletion(
            blocks: [BlockInputBlock(id: "block", kind: kind, text: text)],
            selectedBlockIndex: 0,
            provider: provider,
            selectedOffset: selectedOffset,
            slashCommandAvailability: slashCommandAvailability
        )
    }

    private func startCompletion(
        blocks: [BlockInputBlock],
        selectedBlockIndex: Int,
        provider: (any BlockInputCompletionProvider)?,
        selectedOffset: Int? = nil,
        slashCommandAvailability: BlockInputSlashCommandAvailability = .documentStart
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: blocks),
            completionProvider: provider,
            slashCommandAvailability: slashCommandAvailability
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: selectedBlockIndex))
        let textView = try XCTUnwrap(item.testingTextView)
        let block = blocks[selectedBlockIndex]
        textView.setSelectedRange(NSRange(location: selectedOffset ?? (block.text as NSString).length, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: block.id)
        await mounted.view.completionRequestTask?.value
        mounted.view.layoutSubtreeIfNeeded()
        return mounted
    }
}
