import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTextFormattingShortcutTests: XCTestCase {
    func testCommandBFormatsSelectedTextFromTextFocus() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Format me")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 0, length: 6))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "**Format** me")
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 2, length: 6)
        )))
    }

    func testCommandBFormatsVisibleRelativeFileLinkLabelWhenBaseURLIsConfigured() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let text = "[README](assets/README.md)"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            fileBaseURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "[**README**](assets/README.md)")
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 3, length: 6)
        )))
    }

    func testFormattingShortcutsUseExpectedDelimiters() throws {
        let cases: [(NSEvent, String)] = [
            (try commandIEvent(), "_word_"),
            (try commandUEvent(), "<u>word</u>"),
            (try commandShiftXEvent(), "~~word~~")
        ]

        for (event, expectedText) in cases {
            let blockID = BlockInputBlockID(rawValue: expectedText)
            let mounted = makeMountedBlockInputView(blocks: [
                BlockInputBlock(id: blockID, text: "word")
            ])
            let textView = try textView(in: mounted.view, at: 0)
            textView.setSelectedRange(NSRange(location: 0, length: 4))

            XCTAssertTrue(textView.performKeyEquivalent(with: event))

            XCTAssertEqual(mounted.view.document.blocks[0].text, expectedText)
        }
    }

    func testCommandBTogglesSurroundedSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "**Format** me")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 2, length: 6))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Format me")
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )))
    }

    func testCommandBTogglesSelectionIncludingDelimiters() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "**Format** me")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 0, length: 10))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Format me")
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )))
    }

    func testCommandBTogglesEnclosingNestedMarkupAroundVisibleSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "**_~~owns~~_**")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 5, length: 4))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "_~~owns~~_")
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 3, length: 4)
        )))
    }

    func testCommandBFormatsWholeSelectedBlocksIndependently() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["**First**", "**Second**"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testCommandBFormatsMixedSelectionPerBlockBoundary() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Beta"),
            BlockInputBlock(id: thirdID, text: "Gamma")
        ])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 2))
        )), notify: false)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Al**pha**", "**Beta**", "**Ga**mma"])
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 4, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 2, length: 2))
        )))
    }

    func testCommandBApplyUnlessAllLeavesFormattedSegmentsAlone() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "**First**"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            undoController: undoController
        )
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["**First**", "**Second**"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandZEvent()))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["**First**", "Second"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testCommandBUnformatsWhenAllSegmentsAreFormatted() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "**First**"),
            BlockInputBlock(id: secondID, text: "**Second**")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["First", "Second"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testCommandBDoesNotNormalizeNestedMarkup() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "a **bold** word")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 1, length: 10))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "a** **bold** **word")
    }

    func testFormattingShortcutConsumesCollapsedCaretWithoutChangingText() throws {
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Text")
        ])
        let textView = try textView(in: mounted.view, at: 0)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Text")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)))
    }

    func testFormattingShortcutConsumesUnsupportedSelectionWithoutChangingText() throws {
        let codeID = BlockInputBlockID(rawValue: "code")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: codeID, kind: .code(language: nil), text: "code"),
            BlockInputBlock(id: ruleID, kind: .horizontalRule)
        ])
        mounted.view.applySelection(.blocks([codeID, ruleID]), notify: false)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "code")
        XCTAssertEqual(mounted.view.document.blocks[1].kind, .horizontalRule)
        XCTAssertEqual(mounted.view.selection, .blocks([codeID, ruleID]))
    }

    func testCommandBUndoRedoRestoresMultiBlockFormattingAndSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            undoController: undoController
        )
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandZEvent()))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["First", "Second"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftZEvent()))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["**First**", "**Second**"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testStoreBackedMultiBlockFormattingPublishesGranularReplacements() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]))
        var mutations: [BlockInputDocumentChange] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        store.resetCounts()

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [firstID, secondID])
        XCTAssertEqual(store.document.blocks.map(\.text), ["**First**", "**Second**"])
        XCTAssertEqual(mutations, [
            .replaceBlock(store.document.blocks[0]),
            .replaceBlock(store.document.blocks[1])
        ])
    }

    func testStoreBackedMultiBlockFormattingUndoSkipsUnchangedFormattedBlocks() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "**First**"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ]))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController()
        ))
        mounted.view.applySelection(.blocks([firstID, secondID, thirdID]), notify: false)
        store.resetCounts()

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandBEvent()))

        XCTAssertEqual(store.replaceBlockIDs, [secondID, thirdID])
        store.resetCounts()

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandZEvent()))

        XCTAssertEqual(store.replaceBlockIDs, [secondID, thirdID])
        XCTAssertEqual(store.document.blocks.map(\.text), ["**First**", "Second", "Third"])
    }

    private func textView(
        in view: BlockInputView,
        at index: Int
    ) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: index))
        return try XCTUnwrap(item.testingTextView)
    }
}
