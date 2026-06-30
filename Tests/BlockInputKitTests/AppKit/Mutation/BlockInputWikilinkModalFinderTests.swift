import AppKit
import XCTest
@testable import BlockInputKit

/// The wikilink Edit modal's "Target" field is a fuzzy note finder driven by the SAME completion engine as the inline
/// `[[` finder: typing routes a `.wikilink` query through `completionProvider`, the shared popup presents the ranked
/// rows anchored to the Target field, and accepting a row fills the Target slug + (empty) Title so Save round-trips
/// `[[slug|title]]`. Regular `[label](url)` modals stay plain.
@MainActor
final class BlockInputWikilinkModalFinderTests: XCTestCase {
    func testTypingInTargetFieldQueriesProviderAndPresentsPopup() async throws {
        let provider = PopupCompletionProvider(suggestions: [wikilinkSuggestion()])
        let mounted = mountWikilinkModal(provider: provider)
        let modal = try XCTUnwrap(mounted.view.linkModalView)

        try await type("Foo", in: modal, view: mounted.view)

        XCTAssertEqual(provider.lastContext?.trigger, .custom("wikilink"))
        XCTAssertEqual(provider.lastContext?.query, "Foo")
        let popup = try XCTUnwrap(mounted.view.modalCompletionPopupView)
        XCTAssertNotNil(popup.superview)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["Foo note title"])
        // The inline `[[` finder was not started; only the modal finder is active.
        XCTAssertNil(mounted.view.completionPopupView)
    }

    func testAcceptingSuggestionFillsTargetSlugAndEmptyTitleThenSaveRoundTrips() async throws {
        let provider = PopupCompletionProvider(suggestions: [wikilinkSuggestion()])
        let mounted = mountWikilinkModal(provider: provider, text: "Open [[Old]] here", slug: "Old")
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        // Clear the auto-filled Title so the accept path can populate it from the picked note.
        modal.textField.stringValue = ""

        try await type("Foo", in: modal, view: mounted.view)
        XCTAssertTrue(mounted.view.handleModalCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        // Accept filled the slug + the previously empty Title, and dismissed the finder popup.
        XCTAssertEqual(modal.urlField.stringValue, "baz/Foo")
        XCTAssertEqual(modal.textField.stringValue, "Foo note title")
        XCTAssertTrue(modal.saveButton.isEnabled)
        XCTAssertNil(mounted.view.modalCompletionPopupView)

        modal.saveButton.performClick(nil)
        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Open [[baz/Foo|Foo note title]] here")
    }

    func testAcceptKeepsExistingNonEmptyTitle() async throws {
        let provider = PopupCompletionProvider(suggestions: [wikilinkSuggestion()])
        let mounted = mountWikilinkModal(provider: provider)
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        modal.textField.stringValue = "Custom"

        try await type("Foo", in: modal, view: mounted.view)
        XCTAssertTrue(mounted.view.handleModalCompletionCommand(#selector(NSResponder.insertTab(_:))))

        XCTAssertEqual(modal.urlField.stringValue, "baz/Foo")
        XCTAssertEqual(modal.textField.stringValue, "Custom")
    }

    func testEscapeClosesPopupButNotModal() async throws {
        let provider = PopupCompletionProvider(suggestions: [wikilinkSuggestion()])
        let mounted = mountWikilinkModal(provider: provider)
        let modal = try XCTUnwrap(mounted.view.linkModalView)

        try await type("Foo", in: modal, view: mounted.view)
        XCTAssertNotNil(mounted.view.modalCompletionPopupView)

        XCTAssertTrue(mounted.view.handleModalCompletionCommand(#selector(NSResponder.cancelOperation(_:))))
        XCTAssertNil(mounted.view.modalCompletionPopupView)
        XCTAssertNotNil(mounted.view.linkModalView)
    }

    func testRegularLinkModalDoesNotStartNoteFinder() async throws {
        let provider = PopupCompletionProvider(suggestions: [wikilinkSuggestion()])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: "See [docs](https://example.com) end")]),
            completionProvider: provider
        ))
        let text = "See [docs](https://example.com) end"
        let link = try XCTUnwrap(linkRange(in: text))
        let context = BlockInputLinkContext(
            blockID: "block",
            mode: .edit(link),
            sourceRange: link.fullRange,
            sourceText: text,
            anchorWindowRect: .zero
        )
        mounted.view.showLinkModal(context: context)
        let modal = try XCTUnwrap(mounted.view.linkModalView)

        modal.urlField.stringValue = "Foo"
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.urlField))
        await mounted.view.modalCompletionRequestTask?.value

        XCTAssertNil(mounted.view.modalCompletionPopupView)
        XCTAssertNil(provider.lastContext)
    }

    // MARK: - Helpers

    /// A `.custom("wikilink")` suggestion whose Target fills from `exactMatchText` (the bare slug) and Title from `title`,
    /// so accepting it fills Target=`baz/Foo` and Title=`Foo note title` and Save round-trips `[[baz/Foo|Foo note title]]`.
    private func wikilinkSuggestion() -> BlockInputCompletionSuggestion {
        BlockInputCompletionSuggestion(
            id: "1",
            title: "Foo note title",
            subtitle: "baz/Foo",
            insertionText: "[[baz/Foo|Foo note title]]",
            exactMatchText: "baz/Foo",
            trigger: .custom("wikilink")
        )
    }

    private func mountWikilinkModal(
        provider: any BlockInputCompletionProvider,
        text: String = "Open [[baz/Foo|Foo]] here",
        slug: String = "baz/Foo",
        alias: String? = "Foo"
    ) -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            completionProvider: provider,
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()]
        ))
        guard let wikilink = wikilinkRange(in: text),
              let identity = wikilink.style.customMarkupIdentity else {
            return mounted
        }
        _ = mounted.view.showCustomMarkupModalIfAvailable(blockID: "block", range: wikilink, identity: identity)
        return mounted
    }

    private func type(_ query: String, in modal: BlockInputLinkModalView, view: BlockInputView) async throws {
        modal.urlField.stringValue = query
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.urlField))
        await view.modalCompletionRequestTask?.value
        view.layoutSubtreeIfNeeded()
    }

    private func wikilinkRange(in text: String) -> BlockInputInlineMarkdownRange? {
        WikilinkStandInMarkupProvider.wikilinkRange(in: text)
    }

    private func linkRange(in text: String) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        )
        .first { $0.style == .link }
    }
}
