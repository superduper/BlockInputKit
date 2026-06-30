import AppKit
import XCTest
@testable import BlockInputKit

/// Final wikilink title model: the alias (or the bare slug) is the only visible, styled text; the surrounding chrome
/// (`[[`/`]]` and an aliased `target|`) is hidden via the null-glyph delimiter mechanism. Covers single-line layout,
/// plain-click routing with the slug target, editing the alias, and no reveal-on-edit for regular links.
@MainActor
final class BlockInputWikilinkRenderingTests: XCTestCase {
    // MARK: - (a) `[[Foo]]` shows the slug styled with the brackets hidden

    func testPlainWikilinkShowsSlugWithBracketsHidden() throws {
        let text = "See [[Foo]] now"
        let storage = styledStorage(for: text)
        let wikilink = try XCTUnwrap(wikilinkRange(in: text))

        XCTAssertEqual(content(in: text, range: wikilink.fullRange), "[[Foo]]")
        XCTAssertNil(wikilink.style.customMarkupIdentity?.payload.secondary)
        XCTAssertEqual(wikilink.style.customMarkupIdentity?.payload.primary, "Foo")
        // Visible content is the slug only; the brackets are the hidden ranges.
        XCTAssertEqual(content(in: text, range: wikilink.contentRange), "Foo")
        XCTAssertEqual(wikilink.delimiterRanges.map { content(in: text, range: $0) }, ["[[", "]]"])
        XCTAssertEqual(hiddenRanges(in: storage).map { content(in: text, range: $0) }, ["[[", "]]"])
        // The visible slug is styled as an accent link (foreground + single underline).
        let attributes = storage.attributes(at: wikilink.contentRange.location, effectiveRange: nil)
        XCTAssertEqual(attributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNotNil(attributes[.foregroundColor])
    }

    // MARK: - (b) `[[Foo|Bar]]` shows `Bar`; `[[Foo|` and `]]` hidden via `.blockInputHiddenDelimiter`

    func testAliasedWikilinkShowsAliasWithSlugAndBracketsHidden() throws {
        let text = "See [[Foo|Bar]] now"
        let storage = styledStorage(for: text)
        let wikilink = try XCTUnwrap(wikilinkRange(in: text))

        XCTAssertEqual(wikilink.style.customMarkupIdentity?.payload.secondary, "Bar")
        XCTAssertEqual(wikilink.style.customMarkupIdentity?.payload.primary, "Foo")
        // Visible content is the alias only.
        XCTAssertEqual(content(in: text, range: wikilink.contentRange), "Bar")
        // Hidden chrome is `[[Foo|` (opening brackets through the pipe) plus the closing `]]`.
        XCTAssertEqual(wikilink.delimiterRanges.map { content(in: text, range: $0) }, ["[[Foo|", "]]"])
        XCTAssertEqual(hiddenRanges(in: storage).map { content(in: text, range: $0) }, ["[[Foo|", "]]"])
        // The visible alias keeps the accent styling.
        let aliasLocation = (text as NSString).range(of: "Bar").location
        let aliasAttributes = storage.attributes(at: aliasLocation, effectiveRange: nil)
        XCTAssertEqual(aliasAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
    }

    // MARK: - (c) Unbalanced `[[` is plain text (no wikilink attrs)

    func testUnbalancedWikilinkRemainsPlainText() {
        let text = "See [[Foo without a close"
        XCTAssertNil(wikilinkRange(in: text))
        let storage = styledStorage(for: text)
        XCTAssertEqual(hiddenRanges(in: storage), [])
        let attributes = storage.attributes(at: (text as NSString).range(of: "[[").location, effectiveRange: nil)
        XCTAssertNil(attributes[.underlineStyle])
    }

    func testWikilinkInsideInlineCodeEmitsNoRange() {
        let text = "Use `[[Foo]]` literally"
        XCTAssertNil(wikilinkRange(in: text))
    }

    // MARK: - (d) A paragraph with a `[[...]]` lays out on ONE line (no corruption)

    func testAliasedWikilinkParagraphLaysOutOnSingleLine() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "wiki", text: "Open [[baz/Foo|Foo]] here")]),
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()]
        ))
        let mountedHeight = try usedLineCount(in: mounted, blockIndex: 0)
        XCTAssertEqual(mountedHeight, 1, "A collapsed wikilink must lay out on a single line, never one char per line")
    }

    func testPlainWikilinkParagraphLaysOutOnSingleLine() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "wiki", text: "Open [[Foo]] here")]),
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()]
        ))
        XCTAssertEqual(try usedLineCount(in: mounted, blockIndex: 0), 1)
    }

    // MARK: - (e) Double-click on `[[...]]` routes to inlineLinkClickHandler with kind .customMarkup("wikilink")

    func testDoubleClickOnWikilinkBodyRoutesToHandlerWhileSingleClickPlacesCaret() throws {
        // Interaction model (shipping default): a single click on the wikilink BODY only places the caret; a
        // double-click navigates and routes to the host `inlineLinkClickHandler` with kind `.customMarkup("wikilink")`.
        var captured: BlockInputInlineLinkClickContext?
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open [[baz/Foo|Foo]] here")
            ]),
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()],
            inlineLinkClickHandler: { context in
                captured = context
                return .hostHandled
            }
        ))
        let textView = try textView(in: mounted.view)
        let aliasOffset = (("Open [[baz/Foo|Foo]] here") as NSString).range(of: "Foo]]").location
        let location = try windowLocation(forUTF16Offset: aliasOffset, in: textView)
        let wikilink = try XCTUnwrap(wikilinkRange(in: "Open [[baz/Foo|Foo]] here"))

        // Single click on the body does not route to the handler.
        XCTAssertFalse(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: aliasOffset, length: 0),
            clickedLinkRange: wikilink,
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertNil(captured)

        // Double click on the body routes to the handler.
        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "block",
            selectedRange: NSRange(location: aliasOffset, length: 0),
            clickedLinkRange: wikilink,
            event: try mouseDownEvent(location: location, windowNumber: mounted.window.windowNumber, clickCount: 2)
        ))
        let context = try XCTUnwrap(captured)
        XCTAssertEqual(context.kind, .customMarkup("wikilink"))
        XCTAssertEqual(context.alias, "Foo")
        XCTAssertEqual(context.destination.scheme, "wikilink")
        XCTAssertTrue(context.destination.absoluteString.contains("baz/Foo"))
    }

    // MARK: - (g) Editing the visible alias changes only the alias; the slug is untouched

    func testEditingVisibleAliasLeavesSlugUnchanged() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: "Open [[baz/Foo|Foo]] here")]),
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()]
        ))
        let textView = try textView(in: mounted.view)
        let aliasRange = ("Open [[baz/Foo|Foo]] here" as NSString).range(of: "Foo]]")
        // Replace the visible alias `Foo` with `Renamed`; this only touches the alias characters.
        let aliasOnly = NSRange(location: aliasRange.location, length: 3)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(aliasOnly)
        textView.insertText("Renamed", replacementRange: aliasOnly)

        let updated = try XCTUnwrap(mounted.view.block(withID: "block"))
        XCTAssertEqual(updated.text, "Open [[baz/Foo|Renamed]] here")
        let wikilink = try XCTUnwrap(wikilinkRange(in: updated.text))
        XCTAssertEqual(wikilink.style.customMarkupIdentity?.payload.primary, "baz/Foo")
        XCTAssertEqual(wikilink.style.customMarkupIdentity?.payload.secondary, "Renamed")
    }

    // MARK: - Resolution (b/c/d): bare `[[slug]]` resolves to `[[slug|Title]]` only when complete and resolvable

    func testBareWikilinkResolvesToAliasViaResolver() throws {
        let resolved = expectation(description: "bare slug rewritten to aliased form")
        var observed = false
        let mounted = makeMountedBlockInputView(configuration: configuration(
            text: "Open [[baz/Foo]] here",
            resolver: { slug in slug == "baz/Foo" ? "Resolved Title" : nil },
            onMutation: { document in
                guard !observed, document.blocks.first?.text == "Open [[baz/Foo|Resolved Title]] here" else {
                    return
                }
                observed = true
                resolved.fulfill()
            }
        ))
        wait(for: [resolved], timeout: 2)
        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Open [[baz/Foo|Resolved Title]] here")
    }

    /// FIX 1 (M1): a resolver title carrying structural characters (`]]`, `|`, newline) is sanitized before the
    /// rewrite, so the produced source is still a single valid `[[slug|safeTitle]]` token and never corrupts the
    /// document. The sanitized alias parses back exactly, with the slug untouched.
    func testResolverTitleWithStructuralCharactersIsSanitizedAndNeverCorruptsSource() throws {
        let resolved = expectation(description: "unsafe title sanitized into a valid wikilink")
        var observed = false
        let mounted = makeMountedBlockInputView(configuration: configuration(
            text: "Open [[baz/Foo]] here",
            resolver: { slug in slug == "baz/Foo" ? "Da]]ng|er\nous" : nil },
            onMutation: { document in
                guard !observed, document.blocks.first?.text != "Open [[baz/Foo]] here" else {
                    return
                }
                observed = true
                resolved.fulfill()
            }
        ))
        wait(for: [resolved], timeout: 2)

        let rewritten = try XCTUnwrap(mounted.view.block(withID: "block")?.text)
        // The structural characters `]] | \n` are stripped, so "Da]]ng|er\nous" becomes "Dangerous".
        XCTAssertEqual(rewritten, "Open [[baz/Foo|Dangerous]] here")
        // The rewritten source parses back to exactly one wikilink with the intended slug and sanitized alias.
        let wikilink = try XCTUnwrap(wikilinkRange(in: rewritten))
        XCTAssertEqual(wikilink.style.customMarkupIdentity?.payload.primary, "baz/Foo")
        XCTAssertEqual(wikilink.style.customMarkupIdentity?.payload.secondary, "Dangerous")
        // No structural characters leaked into the alias, so the token cannot have been split or closed early.
        let alias = try XCTUnwrap(wikilink.style.customMarkupIdentity?.payload.secondary)
        for character in alias where ["[", "]", "|", "\n", "\r"].contains(character) {
            XCTFail("Alias still contains a structural character: \(character)")
        }
    }

    func testBareWikilinkWithoutResolverIsNotMutated() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: "Open [[baz/Foo]] here")]),
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()]
        ))
        // No resolver configured: the bare slug shows and the source never changes.
        spinRunLoop()
        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Open [[baz/Foo]] here")
        let wikilink = try XCTUnwrap(wikilinkRange(in: "Open [[baz/Foo]] here"))
        XCTAssertNil(wikilink.style.customMarkupIdentity?.payload.secondary)
        XCTAssertEqual(wikilink.style.customMarkupIdentity?.payload.primary, "baz/Foo")
    }

    func testIncompleteWikilinkIsNeverResolved() throws {
        var resolverCalled = false
        let mounted = makeMountedBlockInputView(configuration: configuration(
            text: "Open [[baz/Foo without a close",
            resolver: { _ in
                resolverCalled = true
                return "Should Not Resolve"
            },
            onMutation: { _ in }
        ))
        spinRunLoop()
        XCTAssertFalse(resolverCalled, "Incomplete `[[` markup must never be resolved")
        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Open [[baz/Foo without a close")
    }

    // MARK: - (f) No reveal-on-edit: caret into a regular link does NOT change its rendering

    func testCaretInsideRegularLinkKeepsCollapsedRendering() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open [docs](https://example.com) end")
        ])
        let textView = try textView(in: mounted.view)
        let storage = try XCTUnwrap(textView.textStorage)
        let collapsedHidden = hiddenRanges(in: storage).count

        // Move the caret inside the link label and focus the row.
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        item.updateSelectionDependentAttributesForCurrentSelection()

        // The `[]()` chrome stays hidden exactly as collapsed; reveal-on-edit would have un-hidden it.
        XCTAssertEqual(hiddenRanges(in: storage).count, collapsedHidden)
        XCTAssertGreaterThan(collapsedHidden, 0)
    }

    // MARK: - Wikilink edit modal: non-URL slug validates and Save round-trips Target + Title

    func testWikilinkModalValidatesPlainSlugAndSavesEditedTargetAndTitle() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: "Open [[baz/Foo|Foo]] here")]),
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()]
        ))
        let wikilink = try XCTUnwrap(wikilinkRange(in: "Open [[baz/Foo|Foo]] here"))
        let identity = try XCTUnwrap(wikilink.style.customMarkupIdentity)

        XCTAssertTrue(mounted.view.showCustomMarkupModalIfAvailable(blockID: "block", range: wikilink, identity: identity))
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        // The Target field is populated with the bare slug (not a URL) and Save is enabled even though `baz/Foo` is not
        // a supported URL scheme.
        XCTAssertEqual(modal.textField.stringValue, "Foo")
        XCTAssertEqual(modal.urlField.stringValue, "baz/Foo")
        XCTAssertTrue(modal.saveButton.isEnabled)

        // Editing both the Title and the (editable) Target and saving rewrites `[[target|title]]`.
        modal.textField.stringValue = "Renamed"
        modal.urlField.stringValue = "baz/Bar"
        modal.saveButton.performClick(nil)

        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Open [[baz/Bar|Renamed]] here")
    }

    func testWikilinkModalDisablesSaveWhenTargetCleared() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: "Open [[baz/Foo|Foo]] here")]),
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()]
        ))
        let wikilink = try XCTUnwrap(wikilinkRange(in: "Open [[baz/Foo|Foo]] here"))
        let identity = try XCTUnwrap(wikilink.style.customMarkupIdentity)
        XCTAssertTrue(mounted.view.showCustomMarkupModalIfAvailable(blockID: "block", range: wikilink, identity: identity))
        let modal = try XCTUnwrap(mounted.view.linkModalView)
        modal.urlField.stringValue = "   "
        modal.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: modal.urlField))
        XCTAssertFalse(modal.saveButton.isEnabled)
    }

    // MARK: - Regular `[label](url)`: label visible + editable, `(url)` hidden via the delimiter mechanism

    func testRegularLinkHidesURLChromeAndKeepsLabelEditable() throws {
        let text = "Open [docs](https://example.com) end"
        let storage = styledStorage(for: text)
        let link = try XCTUnwrap(linkRange(in: text))

        // The label `docs` is the visible content; the `[`, `](https://example.com)` chrome is hidden via the same
        // null-glyph delimiter mechanism wikilinks use.
        XCTAssertEqual(content(in: text, range: link.contentRange), "docs")
        let hidden = hiddenRanges(in: storage).map { content(in: text, range: $0) }
        XCTAssertEqual(hidden, ["[", "](https://example.com)"])

        // The visible label edits like normal text: replacing `docs` changes only the label in source; the url is intact.
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "block", text: text)])
        let textView = try textView(in: mounted.view)
        let labelRange = (text as NSString).range(of: "docs")
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(labelRange)
        textView.insertText("guide", replacementRange: labelRange)

        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Open [guide](https://example.com) end")
    }

    // MARK: - Helpers

    private func linkRange(in text: String) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        )
        .first { $0.style == .link }
    }

    private func configuration(
        text: String,
        resolver: @escaping @MainActor (String) async -> String?,
        onMutation: @escaping (BlockInputDocument) -> Void
    ) -> BlockInputConfiguration {
        var configuration = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            undoController: BlockInputUndoController()
        )
        // Register the test stand-in title rewriter directly: it preserves the exact bare-`[[slug]]` →
        // `[[slug|title]]` rewrite + sanitization that these tests assert, via the generic `inlineMarkupRewriters` seam
        // (core owns no wikilink grammar; the plugin's `BlockInputWikilinkTitleRewriter` is the production equivalent).
        configuration.inlineMarkupProviders = [WikilinkStandInMarkupProvider()]
        configuration.inlineMarkupRewriters = [WikilinkStandInTitleRewriter(resolver: resolver)]
        configuration.onDocumentChange = onMutation
        return configuration
    }

    /// Runs the main run loop briefly so any scheduled resolution Task can complete (and, when correct, do nothing).
    private func spinRunLoop(iterations: Int = 40) {
        for _ in 0..<iterations {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    private func wikilinkRange(in text: String) -> BlockInputInlineMarkdownRange? {
        WikilinkStandInMarkupProvider.wikilinkRange(in: text)
    }

    private func styledStorage(for text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        BlockInputBlockItem.applyInlineMarkdownAttributes(
            for: BlockInputBlock(id: "b", kind: .paragraph, text: text),
            textStorage: storage,
            style: .default,
            inlineMarkupProviders: [WikilinkStandInMarkupProvider()]
        )
        return storage
    }

    private func hiddenRanges(in storage: NSTextStorage) -> [NSRange] {
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.blockInputHiddenDelimiter, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value as? Bool == true {
                ranges.append(range)
            }
        }
        return ranges
    }

    private func usedLineCount(in mounted: (view: BlockInputView, window: NSWindow), blockIndex: Int) throws -> Int {
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: blockIndex))
        let textView = try XCTUnwrap(item.testingTextView)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else {
            return 0
        }
        var lineCount = 0
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineRange = NSRange()
            _ = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            lineCount += 1
            glyphIndex = max(glyphIndex + 1, NSMaxRange(lineRange))
        }
        return lineCount
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func content(in text: String, range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }
}
