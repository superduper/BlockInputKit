import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputCompletionTests: XCTestCase {
    func testCompletionSuggestionStoresHostProvidedInsertion() {
        let suggestion = BlockInputCompletionSuggestion(
            id: "mention:alice",
            title: "Alice",
            subtitle: "Engineering",
            insertionText: "@alice",
            trigger: .mention,
            iconSystemName: "person",
            detailText: "Team"
        )

        XCTAssertEqual(suggestion.id, "mention:alice")
        XCTAssertEqual(suggestion.title, "Alice")
        XCTAssertEqual(suggestion.subtitle, "Engineering")
        XCTAssertEqual(suggestion.insertionText, "@alice")
        XCTAssertEqual(suggestion.trigger, .mention)
        XCTAssertEqual(suggestion.iconSystemName, "person")
        XCTAssertEqual(suggestion.detailText, "Team")
    }

    func testCompletionContextStoresReplacementRawQueryAndFileMetadata() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let fileQuery = BlockInputCompletionFileQuery(
            directoryReference: .parent,
            levelsUp: 1,
            remainder: "README"
        )
        let context = BlockInputCompletionContext(
            trigger: .mention,
            query: "README",
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "@../README")
            ]),
            blockID: blockID,
            selectedRange: NSRange(location: 10, length: 0),
            replacementRange: NSRange(location: 0, length: 10),
            rawQuery: "../README",
            fileQuery: fileQuery
        )

        XCTAssertEqual(context.replacementRange, NSRange(location: 0, length: 10))
        XCTAssertEqual(context.rawQuery, "../README")
        XCTAssertEqual(context.fileQuery, fileQuery)
    }

    func testCompletionProviderReceivesContext() async {
        let blockID = BlockInputBlockID(rawValue: "first")
        let provider = CapturingCompletionProvider()
        let context = BlockInputCompletionContext(
            trigger: .slashCommand,
            query: "cod",
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "/cod")
            ]),
            blockID: blockID,
            selectedRange: NSRange(location: 1, length: 3)
        )

        let suggestions = await provider.suggestions(for: context)

        XCTAssertEqual(provider.lastContext, context)
        XCTAssertEqual(suggestions.map(\.insertionText), ["```"])
    }

    @MainActor
    func testCompletionSuggestionsBuildsContextFromCurrentSelection() async {
        let blockID = BlockInputBlockID(rawValue: "first")
        let provider = CapturingCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "@al")
            ]),
            completionProvider: provider
        ))
        view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 1, length: 2)
        )), notify: false)

        let suggestions = await view.completionSuggestions(trigger: .mention, query: "al")

        XCTAssertEqual(suggestions.map(\.insertionText), ["```"])
        XCTAssertEqual(provider.lastContext, BlockInputCompletionContext(
            trigger: .mention,
            query: "al",
            document: view.document,
            blockID: blockID,
            selectedRange: NSRange(location: 1, length: 2)
        ))
    }

    @MainActor
    func testCompletionSuggestionsBuildsContextFromCurrentCursor() async {
        let blockID = BlockInputBlockID(rawValue: "first")
        let provider = CapturingCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "@al")
            ]),
            completionProvider: provider
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 3)), notify: false)

        _ = await view.completionSuggestions(trigger: .mention, query: "al")

        XCTAssertEqual(provider.lastContext, BlockInputCompletionContext(
            trigger: .mention,
            query: "al",
            document: view.document,
            blockID: blockID,
            selectedRange: NSRange(location: 3, length: 0)
        ))
    }

    @MainActor
    func testCompletionSuggestionsForwardsExplicitFileQueryContext() async {
        let blockID = BlockInputBlockID(rawValue: "first")
        let provider = CapturingCompletionProvider()
        let fileQuery = BlockInputCompletionFileQuery(
            directoryReference: .grandparent,
            levelsUp: 2,
            remainder: "Sources/Block"
        )
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "@.../Sources/Block")
            ]),
            completionProvider: provider
        ))

        _ = await view.completionSuggestions(
            trigger: .mention,
            query: "Sources/Block",
            blockID: blockID,
            replacementRange: NSRange(location: 0, length: 17),
            rawQuery: ".../Sources/Block",
            fileQuery: fileQuery
        )

        XCTAssertEqual(provider.lastContext, BlockInputCompletionContext(
            trigger: .mention,
            query: "Sources/Block",
            document: view.document,
            blockID: blockID,
            replacementRange: NSRange(location: 0, length: 17),
            rawQuery: ".../Sources/Block",
            fileQuery: fileQuery
        ))
    }

    @MainActor
    func testCompletionSuggestionsUsesExplicitBlockAndIgnoresSelectionFromAnotherBlock() async {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let provider = CapturingCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "/cod")
            ]),
            completionProvider: provider
        ))
        view.applySelection(.text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 2)
        )), notify: false)

        _ = await view.completionSuggestions(trigger: .slashCommand, query: "cod", blockID: secondID)

        XCTAssertEqual(provider.lastContext, BlockInputCompletionContext(
            trigger: .slashCommand,
            query: "cod",
            document: view.document,
            blockID: secondID
        ))
    }

    @MainActor
    func testCompletionSuggestionsUsesFirstSelectedBlockForBlockSelection() async {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let provider = CapturingCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "@ava"),
                BlockInputBlock(id: secondID, text: "@noah")
            ]),
            completionProvider: provider
        ))
        view.applySelection(.blocks([secondID, firstID]), notify: false)

        _ = await view.completionSuggestions(trigger: .mention, query: "no")

        XCTAssertEqual(provider.lastContext, BlockInputCompletionContext(
            trigger: .mention,
            query: "no",
            document: view.document,
            blockID: secondID
        ))
    }

    @MainActor
    func testCompletionSuggestionsFallsBackToFirstBlockWithoutSelection() async {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let provider = CapturingCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "@ava"),
                BlockInputBlock(id: secondID, text: "@noah")
            ]),
            completionProvider: provider
        ))

        _ = await view.completionSuggestions(trigger: .mention, query: "av")

        XCTAssertEqual(provider.lastContext, BlockInputCompletionContext(
            trigger: .mention,
            query: "av",
            document: view.document,
            blockID: firstID
        ))
    }

    @MainActor
    func testCompletionSuggestionsReturnsEmptyWithoutProviderOrKnownBlock() async {
        let blockID = BlockInputBlockID(rawValue: "first")
        let provider = CapturingCompletionProvider()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "@al")
        ])))

        let missingProviderSuggestions = await view.completionSuggestions(trigger: .mention, query: "al")

        view.configure(BlockInputConfiguration(
            document: view.document,
            completionProvider: provider
        ))
        let missingBlockSuggestions = await view.completionSuggestions(
            trigger: .mention,
            query: "al",
            blockID: "missing"
        )

        XCTAssertTrue(missingProviderSuggestions.isEmpty)
        XCTAssertTrue(missingBlockSuggestions.isEmpty)
        XCTAssertNil(provider.lastContext)
    }

    @MainActor
    func testAcceptCompletionSuggestionReplacesCurrentTextSelection() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        var publishedDocuments: [BlockInputDocument] = []
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Hello @al")
            ]),
            undoController: undoController,
            onDocumentChange: { publishedDocuments.append($0) }
        ))
        view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 6, length: 3)
        )), notify: false)

        let selection = view.acceptCompletionSuggestion(BlockInputCompletionSuggestion(
            id: "mention:alice",
            title: "Alice",
            insertionText: "@alice",
            trigger: .mention
        ))

        XCTAssertEqual(view.document.blocks[0].text, "Hello @alice")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 12)))
        XCTAssertEqual(publishedDocuments.last, view.document)

        _ = view.undoTextEditInActiveBlock()
        XCTAssertEqual(view.document.blocks[0].text, "Hello @al")
        XCTAssertEqual(view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 6, length: 3)
        )))
    }

    @MainActor
    func testAcceptCompletionSuggestionInsertsAtCurrentCursor() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Hello ")
            ]),
            undoController: undoController
        ))
        view.focus(blockID: blockID, utf16Offset: 6)

        let selection = view.acceptCompletionSuggestion(BlockInputCompletionSuggestion(
            id: "mention:alice",
            title: "Alice",
            insertionText: "@alice",
            trigger: .mention
        ))

        XCTAssertEqual(view.document.blocks[0].text, "Hello @alice")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 12)))

        _ = view.undoTextEditInActiveBlock()
        XCTAssertEqual(view.document.blocks[0].text, "Hello ")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)))
    }

    @MainActor
    func testAcceptCompletionSuggestionPreservesListLineIndentation() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(
                    id: blockID,
                    kind: .bulletedListItem,
                    text: "One\nTwo",
                    lineIndentationLevels: [0, 1]
                )
            ]),
            undoController: undoController
        ))
        view.focus(blockID: blockID, utf16Offset: 7)

        let selection = view.acceptCompletionSuggestion(BlockInputCompletionSuggestion(
            id: "append:three",
            title: "Three",
            insertionText: "\nThree",
            trigger: .slashCommand
        ))

        XCTAssertEqual(view.document.blocks[0].text, "One\nTwo\nThree")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 1, 1])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 13)))

        _ = view.undoTextEditInActiveBlock()

        XCTAssertEqual(view.document.blocks[0].text, "One\nTwo")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 1])
    }

    @MainActor
    func testAcceptCompletionSuggestionUsesExplicitRangeAndBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "/cod")
            ]),
            undoController: undoController
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: firstID, utf16Offset: 1)), notify: false)

        let selection = view.acceptCompletionSuggestion(
            BlockInputCompletionSuggestion(
                id: "slash:code",
                title: "Code block",
                insertionText: "```",
                trigger: .slashCommand
            ),
            in: secondID,
            replacing: NSRange(location: 0, length: 4)
        )

        XCTAssertEqual(view.document.blocks.map(\.text), ["First", "```"])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: secondID, utf16Offset: 3)))

        view.focus(blockID: firstID, utf16Offset: 1)
        _ = view.undoTextEditInActiveBlock()
        XCTAssertEqual(view.document.blocks.map(\.text), ["First", "```"])

        view.focus(blockID: secondID, utf16Offset: 3)
        _ = view.undoTextEditInActiveBlock()
        XCTAssertEqual(view.document.blocks.map(\.text), ["First", "/cod"])
        XCTAssertEqual(view.selection, .text(BlockInputTextRange(
            blockID: secondID,
            range: NSRange(location: 0, length: 4)
        )))
    }

    @MainActor
    func testAcceptCompletionSuggestionClampsExplicitRangeBeforeRegisteringUndo() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "abc")
            ]),
            undoController: undoController
        ))

        let selection = view.acceptCompletionSuggestion(
            BlockInputCompletionSuggestion(
                id: "mention:alice",
                title: "Alice",
                insertionText: "@alice",
                trigger: .mention
            ),
            in: blockID,
            replacing: NSRange(location: 10, length: 4)
        )

        XCTAssertEqual(view.document.blocks[0].text, "abc@alice")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)))

        _ = view.undoTextEditInActiveBlock()
        XCTAssertEqual(view.document.blocks[0].text, "abc")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 3)))
    }
}

private final class CapturingCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private(set) var lastContext: BlockInputCompletionContext?

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        lastContext = context
        return [
            BlockInputCompletionSuggestion(
                id: "slash:code",
                title: "Code block",
                insertionText: "```",
                trigger: context.trigger
            )
        ]
    }
}
