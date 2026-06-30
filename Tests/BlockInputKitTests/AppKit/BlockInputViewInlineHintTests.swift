import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewInlineHintTests: XCTestCase {
    func testInlineHintDrawsAfterFocusedCaretAndSuppliesContext() throws {
        let blockID = BlockInputBlockID(rawValue: "command")
        let text = "/review-github-pr"
        var contexts: [BlockInputInlineHintContext] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            inlineHintProvider: { context in
                contexts.append(context)
                return BlockInputInlineHint(text: " [PR URL]")
            }
        ))

        mounted.view.focus(blockID: blockID, utf16Offset: (text as NSString).length)

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let hintView = item.testingInlineHintView
        let context = try XCTUnwrap(contexts.last)

        XCTAssertFalse(hintView.isHidden)
        XCTAssertEqual(hintView.text, " [PR URL]")
        XCTAssertGreaterThan(hintView.frame.minX, textView.textContainerInset.width)
        XCTAssertGreaterThan(hintView.frame.width, 1)
        XCTAssertTrue(context.editorView === mounted.view)
        XCTAssertEqual(context.block.id, blockID)
        XCTAssertEqual(context.blockIndex, 0)
        XCTAssertEqual(context.cursor, BlockInputCursor(blockID: blockID, utf16Offset: (text as NSString).length))
        XCTAssertEqual(context.selectedRange, NSRange(location: (text as NSString).length, length: 0))
        XCTAssertTrue(context.isDocumentStartBlock)
        XCTAssertFalse(context.isAtDocumentStart)
    }

    func testInlineHintCanAppearAfterSlashCommandCompletionIsAccepted() async throws {
        let blockID = BlockInputBlockID(rawValue: "command")
        let expectedText = "[/heading](demo://heading) "
        let provider = PopupCompletionProvider(suggestions: [
            .slashCommand(id: "heading", title: "Heading", uri: "demo://heading", label: "heading")
        ])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "/")
            ]),
            inlineHintProvider: { context in
                context.block.text == expectedText
                    ? BlockInputInlineHint(text: "Heading text")
                    : nil
            },
            completionProvider: provider
        ))
        mounted.view.focus(blockID: blockID, utf16Offset: 1)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        mounted.view.refreshCompletionSession(item: item, blockID: blockID)
        await mounted.view.completionRequestTask?.value

        XCTAssertTrue(item.testingInlineHintView.isHidden)
        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [expectedText])
        XCTAssertEqual(updatedItem.testingInlineHintView.text, "Heading text")
        XCTAssertFalse(updatedItem.testingInlineHintView.isHidden)
    }

    func testInlineHintHidesForNilProviderNonCollapsedSelectionReadOnlyAndUnsupportedBlocks() throws {
        try assertHintHidden(
            blocks: [BlockInputBlock(id: "plain", text: "/command")],
            focus: BlockInputCursor(blockID: "plain", utf16Offset: 8),
            inlineHintProvider: nil
        )
        try assertHintHidden(
            blocks: [BlockInputBlock(id: "selection", text: "/command")],
            focus: BlockInputCursor(blockID: "selection", utf16Offset: 8),
            selectedRangeOverride: NSRange(location: 0, length: 2),
            inlineHintProvider: { _ in BlockInputInlineHint(text: " hint") }
        )
        try assertHintHidden(
            blocks: [BlockInputBlock(id: "readonly", text: "/command")],
            focus: BlockInputCursor(blockID: "readonly", utf16Offset: 8),
            isEditable: false,
            inlineHintProvider: { _ in BlockInputInlineHint(text: " hint") }
        )
        try assertHintHidden(
            blocks: [BlockInputBlock(id: "code", kind: .code(language: nil), text: "/command")],
            focus: BlockInputCursor(blockID: "code", utf16Offset: 8),
            inlineHintProvider: { _ in BlockInputInlineHint(text: " hint") }
        )
    }

    func testInlineHintHidesWhenSelectionIsStaleOrBlockIsNotFocused() throws {
        let blockID = BlockInputBlockID(rawValue: "command")
        let text = "/command"
        var providerCallCount = 0
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            inlineHintProvider: { _ in
                providerCallCount += 1
                return BlockInputInlineHint(text: " hint")
            }
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        providerCallCount = 0
        mounted.view.selection = .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 100))
        mounted.view.updateInlineHintsForVisibleItems()

        XCTAssertTrue(item.testingInlineHintView.isHidden)
        XCTAssertEqual(providerCallCount, 0)

        let unfocusedMounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            inlineHintProvider: { _ in
                providerCallCount += 1
                return BlockInputInlineHint(text: " hint")
            }
        ))
        let unfocusedItem = try XCTUnwrap(unfocusedMounted.view.visibleBlockItemForTesting(at: 0))
        unfocusedMounted.view.selection = .cursor(BlockInputCursor(blockID: blockID, utf16Offset: (text as NSString).length))
        unfocusedItem.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        unfocusedMounted.view.updateInlineHintsForVisibleItems()

        XCTAssertTrue(unfocusedItem.testingInlineHintView.isHidden)
        XCTAssertEqual(providerCallCount, 0)
    }

    func testInlineHintDoesNotMutateDocumentExportOrAccessibilityValue() throws {
        let blockID = BlockInputBlockID(rawValue: "command")
        let text = "/review-github-pr"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            inlineHintProvider: { _ in BlockInputInlineHint(text: " [PR URL]") }
        ))

        mounted.view.focus(blockID: blockID, utf16Offset: (text as NSString).length)
        mounted.view.updateInlineHintsForVisibleItems()

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertFalse(item.testingInlineHintView.isHidden)
        XCTAssertEqual(textView.string, text)
        XCTAssertEqual(mounted.view.document.blocks[0].text, text)
        XCTAssertEqual(mounted.view.document.markdown, text)
        XCTAssertEqual(textView.accessibilityValue(), text)
    }

    func testInlineHintClearsDuringBlockReuse() throws {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration())
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "first", text: "/first"),
            allowsReordering: true,
            inlineHint: BlockInputInlineHint(text: " hint"),
            delegate: view
        )

        item.testingInlineHintView.isHidden = false
        item.prepareForReuse()

        XCTAssertTrue(item.testingInlineHintView.isHidden)
        XCTAssertNil(item.textView.inlineHint)
    }

    private func assertHintHidden(
        blocks: [BlockInputBlock],
        focus: BlockInputCursor,
        selectedRangeOverride: NSRange? = nil,
        isEditable: Bool = true,
        inlineHintProvider: BlockInputInlineHintProvider?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: blocks),
            isEditable: isEditable,
            inlineHintProvider: inlineHintProvider
        ))
        mounted.view.focus(blockID: focus.blockID, utf16Offset: focus.utf16Offset)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0), file: file, line: line)
        if let selectedRangeOverride {
            item.setSelectedRange(selectedRangeOverride)
            mounted.view.applySelection(.text(BlockInputTextRange(blockID: focus.blockID, range: selectedRangeOverride)), notify: false)
        }
        mounted.view.updateInlineHintsForVisibleItems()

        XCTAssertTrue(item.testingInlineHintView.isHidden, file: file, line: line)
    }
}
