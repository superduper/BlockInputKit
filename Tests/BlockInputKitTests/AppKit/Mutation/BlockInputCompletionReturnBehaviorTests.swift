import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCompletionReturnBehaviorTests: XCTestCase {
    func testReturnAcceptsExactMatchByDefault() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            exactMentionSuggestion("@read")
        ])
        let mounted = try await startCompletion(text: "@read", provider: provider)

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["@read"])
        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(mounted.view.completionSession)
    }

    func testReturnPassesThroughExactMatchWhenConfigured() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            exactMentionSuggestion("@read")
        ])
        let mounted = try await startCompletion(
            text: "@read",
            provider: provider,
            completionReturnBehavior: .passthroughExactMatch
        )

        XCTAssertFalse(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["@read"])
        XCTAssertNotNil(mounted.view.completionPopupView)
        XCTAssertNotNil(mounted.view.completionSession)
    }

    func testReturnPassthroughUsesSuggestionExactMatchText() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            BlockInputCompletionSuggestion(
                id: "read",
                title: "Read",
                insertionText: "@read ",
                exactMatchText: "@read",
                trigger: .mention
            )
        ])
        let mounted = try await startCompletion(
            text: "@read",
            provider: provider,
            completionReturnBehavior: .passthroughExactMatch
        )

        XCTAssertFalse(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["@read"])
        XCTAssertNotNil(mounted.view.completionPopupView)
    }

    func testReturnPassthroughMatchesSlashCommandTokenWithoutTrailingInsertionSpace() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            BlockInputCompletionSuggestion.slashCommand(
                title: "review-github-pr",
                uri: "demo-command://review-github-pr",
                insertionStyle: .rawToken
            )
        ])
        let mounted = try await startCompletion(
            text: "/review-github-pr",
            provider: provider,
            completionReturnBehavior: .passthroughExactMatch
        )

        XCTAssertFalse(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["/review-github-pr"])
        XCTAssertNotNil(mounted.view.completionPopupView)
    }

    func testReturnPassthroughRunsHostShortcut() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            exactMentionSuggestion("@read")
        ])
        var handledReturnCount = 0
        let mounted = try await startCompletion(
            text: "@read",
            provider: provider,
            completionReturnBehavior: .passthroughExactMatch,
            keyboardShortcuts: [
                .returnKey: { _ in
                    handledReturnCount += 1
                    return .handled
                }
            ]
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(handledReturnCount, 1)
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["@read"])
        XCTAssertNotNil(mounted.view.completionPopupView)
    }

    func testReturnPassthroughRunsBuiltInReturnBehavior() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            exactMentionSuggestion("@read")
        ])
        let mounted = try await startCompletion(
            text: "@read",
            provider: provider,
            completionReturnBehavior: .passthroughExactMatch
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertEqual(mounted.view.document.blocks.first?.text, "@read")
        let insertedBlock = try XCTUnwrap(mounted.view.document.blocks.last)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: insertedBlock.id, utf16Offset: 0)))
    }

    func testReturnAcceptsPartialMatchWhenExactMatchPassthroughIsConfigured() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            exactMentionSuggestion("@read ")
        ])
        let mounted = try await startCompletion(
            text: "@rea",
            provider: provider,
            completionReturnBehavior: .passthroughExactMatch
        )

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["@read "])
        XCTAssertNil(mounted.view.completionPopupView)
    }

    func testTabAcceptsExactMatchWhenReturnPassthroughIsConfigured() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            exactMentionSuggestion("@read")
        ])
        let mounted = try await startCompletion(
            text: "@read",
            provider: provider,
            completionReturnBehavior: .passthroughExactMatch
        )

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertTab(_:))))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["@read"])
        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(mounted.view.completionSession)
    }

    func testReturnPassthroughProtectsOutOfRangeReplacement() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            exactMentionSuggestion("@read")
        ])
        let mounted = try await startCompletion(
            text: "@read",
            provider: provider,
            completionReturnBehavior: .passthroughExactMatch
        )
        mounted.view.completionSession?.token.replacementRange = NSRange(location: 99, length: 4)

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["@read"])
        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(mounted.view.completionSession)
    }

    private func startCompletion(
        text: String,
        provider: any BlockInputCompletionProvider,
        completionReturnBehavior: BlockInputCompletionReturnBehavior = .acceptHighlightedSuggestion,
        keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:]
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            keyboardShortcuts: keyboardShortcuts,
            completionProvider: provider,
            completionReturnBehavior: completionReturnBehavior
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: "block")
        await mounted.view.completionRequestTask?.value
        mounted.view.layoutSubtreeIfNeeded()
        return mounted
    }

    private func exactMentionSuggestion(_ text: String) -> BlockInputCompletionSuggestion {
        BlockInputCompletionSuggestion(
            id: text,
            title: text,
            insertionText: text,
            trigger: .mention
        )
    }
}
