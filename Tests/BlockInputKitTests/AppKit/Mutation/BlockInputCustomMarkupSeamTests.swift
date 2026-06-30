import AppKit
import XCTest
@testable import BlockInputKit

/// Generic Sub-step B seams, exercised WITHOUT any wikilink grammar: a trivial `@@target@@` markup provider, a
/// `BlockInputCompletionTokenTrigger("@@")`, and a trivial rewriter. Proves that custom markup click routing, the custom
/// completion trigger, and the async rewriter all fire for a registered, non-wikilink markup.
@MainActor
final class BlockInputCustomMarkupSeamTests: XCTestCase {
    // MARK: - (a) Clicking the `@@` markup routes to inlineLinkClickHandler with kind .customMarkup and decoded target

    func testDoubleClickOnCustomMarkupRoutesToHandlerWithDecodedTarget() throws {
        var captured: BlockInputInlineLinkClickContext?
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open @@baz/Foo@@ here")
            ]),
            inlineMarkupProviders: [AtMarkupProvider()],
            inlineLinkClickHandler: { context in
                captured = context
                return .hostHandled
            }
        ))
        let textView = try textView(in: mounted.view)
        let innerOffset = ("Open @@baz/Foo@@ here" as NSString).range(of: "baz/Foo").location
        let location = try windowLocation(forUTF16Offset: innerOffset, in: textView)
        let markupRange = try XCTUnwrap(customMarkupRange(in: "Open @@baz/Foo@@ here"))

        // Single click on the body only places the caret (does not route).
        XCTAssertFalse(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: innerOffset, length: 0),
            clickedLinkRange: markupRange,
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertNil(captured)

        // Double click routes to the host handler with kind .customMarkup("at") and the decoded target.
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: innerOffset, length: 0),
            clickedLinkRange: markupRange,
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, clickCount: 2)
        ))
        let context = try XCTUnwrap(captured)
        XCTAssertEqual(context.kind, .customMarkup("at"))
        XCTAssertEqual(context.destination.scheme, "at")
        // Destination is `at:<percent-encoded primary>`, which decodes back to the stored target.
        let decoded = context.destination.absoluteString
            .replacingOccurrences(of: "at:", with: "")
            .removingPercentEncoding
        XCTAssertEqual(decoded, "baz/Foo")
        XCTAssertEqual(context.label, "baz/Foo")
    }

    // MARK: - (b) The `@@` trigger opens completion with .custom("at")

    func testCustomTokenTriggerOpensCompletionWithCustomTrigger() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            BlockInputCompletionSuggestion(id: "1", title: "Foo", insertionText: "@@Foo@@", trigger: .custom("at"))
        ])
        let block = BlockInputBlock(id: "block", kind: .paragraph, text: "@@Foo")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [block]),
            completionProvider: provider,
            completionTokenTriggers: [
                BlockInputCompletionTokenTrigger(
                    identifier: "at",
                    openingToken: "@@",
                    closingToken: "@@",
                    abortingSubstrings: ["@@"],
                    query: .verbatim
                )
            ]
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: block.id)
        await mounted.view.completionRequestTask?.value

        XCTAssertEqual(provider.lastContext?.trigger, .custom("at"))
        XCTAssertEqual(provider.lastContext?.query, "Foo")
        XCTAssertEqual(provider.lastContext?.replacementRange, NSRange(location: 0, length: 5))
    }

    // MARK: - (c) The rewriter rewrites a matching block's source once, undoably

    func testRewriterRewritesMatchingBlockOnceUndoably() throws {
        let rewriter = AtRewriter()
        var configuration = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: "Open @@Foo@@ here")]),
            undoController: BlockInputUndoController()
        )
        configuration.inlineMarkupRewriters = [rewriter]
        let rewritten = expectation(description: "block rewritten by the at-rewriter")
        var observed = false
        configuration.onDocumentChange = { document in
            guard !observed, document.blocks.first?.text == "Open @@Foo!@@ here" else {
                return
            }
            observed = true
            rewritten.fulfill()
        }
        let mounted = makeMountedBlockInputView(configuration: configuration)
        wait(for: [rewritten], timeout: 2)
        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Open @@Foo!@@ here")
        // The matching source is rewritten exactly once; the rewriter then returns nil for the new text, so the
        // "unchanged/no-match ⇒ skip" guard stops it (the count stays bounded — no resolver loop).
        XCTAssertEqual(rewriter.matchingRewriteCount, 1, "A rewriter whose result no longer matches must not loop")

        // The rewrite is one undoable structural mutation: undo restores the original source.
        XCTAssertNotNil(mounted.view.undoStructuralEdit())
        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Open @@Foo@@ here")
    }

    // MARK: - Helpers

    private func customMarkupRange(in text: String) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange),
            inlineMarkupProviders: [AtMarkupProvider()]
        )
        .first { if case .customMarkup = $0.style { return true } else { return false } }
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }
}

/// A trivial custom markup: `@@target@@`. The visible content is the inner target; the `@@` pairs are hidden chrome.
private struct AtMarkupProvider: BlockInputInlineMarkupProvider {
    let identifier = "at"

    func spans(in text: String, excluding excludedRanges: [NSRange]) -> [BlockInputInlineMarkupSpan] {
        let nsText = text as NSString
        var spans: [BlockInputInlineMarkupSpan] = []
        var searchStart = 0
        while searchStart < nsText.length {
            let openRange = nsText.range(of: "@@", range: NSRange(location: searchStart, length: nsText.length - searchStart))
            guard openRange.location != NSNotFound else { break }
            let innerStart = NSMaxRange(openRange)
            let closeRange = nsText.range(of: "@@", range: NSRange(location: innerStart, length: nsText.length - innerStart))
            guard closeRange.location != NSNotFound, closeRange.location > innerStart else {
                searchStart = NSMaxRange(openRange)
                continue
            }
            let contentRange = NSRange(location: innerStart, length: closeRange.location - innerStart)
            let fullRange = NSRange(location: openRange.location, length: NSMaxRange(closeRange) - openRange.location)
            let target = nsText.substring(with: contentRange)
            spans.append(BlockInputInlineMarkupSpan(
                fullRange: fullRange,
                contentRange: contentRange,
                hiddenRanges: [openRange, NSRange(location: closeRange.location, length: 2)],
                style: BlockInputInlineMarkupStyle(foregroundColor: .systemPink, underlines: true, showsOpenIcon: true),
                payload: BlockInputInlineMarkupPayload(primary: target)
            ))
            searchStart = NSMaxRange(closeRange)
        }
        return spans
    }
}

/// A trivial rewriter that appends `!` to an `@@Foo@@` target once; the rewritten `@@Foo!@@` no longer matches, so the
/// "result == input ⇒ skip" guard stops it after one pass.
private final class AtRewriter: BlockInputInlineMarkupRewriter, @unchecked Sendable {
    let identifier = "at"
    let rewriteActionName = "Expand Markup"
    /// Counts only the calls that actually matched and produced a rewrite, so re-runs for the already-rewritten text
    /// (which return nil) are not conflated with a loop.
    private(set) var matchingRewriteCount = 0

    @MainActor
    func rewrittenSource(for text: String, blockID: BlockInputBlockID) async -> String? {
        guard text == "Open @@Foo@@ here" else {
            return nil
        }
        matchingRewriteCount += 1
        return "Open @@Foo!@@ here"
    }
}
