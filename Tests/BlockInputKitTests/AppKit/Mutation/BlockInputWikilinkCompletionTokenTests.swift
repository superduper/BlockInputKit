import AppKit
import XCTest
@testable import BlockInputKit

/// `[[` token detection in the completion session: opens a `.wikilink` token, derives the inner query up to `|`, spans
/// the replacement from `[[` to the caret (swallowing a trailing `]]`), and stays closed once `]]` precedes the caret.
@MainActor
final class BlockInputWikilinkCompletionTokenTests: XCTestCase {
    func testTypingOpenBracketsOpensWikilinkTokenWithInnerQuery() async throws {
        let provider = wikilinkProvider()
        _ = try await startCompletion(text: "[[Foo", provider: provider)

        XCTAssertEqual(provider.lastContext?.trigger, .custom("wikilink"))
        XCTAssertEqual(provider.lastContext?.query, "Foo")
        XCTAssertEqual(provider.lastContext?.rawQuery, "Foo")
        XCTAssertEqual(provider.lastContext?.replacementRange, NSRange(location: 0, length: 5))
    }

    func testQueryStopsAtPipe() async throws {
        let provider = wikilinkProvider()
        _ = try await startCompletion(text: "[[Foo|Bar", provider: provider)

        XCTAssertEqual(provider.lastContext?.trigger, .custom("wikilink"))
        XCTAssertEqual(provider.lastContext?.query, "Foo")
        XCTAssertEqual(provider.lastContext?.rawQuery, "Foo|Bar")
        XCTAssertEqual(provider.lastContext?.replacementRange, NSRange(location: 0, length: 9))
    }

    func testReplacementRangeSwallowsTrailingClosingBrackets() async throws {
        // Caret is between the open and close brackets: "[[Foo|]]" with caret after "Foo".
        let provider = wikilinkProvider()
        let text = "[[Foo]]"
        _ = try await startCompletion(text: text, provider: provider, selectedOffset: 5)

        XCTAssertEqual(provider.lastContext?.trigger, .custom("wikilink"))
        XCTAssertEqual(provider.lastContext?.query, "Foo")
        // Replacement spans "[[" through the swallowed trailing "]]".
        XCTAssertEqual(provider.lastContext?.replacementRange, NSRange(location: 0, length: 7))
    }

    func testNoTokenWhenClosingBracketsAlreadyPrecedeCaret() async throws {
        let provider = wikilinkProvider()
        let text = "[[Foo]] "
        let mounted = try await startCompletion(text: text, provider: provider, selectedOffset: (text as NSString).length)

        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(provider.lastContext)
    }

    func testWikilinkTokenDoesNotOpenInsideInlineCode() async throws {
        let provider = wikilinkProvider()
        let text = "`[[Foo`"
        let mounted = try await startCompletion(text: text, provider: provider, selectedOffset: 6)

        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(provider.lastContext)
    }

    private func wikilinkProvider() -> PopupCompletionProvider {
        PopupCompletionProvider(suggestions: [
            BlockInputCompletionSuggestion(
                id: "1",
                title: "Foo Note",
                insertionText: "[[baz/Foo]]",
                trigger: .custom("wikilink")
            )
        ])
    }

    private func startCompletion(
        text: String,
        provider: any BlockInputCompletionProvider,
        selectedOffset: Int? = nil
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        let block = BlockInputBlock(id: "block", kind: .paragraph, text: text)
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [block]),
            completionProvider: provider,
            completionTokenTriggers: [
                BlockInputCompletionTokenTrigger(
                    identifier: "wikilink",
                    openingToken: "[[",
                    closingToken: "]]",
                    abortingSubstrings: ["]]", "[["],
                    query: .beforeFirst(separator: "|")
                )
            ]
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: selectedOffset ?? (text as NSString).length, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: block.id)
        await mounted.view.completionRequestTask?.value
        mounted.view.layoutSubtreeIfNeeded()
        return mounted
    }
}
