import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCompletionPopupTests: XCTestCase {
    func testMentionTokenOpensPopupAndParsesParentDirectoryPrefix() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "../README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])

        let mounted = try await startCompletion(text: "See @../RE", provider: provider)

        XCTAssertNotNil(mounted.view.completionPopupView)
        XCTAssertEqual(mounted.view.completionSession?.suggestions.count, 1)
        XCTAssertEqual(provider.lastContext?.query, "RE")
        XCTAssertEqual(provider.lastContext?.rawQuery, "../RE")
        XCTAssertEqual(provider.lastContext?.replacementRange, NSRange(location: 4, length: 6))
        XCTAssertEqual(provider.lastContext?.fileQuery, BlockInputCompletionFileQuery(
            directoryReference: .parent,
            levelsUp: 1,
            remainder: "RE"
        ))
    }

    func testMentionTokenParsesCurrentAndGrandparentDirectoryPrefixes() async throws {
        let currentProvider = PopupCompletionProvider(suggestions: [])
        _ = try await startCompletion(text: "See @./Sources", provider: currentProvider)

        XCTAssertEqual(currentProvider.lastContext?.query, "Sources")
        XCTAssertEqual(currentProvider.lastContext?.rawQuery, "./Sources")
        XCTAssertEqual(currentProvider.lastContext?.fileQuery, BlockInputCompletionFileQuery(
            directoryReference: .current,
            levelsUp: 0,
            remainder: "Sources"
        ))

        let grandparentProvider = PopupCompletionProvider(suggestions: [])
        _ = try await startCompletion(text: "See @.../README", provider: grandparentProvider)

        XCTAssertEqual(grandparentProvider.lastContext?.query, "README")
        XCTAssertEqual(grandparentProvider.lastContext?.rawQuery, ".../README")
        XCTAssertEqual(grandparentProvider.lastContext?.fileQuery, BlockInputCompletionFileQuery(
            directoryReference: .grandparent,
            levelsUp: 2,
            remainder: "README"
        ))
    }

    func testMentionTokenParsesBareDotDirectoryPrefixes() async throws {
        let currentProvider = PopupCompletionProvider(suggestions: [])
        _ = try await startCompletion(text: "See @.", provider: currentProvider)

        XCTAssertEqual(currentProvider.lastContext?.query, "")
        XCTAssertEqual(currentProvider.lastContext?.rawQuery, ".")
        XCTAssertEqual(currentProvider.lastContext?.fileQuery, BlockInputCompletionFileQuery(
            directoryReference: .current,
            levelsUp: 0,
            remainder: ""
        ))

        let parentProvider = PopupCompletionProvider(suggestions: [])
        _ = try await startCompletion(text: "See @..", provider: parentProvider)

        XCTAssertEqual(parentProvider.lastContext?.query, "")
        XCTAssertEqual(parentProvider.lastContext?.rawQuery, "..")
        XCTAssertEqual(parentProvider.lastContext?.fileQuery, BlockInputCompletionFileQuery(
            directoryReference: .parent,
            levelsUp: 1,
            remainder: ""
        ))

        let grandparentProvider = PopupCompletionProvider(suggestions: [])
        _ = try await startCompletion(text: "See @...", provider: grandparentProvider)

        XCTAssertEqual(grandparentProvider.lastContext?.query, "")
        XCTAssertEqual(grandparentProvider.lastContext?.rawQuery, "...")
        XCTAssertEqual(grandparentProvider.lastContext?.fileQuery, BlockInputCompletionFileQuery(
            directoryReference: .grandparent,
            levelsUp: 2,
            remainder: ""
        ))
    }

    func testMentionTokenUsesUTF16ReplacementRangeAfterUnicodePrefix() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])

        _ = try await startCompletion(text: "🙂 @read", provider: provider)

        XCTAssertEqual(provider.lastContext?.replacementRange, NSRange(location: 3, length: 5))
    }

    func testMentionTokenRequiresCollapsedSelectionAndTokenBoundary() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])

        let nonCollapsed = try await startCompletion(
            text: "See @read",
            provider: provider,
            selectedOffset: 4,
            selectedLength: 5
        )
        XCTAssertNil(nonCollapsed.view.completionPopupView)

        let insideWord = try await startCompletion(text: "email@read", provider: provider)
        XCTAssertNil(insideWord.view.completionPopupView)

        let afterBoundary = try await startCompletion(text: "(@read", provider: provider)
        XCTAssertNotNil(afterBoundary.view.completionPopupView)
        XCTAssertEqual(provider.lastContext?.replacementRange, NSRange(location: 1, length: 5))
    }

    func testReturnAcceptsHighlightedCompletionAndRestoresFocus() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "../README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "See @../RE", provider: provider)

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See [../README.md](file:///tmp/README.md) "])
        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: 42)))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)

        _ = mounted.view.undoTextEditInActiveBlock()
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See @../RE"])
    }

    func testReturnAcceptsFileCompletionInHeadingAndPreservesKind() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(
            text: "See @read",
            provider: provider,
            kind: .heading(level: 2)
        )

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        let expectedText = "See [README.md](file:///tmp/README.md) "
        let block = try XCTUnwrap(mounted.view.document.blocks.first)
        XCTAssertEqual(block.kind, .heading(level: 2))
        XCTAssertEqual(block.text, expectedText)
        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(
            blockID: "block",
            utf16Offset: (expectedText as NSString).length
        )))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)

        _ = mounted.view.undoTextEditInActiveBlock()
        let restoredBlock = try XCTUnwrap(mounted.view.document.blocks.first)
        XCTAssertEqual(restoredBlock.kind, .heading(level: 2))
        XCTAssertEqual(restoredBlock.text, "See @read")
    }

    func testTabConsumesEmptyPopupAndEscapeDismissesPopup() async throws {
        let provider = PopupCompletionProvider(suggestions: [])
        let mounted = try await startCompletion(text: "@missing", provider: provider)

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertTab(_:))))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["@missing"])
        XCTAssertNotNil(mounted.view.completionPopupView)

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.cancelOperation(_:))))
        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(mounted.view.completionSession)
    }

    func testPopupDoesNotOpenWithoutProviderOrInsideInlineCodeOrLinks() async throws {
        let noProvider = try await startCompletion(text: "@read", provider: nil)
        XCTAssertNil(noProvider.view.completionPopupView)

        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let inlineCode = try await startCompletion(text: "Use `@read`", provider: provider, selectedOffset: 10)
        XCTAssertNil(inlineCode.view.completionPopupView)

        let link = try await startCompletion(text: "Open [@read](file:///tmp/read.md)", provider: provider, selectedOffset: 11)
        XCTAssertNil(link.view.completionPopupView)

        let unsupportedLabelLinkText = "Open [@read](mailto:user@example.com)"
        let unsupportedLabelQueryRange = (unsupportedLabelLinkText as NSString).range(of: "@read")
        let unsupportedLabelLink = try await startCompletion(
            text: unsupportedLabelLinkText,
            provider: provider,
            selectedOffset: NSMaxRange(unsupportedLabelQueryRange)
        )
        XCTAssertNil(unsupportedLabelLink.view.completionPopupView)

        let unsupportedDestinationLinkText = "Open [file](@read)"
        let unsupportedDestinationQueryRange = (unsupportedDestinationLinkText as NSString).range(of: "@read")
        let unsupportedDestinationLink = try await startCompletion(
            text: unsupportedDestinationLinkText,
            provider: provider,
            selectedOffset: NSMaxRange(unsupportedDestinationQueryRange)
        )
        XCTAssertNil(unsupportedDestinationLink.view.completionPopupView)

        let emptyDestinationLinkText = "Open [@read]()"
        let emptyDestinationQueryRange = (emptyDestinationLinkText as NSString).range(of: "@read")
        let emptyDestinationLink = try await startCompletion(
            text: emptyDestinationLinkText,
            provider: provider,
            selectedOffset: NSMaxRange(emptyDestinationQueryRange)
        )
        XCTAssertNil(emptyDestinationLink.view.completionPopupView)

        let emptyLabelLinkText = "Open [](@read)"
        let emptyLabelQueryRange = (emptyLabelLinkText as NSString).range(of: "@read")
        let emptyLabelLink = try await startCompletion(
            text: emptyLabelLinkText,
            provider: provider,
            selectedOffset: NSMaxRange(emptyLabelQueryRange)
        )
        XCTAssertNil(emptyLabelLink.view.completionPopupView)

        let code = try await startCompletion(text: "@read", provider: provider, kind: .code(language: nil))
        XCTAssertNil(code.view.completionPopupView)

        let frontMatter = try await startCompletion(text: "@read", provider: provider, kind: .frontMatter)
        XCTAssertNil(frontMatter.view.completionPopupView)

        let rawMarkdown = try await startCompletion(text: "@read", provider: provider, kind: .rawMarkdown)
        XCTAssertNil(rawMarkdown.view.completionPopupView)

        let horizontalRule = try await startCompletion(text: "@read", provider: provider, kind: .horizontalRule)
        XCTAssertNil(horizontalRule.view.completionPopupView)
    }

    func testPopupDoesNotOpenInsideImageMarkdownSource() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])

        let imageLabelLinkText = "Open ![@image](file:///tmp/image.png)"
        let imageLabelQueryRange = (imageLabelLinkText as NSString).range(of: "@image")
        let imageLabelLink = try await startCompletion(
            text: imageLabelLinkText,
            provider: provider,
            selectedOffset: NSMaxRange(imageLabelQueryRange)
        )
        XCTAssertNil(imageLabelLink.view.completionPopupView)

        let imageDestinationLinkText = "Open ![image](@read)"
        let imageDestinationQueryRange = (imageDestinationLinkText as NSString).range(of: "@read")
        let imageDestinationLink = try await startCompletion(
            text: imageDestinationLinkText,
            provider: provider,
            selectedOffset: NSMaxRange(imageDestinationQueryRange)
        )
        XCTAssertNil(imageDestinationLink.view.completionPopupView)
    }

    func testPopupRowsAreLaidOutInSuggestionOrderFromTop() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "First.md", fileURL: URL(fileURLWithPath: "/tmp/First.md")),
            .fileLink(label: "Second.md", fileURL: URL(fileURLWithPath: "/tmp/Second.md"))
        ])
        let mounted = try await startCompletion(text: "@read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)

        let firstRow = try rowView(label: "First.md", in: popup)
        let secondRow = try rowView(label: "Second.md", in: popup)

        XCTAssertGreaterThan(firstRow.frame.minY, secondRow.frame.minY)
    }

    func testMouseUpOnPopupRowAcceptsCompletionAfterMouseDown() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "See @read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        let row = try rowView(label: "README.md", in: popup)

        XCTAssertTrue(popup.routeMouseDown(
            at: NSPoint(x: row.frame.midX, y: row.frame.midY),
            event: try mouseDownEvent(location: .zero, windowNumber: mounted.window.windowNumber)
        ))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See @read"])
        XCTAssertNotNil(mounted.view.completionPopupView)

        XCTAssertTrue(popup.routeMouseUp(
            at: NSPoint(x: row.frame.midX, y: row.frame.midY),
            event: try mouseUpEvent(location: .zero, windowNumber: mounted.window.windowNumber)
        ))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["See [README.md](file:///tmp/README.md) "])
        XCTAssertNil(mounted.view.completionPopupView)
    }

    func testPopupRowPlacesTitleAboveSubtitle() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(
                subtitle: "/tmp",
                label: "README.md",
                fileURL: URL(fileURLWithPath: "/tmp/README.md")
            )
        ])
        let mounted = try await startCompletion(text: "@read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        popup.layoutSubtreeIfNeeded()

        let row = try rowView(label: "README.md, /tmp", in: popup)
        let titleField = try textField(label: "README.md", in: row)
        let subtitleField = try textField(label: "/tmp", in: row)

        XCTAssertGreaterThan(titleField.frame.minY, subtitleField.frame.minY)
    }

    func testPopupScrollKeepsHighlightedSuggestionVisibleForAccept() async throws {
        let provider = PopupCompletionProvider(suggestions: (0..<8).map { index in
            .fileLink(label: "File\(index).md", fileURL: URL(fileURLWithPath: "/tmp/File\(index).md"))
        })
        let mounted = try await startCompletion(text: "@read", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)

        XCTAssertTrue(popup.routeScrollWheel(
            at: NSPoint(x: popup.bounds.midX, y: popup.bounds.midY),
            event: TestScrollWheelEvent(deltaY: -1)
        ))

        XCTAssertEqual(mounted.view.completionSession?.highlightedIndex, 1)
        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["[File1.md](file:///tmp/File1.md) "])
    }

    func testReconfigureWithNewDocumentDismissesPopup() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "@read", provider: provider)

        mounted.view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "next", text: "Next")
            ]),
            completionProvider: provider
        ))

        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(mounted.view.completionSession)
    }

    func testEndEditingDismissesPopup() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "@read", provider: provider)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        mounted.view.blockItemDidEndEditing(item, blockID: "block")

        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(mounted.view.completionSession)
    }

    func testAcceptingStaleCompletionSessionDoesNotMutateDocument() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "@read", provider: provider)
        mounted.view.documentStore?.replaceBlock(BlockInputBlock(id: "block", text: "Changed @read"))

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Changed @read")
        XCTAssertNil(mounted.view.completionPopupView)
    }

    func testAcceptingStaleCompletionSessionDoesNotMutateUnsupportedBlockKind() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startCompletion(text: "@read", provider: provider)
        mounted.view.documentStore?.replaceBlock(BlockInputBlock(
            id: "block",
            kind: .code(language: nil),
            text: "@read"
        ))

        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        let block = try XCTUnwrap(mounted.view.block(withID: "block"))
        XCTAssertEqual(block.kind, .code(language: nil))
        XCTAssertEqual(block.text, "@read")
        XCTAssertNil(mounted.view.completionPopupView)
    }

    func testStaleAsyncCompletionResultDismissesPopup() async throws {
        let provider = DelayedPopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try startMountedCompletion(text: "@read", provider: provider)
        while !provider.isWaiting {
            await Task.yield()
        }

        mounted.view.documentStore?.replaceBlock(BlockInputBlock(id: "block", text: "Changed @read"))
        provider.resume()
        await mounted.view.completionRequestTask?.value

        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(mounted.view.completionSession)
        XCTAssertEqual(mounted.view.block(withID: "block")?.text, "Changed @read")
    }

    func testCompletionProviderRequestRunsOffMainThread() async throws {
        let provider = ThreadCapturingPopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])

        _ = try await startCompletion(text: "@read", provider: provider)

        XCTAssertEqual(provider.requestRanOnMainThread, false)
    }

    private func startCompletion(
        text: String,
        provider: (any BlockInputCompletionProvider)?,
        selectedOffset: Int? = nil,
        selectedLength: Int = 0,
        placement: BlockInputCompletionPopupPlacement = .caret,
        kind: BlockInputBlockKind = .paragraph
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        let mounted = try startMountedCompletion(
            text: text,
            provider: provider,
            selectedOffset: selectedOffset,
            selectedLength: selectedLength,
            placement: placement,
            kind: kind
        )
        await mounted.view.completionRequestTask?.value
        mounted.view.layoutSubtreeIfNeeded()
        return mounted
    }

    private func startMountedCompletion(
        text: String,
        provider: (any BlockInputCompletionProvider)?,
        selectedOffset: Int? = nil,
        selectedLength: Int = 0,
        placement: BlockInputCompletionPopupPlacement = .caret,
        kind: BlockInputBlockKind = .paragraph
    ) throws -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", kind: kind, text: text)
            ]),
            completionProvider: provider,
            completionPopupPlacement: placement
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: selectedOffset ?? (text as NSString).length, length: selectedLength))
        mounted.view.refreshCompletionSession(item: item, blockID: "block")
        return mounted
    }

    private func rowView(label: String, in popup: NSView) throws -> NSView {
        try XCTUnwrap(popup.subviews.first { $0.accessibilityLabel() == label })
    }

    private func textField(label: String, in row: NSView) throws -> NSTextField {
        try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == label })
    }

}
