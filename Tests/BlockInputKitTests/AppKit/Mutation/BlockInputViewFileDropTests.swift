import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewFileDropTests: XCTestCase {
    func testDroppingFileIntoParagraphInsertsInlineFileChipAtDropOffset() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ])
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 5, in: textView)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")],
            location: location
        )

        XCTAssertTrue(textView.draggingEntered(draggingInfo).contains(.copy))
        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        let expectedText = "Open [README.md](file:///tmp/README.md)docs"
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        assertCaret(in: mounted.view, textView: textView, blockID: blockID, utf16Offset: (expectedText as NSString).length - 4)
    }

    func testDroppingImageIntoParagraphWithTextLinkPresentationInsertsInlineMarkdownImage() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Open docs")
            ]),
            imagePresentation: .textLinksWithPreviewStrip,
            undoController: undoController
        ))
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 5, in: textView)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/Cat Photo.png")],
            location: location
        )

        XCTAssertTrue(textView.draggingEntered(draggingInfo).contains(.copy))
        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        let expectedText = "Open ![Cat Photo](file:///tmp/Cat%20Photo.png) docs"
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        XCTAssertEqual(mounted.view.imagePreviewStripView.itemCountForTesting, 1)
        assertCaret(in: mounted.view, textView: textView, blockID: blockID, utf16Offset: (expectedText as NSString).length - 4)

        let undo = mounted.view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Image")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open docs")
    }

    func testDroppingImageBeforeExistingWhitespaceDoesNotDoubleSeparator() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Open  docs")
            ]),
            imagePresentation: .textLinksWithPreviewStrip
        ))
        let textView = try textView(in: mounted.view)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/Cat Photo.png")],
            location: try windowLocation(forUTF16Offset: 5, in: textView)
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        let expectedText = "Open ![Cat Photo](file:///tmp/Cat%20Photo.png) docs"
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        assertCaret(in: mounted.view, textView: textView, blockID: blockID, utf16Offset: (expectedText as NSString).length - 5)
    }

    func testDroppingMultipleImagesIntoListItemWithTextLinkPresentationInsertsInlineMarkdownImages() throws {
        let blockID = BlockInputBlockID(rawValue: "item")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .numberedListItem(start: 2), text: "Attach ")
            ]),
            imagePresentation: .textLinksWithPreviewStrip
        ))
        let textView = try textView(in: mounted.view)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [
                URL(fileURLWithPath: "/tmp/First Photo.png"),
                URL(fileURLWithPath: "/tmp/Second Photo.jpg")
            ],
            location: try windowLocation(forUTF16Offset: 7, in: textView)
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        let expectedText = "Attach ![First Photo](file:///tmp/First%20Photo.png) ![Second Photo](file:///tmp/Second%20Photo.jpg) "
        XCTAssertEqual(mounted.view.document.blocks.count, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .numberedListItem(start: 2))
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        XCTAssertEqual(mounted.view.imagePreviewStripView.itemCountForTesting, 2)
        assertCaret(in: mounted.view, textView: textView, blockID: blockID, utf16Offset: (expectedText as NSString).length)
    }

    func testAcceptedFileDropCaretIsVerticallyAlignedToTextLine() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open docs")
        ])
        let textView = try textView(in: mounted.view)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")],
            location: try windowLocation(forUTF16Offset: 5, in: textView)
        )

        XCTAssertTrue(textView.draggingEntered(draggingInfo).contains(.copy))

        let expectedLineFrame = try lineFragmentFrame(forUTF16Offset: 5, in: textView)
        XCTAssertFalse(textView.fileDropCaretView.isHidden)
        XCTAssertEqual(textView.fileDropCaretView.frame.midY, expectedLineFrame.midY, accuracy: 0.5)
    }

    func testDroppingFileIgnoresCurrentSelectionAndUsesDropOffset() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ])
        let textView = try textView(in: mounted.view)
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")],
            location: try windowLocation(forUTF16Offset: 5, in: textView)
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        let expectedText = "Open [README.md](file:///tmp/README.md)docs"
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        assertCaret(in: mounted.view, textView: textView, blockID: blockID, utf16Offset: (expectedText as NSString).length - 4)
    }

    func testDroppingDirectoryAcceptsFileURL() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Open ")
        ])
        let textView = try textView(in: mounted.view)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/Docs", isDirectory: true)],
            location: try windowLocation(forUTF16Offset: 5, in: textView)
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open [Docs](file:///tmp/Docs/)")
    }

    func testDroppingFilesIntoHeadingInsertsSpaceSeparatedFileChipsAndPreservesKind() throws {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Read ")
        ])
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 5, in: textView)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [
                URL(fileURLWithPath: "/tmp/First.md"),
                URL(fileURLWithPath: "/tmp/Second File.md")
            ],
            location: location
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        let expectedText = "Read [First.md](file:///tmp/First.md) [Second File.md](file:///tmp/Second%20File.md)"
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .heading(level: 2))
        XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        assertCaret(in: mounted.view, textView: textView, blockID: blockID, utf16Offset: (expectedText as NSString).length)
    }

    func testDroppingFileIntoListItemPreservesKind() throws {
        let blockID = BlockInputBlockID(rawValue: "item")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: false), text: "Attach ")
        ])
        let textView = try textView(in: mounted.view)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/Todo.md")],
            location: try windowLocation(forUTF16Offset: 7, in: textView)
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        XCTAssertEqual(mounted.view.document.blocks[0].kind, .checklistItem(isChecked: false))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Attach [Todo.md](file:///tmp/Todo.md)")
    }

    func testDroppingFileIntoQuoteAndNumberedListPreservesKind() throws {
        let quoteID = BlockInputBlockID(rawValue: "quote")
        let quote = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: quoteID, kind: .quote, text: "Quote ")
        ])
        let quoteTextView = try textView(in: quote.view)

        XCTAssertTrue(quoteTextView.performDragOperation(BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/Quote.md")],
            location: try windowLocation(forUTF16Offset: 6, in: quoteTextView)
        )))
        XCTAssertEqual(quote.view.document.blocks[0].kind, .quote)
        XCTAssertEqual(quote.view.document.blocks[0].text, "Quote [Quote.md](file:///tmp/Quote.md)")

        let listID = BlockInputBlockID(rawValue: "list")
        let numberedList = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: listID, kind: .numberedListItem(start: 3), text: "Item ")
        ])
        let listTextView = try textView(in: numberedList.view)

        XCTAssertTrue(listTextView.performDragOperation(BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/List.md")],
            location: try windowLocation(forUTF16Offset: 5, in: listTextView)
        )))
        XCTAssertEqual(numberedList.view.document.blocks[0].kind, .numberedListItem(start: 3))
        XCTAssertEqual(numberedList.view.document.blocks[0].text, "Item [List.md](file:///tmp/List.md)")
    }

    func testDroppingOnExistingFileChipSnapsAfterFullMarkdownSource() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let initialText = "See [README.md](file:///tmp/README.md) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: initialText)
        ])
        let textView = try textView(in: mounted.view)
        let existingLinkEnd = NSMaxRange((initialText as NSString).range(of: "[README.md](file:///tmp/README.md)"))
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/After.md")],
            location: try windowLocation(forUTF16Offset: existingLinkEnd - 1, in: textView)
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        XCTAssertEqual(
            mounted.view.document.blocks[0].text,
            "See [README.md](file:///tmp/README.md)[After.md](file:///tmp/After.md) now"
        )
    }

    func testDroppingOnExistingFileChipSnapsBeforeFullMarkdownSource() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let initialText = "See [README.md](file:///tmp/README.md) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: initialText)
        ])
        let textView = try textView(in: mounted.view)
        let existingLinkStart = (initialText as NSString).range(of: "README.md").location
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/Before.md")],
            location: try windowLocation(forUTF16Offset: existingLinkStart, in: textView)
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        XCTAssertEqual(
            mounted.view.document.blocks[0].text,
            "See [Before.md](file:///tmp/Before.md)[README.md](file:///tmp/README.md) now"
        )
    }

    func testDroppingOnExistingSlashCommandChipSnapsAroundFullMarkdownSource() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let initialText = "Run [/table](host-app://commands/table) now"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: initialText)
        ])
        let textView = try textView(in: mounted.view)
        let existingLinkEnd = NSMaxRange((initialText as NSString).range(of: "[/table](host-app://commands/table)"))
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/After.md")],
            location: try windowLocation(forUTF16Offset: existingLinkEnd - 1, in: textView)
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        XCTAssertEqual(
            mounted.view.document.blocks[0].text,
            "Run [/table](host-app://commands/table)[After.md](file:///tmp/After.md) now"
        )
    }

    func testDroppingFileIntoUnsupportedBlockIsRejectedWithoutNativeTextInsertion() throws {
        let blockID = BlockInputBlockID(rawValue: "code")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"), text: "let value = 1")
        ])
        let textView = try textView(in: mounted.view)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")],
            location: try windowLocation(forUTF16Offset: 4, in: textView)
        )

        XCTAssertTrue(textView.draggingEntered(draggingInfo).isEmpty)
        XCTAssertFalse(textView.performDragOperation(draggingInfo))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "let value = 1")
        XCTAssertEqual(textView.string, "let value = 1")
    }

    func testDroppingFileIntoHorizontalRuleIsRejected() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "rule", kind: .horizontalRule)
        ])
        let textView = try textView(in: mounted.view)

        XCTAssertTrue(textView.draggingEntered(BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")]
        )).isEmpty)
        XCTAssertFalse(textView.performDragOperation(BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")]
        )))
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .horizontalRule)
        XCTAssertTrue(mounted.view.document.blocks[0].text.isEmpty)
    }

    func testDroppingFileIntoFrontMatterOrRawMarkdownIsRejected() throws {
        let frontMatter = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        ])
        let frontMatterTextView = try textView(in: frontMatter.view)

        XCTAssertTrue(frontMatterTextView.draggingEntered(BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")],
            location: try windowLocation(forUTF16Offset: 0, in: frontMatterTextView)
        )).isEmpty)
        XCTAssertEqual(frontMatter.view.document.blocks[0].text, "title: Demo")

        let rawMarkdown = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "raw", kind: .rawMarkdown, text: "<div>raw</div>")
        ])
        let rawMarkdownTextView = try textView(in: rawMarkdown.view)

        XCTAssertTrue(rawMarkdownTextView.draggingEntered(BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")],
            location: try windowLocation(forUTF16Offset: 0, in: rawMarkdownTextView)
        )).isEmpty)
        XCTAssertEqual(rawMarkdown.view.document.blocks[0].text, "<div>raw</div>")
    }

    func testDroppingFileOutsideTextBoundsIsRejected() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open")
        ])
        let textView = try textView(in: mounted.view)
        let outsideLocation = textView.convert(NSPoint(x: textView.bounds.maxX + 20, y: textView.bounds.midY), to: nil)

        XCTAssertTrue(textView.draggingEntered(BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")],
            location: outsideLocation
        )).isEmpty)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open")
    }

    func testDroppingRemoteURLOrPromisedFileOnlyDragIsRejected() throws {
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/README.md"))
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open")
        ])
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 2, in: textView)
        let promisedFileType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")

        XCTAssertTrue(textView.draggingEntered(BlockInputDraggingInfo(fileURLs: [remoteURL], location: location)).isEmpty)
        XCTAssertTrue(textView.draggingEntered(BlockInputDraggingInfo(location: location)).isEmpty)
        XCTAssertTrue(textView.draggingEntered(BlockInputDraggingInfo(pasteboardTypes: [promisedFileType], location: location)).isEmpty)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open")
    }

    func testFileDropWithBlockIDIsRejectedByTextView() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "block", text: "Open")
        ])
        let textView = try textView(in: mounted.view)
        let draggingInfo = BlockInputDraggingInfo(
            blockID: "block",
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")],
            location: try windowLocation(forUTF16Offset: 2, in: textView)
        )

        XCTAssertTrue(textView.draggingEntered(draggingInfo).isEmpty)
        XCTAssertFalse(textView.performDragOperation(draggingInfo))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open")
    }

    func testStoreBackedFileDropPublishesGranularReplacementAndUndoRedoRestoresSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Open docs")
        ]))
        var mutations: [BlockInputDocumentChange] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        let textView = try textView(in: mounted.view)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")],
            location: try windowLocation(forUTF16Offset: 5, in: textView)
        )
        store.resetCounts()

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        let expectedText = "Open [README.md](file:///tmp/README.md)docs"
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [blockID])
        XCTAssertEqual(store.document.blocks[0].text, expectedText)
        XCTAssertEqual(mutations, [.replaceBlock(store.document.blocks[0])])

        XCTAssertNotNil(mounted.view.undoStructuralEdit())
        XCTAssertEqual(store.document.blocks[0].text, "Open docs")
        XCTAssertNil(mounted.view.selection)

        XCTAssertNotNil(mounted.view.redoStructuralEdit())
        XCTAssertEqual(store.document.blocks[0].text, expectedText)
        assertCaret(
            in: mounted.view,
            textView: try self.textView(in: mounted.view),
            blockID: blockID,
            utf16Offset: (expectedText as NSString).length - 4
        )
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func assertCaret(
        in view: BlockInputView,
        textView: BlockInputTextView,
        blockID: BlockInputBlockID,
        utf16Offset: Int
    ) {
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: utf16Offset)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: utf16Offset, length: 0))
    }

    private func lineFragmentFrame(forUTF16Offset offset: Int, in textView: BlockInputTextView) throws -> NSRect {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let textLength = (textView.string as NSString).length
        let characterIndex = min(max(offset, 0), max(textLength - 1, 0))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        return layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    }

}
