import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewTests: XCTestCase {
    func testConfigureUsesDocumentAndReorderingDefault() {
        let block = BlockInputBlock(id: "first", text: "Hello")
        let view = BlockInputView()

        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [block])))

        XCTAssertEqual(view.document.blocks, [block])
        XCTAssertTrue(view.allowsBlockReordering)
    }

    func testCollectionLayoutDoesNotInsertRowSeparatorSpacing() {
        let view = BlockInputView()

        let layout = view.collectionView.collectionViewLayout as? NSCollectionViewFlowLayout

        XCTAssertEqual(layout?.minimumLineSpacing, 0)
    }

    func testMountedEditorUsesMinimumCodeSurfaceWhenReorderingIsDisabled() throws {
        let codeBlock = BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                codeBlock
            ]),
            allowsBlockReordering: false
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let codeSurface = item.testingCodeBackgroundView

        XCTAssertEqual(scrollView.frame.minX, item.view.bounds.maxX - scrollView.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(
            scrollView.frame.width,
            BlockInputBlockItem.textScrollViewWidth(
                for: item.view.bounds.width,
                block: codeBlock,
                allowsReordering: false
            ),
            accuracy: 0.5
        )
        XCTAssertEqual(
            codeSurface.frame.minX,
            BlockInputBlockItem.codeBackgroundLeadingInset(allowsReordering: false),
            accuracy: 0.5
        )
        XCTAssertEqual(
            codeSurface.frame.width,
            max(ceil(BlockInputBlockItem.font(for: codeBlock.kind).pointSize * 12), 144),
            accuracy: 0.5
        )
        XCTAssertLessThan(codeSurface.frame.maxX, scrollView.frame.maxX)
    }

    func testMountedEditorPreservesReorderLaneWhenReorderingIsEnabled() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", text: "First")
            ]),
            allowsBlockReordering: true
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let handleView = try XCTUnwrap(item.testingHandleView)

        XCTAssertEqual(scrollView.frame.minX, BlockInputBlockItem.horizontalChromeWidth(allowsReordering: true), accuracy: 0.5)
        XCTAssertEqual(scrollView.frame.minX, item.view.bounds.maxX - scrollView.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(handleView.frame.minX, BlockInputBlockItem.handleLeading, accuracy: 0.5)
        XCTAssertEqual(handleView.frame.width, BlockInputBlockItem.handleWidth, accuracy: 0.5)
        XCTAssertFalse(handleView.isHidden)
    }

    func testMountedEditorPassesConfigurationStyleToVisibleRows() throws {
        let block = BlockInputBlock(id: "paragraph", text: "Styled")
        let style = BlockInputStyle(baseText: BlockInputTextStyle(font: .systemFont(ofSize: 21), foregroundColor: .systemPink))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [block]),
            style: style
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = try XCTUnwrap(textView.textStorage)

        XCTAssertEqual(textView.font?.pointSize, 21)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemPink)
        XCTAssertEqual(
            BlockInputBlockItem.height(for: block, textWidth: 240, style: style),
            BlockInputBlockItem.height(for: block, textWidth: 240, style: mounted.view.style)
        )
    }

    func testInsertBlockBelowCurrentBlockPublishesDocumentChange() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        var publishedDocument: BlockInputDocument?
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: blockID, text: "Hello")]),
            onDocumentChange: { publishedDocument = $0 }
        ))
        view.focus(blockID: blockID, utf16Offset: 5)

        let selection = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
        XCTAssertEqual(publishedDocument, view.document)
    }

    func testDeleteEmptyBlockFocusesPreviousBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Before"),
            BlockInputBlock(id: secondID, text: "")
        ])))
        view.focus(blockID: secondID)

        let selection = view.deleteCurrentEmptyBlockForBackspaceOrDelete()

        XCTAssertEqual(view.document.blocks.map(\.id), [firstID])
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
    }

    func testDeleteKeyClearsOnlySelectedBlock() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        var publishedDocument: BlockInputDocument?
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            onDocumentChange: { publishedDocument = $0 }
        ))
        view.applySelection(.blocks([blockID]), notify: false)

        view.keyDown(with: try keyDownEvent(keyCode: 51, characters: "\u{7F}"))

        XCTAssertEqual(view.document.blocks.map(\.id), [blockID])
        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
        XCTAssertEqual(publishedDocument, view.document)
    }

    func testFocusIgnoresMissingBlockID() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let missingID = BlockInputBlockID(rawValue: "missing")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])))

        view.focus(blockID: missingID)

        XCTAssertNil(view.selection)
    }

    func testFocusClampsCursorOffsetToBlockLength() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])))

        view.focus(blockID: blockID, utf16Offset: 100)

        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)))
    }

    func testConfigureClearsStaleSelectionWhenDocumentChanges() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Hello")
        ])))
        view.focus(blockID: firstID)

        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "Replacement")
        ])))

        XCTAssertNil(view.selection)
        XCTAssertNotNil(view.insertBlockBelowCurrentBlock()?.cursorBlockID)
        XCTAssertEqual(view.document.blocks.map(\.id).first, replacementID)
        XCTAssertEqual(view.document.blocks.count, 2)
    }

    func testConfigurePublishesNilSelectionWhenSelectedBlockIsRemoved() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let view = BlockInputView()
        var publishedSelections: [BlockInputSelection?] = []
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "Hello")
            ]),
            onSelectionChange: { publishedSelections.append($0) }
        ))
        view.focus(blockID: firstID)

        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: replacementID, text: "Replacement")
            ]),
            onSelectionChange: { publishedSelections.append($0) }
        ))

        guard let lastPublishedSelection = publishedSelections.last else {
            return XCTFail("Expected configure to publish a nil selection")
        }
        XCTAssertNil(lastPublishedSelection)
    }

    func testConfigureClearsStaleCursorWhenBlockTextShrinks() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])))
        view.focus(blockID: blockID, utf16Offset: 5)

        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hi")
        ])))

        XCTAssertNil(view.selection)
    }

    func testConfigureClearsNegativeCursorOffset() {
        let blockID = BlockInputBlockID(rawValue: "first")
        var cursor = BlockInputCursor(blockID: blockID, utf16Offset: 0)
        cursor.utf16Offset = -1
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])))
        view.applySelection(.cursor(cursor), notify: false)

        view.configure(BlockInputConfiguration(document: view.document))

        XCTAssertNil(view.selection)
    }

    func testConfigureClearsStaleTextRangeWhenBlockTextShrinks() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])))
        view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 5)
        )), notify: false)

        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hi")
        ])))

        XCTAssertNil(view.selection)
    }

    func testConfigureClearsEmptyBlockSelection() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])))
        view.applySelection(.blocks([]), notify: false)

        view.configure(BlockInputConfiguration(document: view.document))

        XCTAssertNil(view.selection)
    }

    func testConfigureClearsDuplicateBlockSelection() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])))
        view.applySelection(.blocks([blockID, blockID]), notify: false)

        view.configure(BlockInputConfiguration(document: view.document))

        XCTAssertNil(view.selection)
    }

    func testFocusEditorPreservesCurrentTextSelection() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])))
        view.focus(blockID: firstID, utf16Offset: 1)
        view.applySelection(.text(BlockInputTextRange(
            blockID: secondID,
            range: NSRange(location: 0, length: 2)
        )), notify: false)

        view.focusEditor()

        XCTAssertEqual(view.selection, .text(BlockInputTextRange(
            blockID: secondID,
            range: NSRange(location: 0, length: 2)
        )))
    }

    func testFocusEditorPreservesCurrentBlockSelection() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])))
        view.focus(blockID: firstID, utf16Offset: 1)
        view.applySelection(.blocks([secondID]), notify: false)

        view.focusEditor()

        XCTAssertEqual(view.selection, .blocks([secondID]))
    }

    func testMoveBlockIsIgnoredWhenReorderingIsDisabled() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            allowsBlockReordering: false
        ))

        let selection = view.moveBlock(blockID: firstID, to: 1)

        XCTAssertNil(selection)
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
    }

    func testMoveBlockPublishesChangeWhenReorderingIsEnabled() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let view = BlockInputView()
        var publishedDocument: BlockInputDocument?
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second"),
                BlockInputBlock(id: thirdID, text: "Third")
            ]),
            onDocumentChange: { publishedDocument = $0 }
        ))

        let selection = view.moveBlock(blockID: firstID, to: 2)

        XCTAssertEqual(selection, .blocks([firstID]))
        XCTAssertEqual(view.document.blocks.map(\.id), [secondID, thirdID, firstID])
        XCTAssertEqual(publishedDocument, view.document)
    }

    func testNoOpStructuralEditDoesNotPublishDocumentChange() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        var publishCount = 0
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            onDocumentChange: { _ in publishCount += 1 }
        ))

        let selection = view.moveBlock(blockID: blockID, to: 0)

        XCTAssertNil(selection)
        XCTAssertEqual(publishCount, 0)
        XCTAssertEqual(view.document.blocks.map(\.id), [blockID])
    }

}

private extension BlockInputSelection {
    var cursorBlockID: BlockInputBlockID? {
        if case let .cursor(cursor) = self {
            return cursor.blockID
        }
        return nil
    }
}
