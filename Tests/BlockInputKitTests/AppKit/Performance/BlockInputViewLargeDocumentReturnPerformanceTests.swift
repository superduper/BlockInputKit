import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class LargeDocumentMutationPerformanceTests: XCTestCase {
    func testStoreBackedReturnAtEndOfInsertedLargeListItemStaysGranular() throws {
        let targetIndex = 50_000
        let (blockID, document) = largeListDocument(targetIndex: targetIndex)
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)), notify: false)

        let insertedSelection = try XCTUnwrap(view.insertBlockBelowCurrentBlock())
        guard case let .cursor(insertedCursor) = insertedSelection else {
            XCTFail("Expected inserted cursor selection")
            return
        }
        var insertedBlock = try XCTUnwrap(store.block(withID: insertedCursor.blockID))
        insertedBlock.text = "Next item"
        store.replaceBlock(insertedBlock)
        view.applySelection(.cursor(BlockInputCursor(blockID: insertedBlock.id, utf16Offset: 9)), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, targetIndex + 2)
        XCTAssertEqual(store.insertedBlockBatches[0].blocks.first?.kind, .bulletedListItem)
    }

    func testStoreBackedReturnWithMutationCallbackDoesNotReadFullDocumentSnapshot() {
        let targetIndex = 50_000
        let (blockID, document) = largeListDocument(targetIndex: targetIndex)
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(mutations.count, 1)
        guard case let .insertBlocks(insertedBlocks, index) = mutations.first else {
            XCTFail("Expected an insert-block mutation")
            return
        }
        XCTAssertEqual(index, targetIndex + 1)
        XCTAssertEqual(insertedBlocks.first?.kind, .bulletedListItem)
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
    }

    func testStoreBackedReturnDelegatePathDoesNotReadFullDocumentSnapshot() throws {
        let targetIndex = 50_000
        let (blockID, document) = largeListDocument(targetIndex: targetIndex)
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: blockID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        store.resetCounts()

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, targetIndex + 1)
    }

    func testStoreBackedReturnAtFrontOfHeadingDoesNotReadFullDocumentSnapshot() {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                kind: index == targetIndex ? .heading(level: 2) : .paragraph,
                text: index == targetIndex ? "Heading" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController()
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, targetIndex + 1)
        XCTAssertEqual(store.insertedBlockBatches[0].blocks.first?.kind, .heading(level: 2))
    }

    func testMountedLargeEmptyQuoteReturnReconfiguresWithoutFullSnapshot() throws {
        let quoteID = BlockInputBlockID(rawValue: "large-2")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            let id = BlockInputBlockID(rawValue: "large-\(index)")
            return BlockInputBlock(
                id: id,
                kind: index == 2 ? .quote : .paragraph,
                text: index == 2 ? "" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: quoteID, utf16Offset: 0)), notify: false)
        store.resetCounts()

        _ = mounted.view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [quoteID])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        XCTAssertEqual(item.representedBlockID, quoteID)
        XCTAssertTrue(try XCTUnwrap(item.testingQuoteBarView).isHidden)
    }

    func testMountedLargeTrailingQuoteLineExitStaysGranular() throws {
        let quoteID = BlockInputBlockID(rawValue: "large-2")
        // Two trailing blank lines plus an end-of-block caret are the escape gesture under the new
        // threshold; the exit trims both blanks and stays on the granular replace-plus-insert path.
        let quoteText = "Line 1\nLine 2\n\n"
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            let id = BlockInputBlockID(rawValue: "large-\(index)")
            return BlockInputBlock(
                id: id,
                kind: index == 2 ? .quote : .paragraph,
                text: index == 2 ? quoteText : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: store,
            undoController: undoController
        ))
        mounted.view.applySelection(.cursor(BlockInputCursor(
            blockID: quoteID,
            utf16Offset: (quoteText as NSString).length
        )), notify: false)
        store.resetCounts()

        let insertedSelection = try XCTUnwrap(mounted.view.insertBlockBelowCurrentBlock())

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [quoteID])
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, 3)
        let quoteItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let paragraphItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 3))
        XCTAssertEqual(quoteItem.currentText, "Line 1\nLine 2")
        XCTAssertFalse(try XCTUnwrap(quoteItem.testingQuoteBarView).isHidden)
        XCTAssertEqual(paragraphItem.currentText, "")
        XCTAssertEqual(mounted.view.selection, insertedSelection)
        store.resetCounts()

        _ = mounted.view.undoStructuralEdit()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [quoteID])
        XCTAssertEqual(store.deletedBlockIDs.count, 1)
    }

    func testStoreBackedTypingInsertedLargeListItemDoesNotReadFullDocumentSnapshot() throws {
        let (blockID, document) = largeListDocument(targetIndex: 50_000)
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)), notify: false)
        let insertedSelection = try XCTUnwrap(view.insertBlockBelowCurrentBlock())
        guard case let .cursor(insertedCursor) = insertedSelection else {
            XCTFail("Expected inserted cursor selection")
            return
        }
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: insertedCursor.blockID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        store.resetCounts()

        textView.string = "Next item"
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [insertedCursor.blockID])
        XCTAssertEqual(store.block(withID: insertedCursor.blockID)?.text, "Next item")
    }

    func testStoreBackedDeleteInsertedLargeBlockDoesNotReadFullDocumentSnapshot() throws {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: index == targetIndex ? "Paragraph" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)), notify: false)
        let insertedSelection = try XCTUnwrap(view.insertBlockBelowCurrentBlock())
        guard case let .cursor(insertedCursor) = insertedSelection else {
            XCTFail("Expected inserted cursor selection")
            return
        }
        store.resetCounts()

        _ = view.deleteCurrentEmptyBlockForBackspaceOrDelete()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.deletedBlockIDs, [[insertedCursor.blockID]])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)))
    }

    func testStoreBackedDeleteWithMutationCallbackDoesNotReadFullDocumentSnapshot() throws {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: index == targetIndex ? "Paragraph" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)), notify: false)
        guard case .cursor = view.insertBlockBelowCurrentBlock() else {
            XCTFail("Expected inserted cursor selection")
            return
        }
        store.resetCounts()
        mutations = []

        _ = view.deleteCurrentEmptyBlockForBackspaceOrDelete()

        XCTAssertEqual(mutations.count, 1)
        guard case let .deleteBlocks(deletedIDs) = mutations.first else {
            XCTFail("Expected a delete-block mutation")
            return
        }
        XCTAssertEqual(deletedIDs, store.deletedBlockIDs.first)
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.deletedBlockIDs.count, 1)
    }

    func testStoreBackedChecklistToggleDoesNotReadFullDocumentSnapshot() {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                kind: index == targetIndex ? .checklistItem(isChecked: false) : .paragraph,
                text: index == targetIndex ? "Task" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4)), notify: false)
        store.resetCounts()

        _ = view.toggleChecklistItem()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.block(withID: blockID)?.kind, .checklistItem(isChecked: true))
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4)))
    }

    func testStoreBackedUndoRedoInsertedLargeBlockDoesNotReadFullDocumentSnapshot() throws {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: index == targetIndex ? "Paragraph" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let undoController = BlockInputUndoController()
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store, undoController: undoController))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)), notify: false)
        let insertedSelection = try XCTUnwrap(view.insertBlockBelowCurrentBlock())
        guard case let .cursor(insertedCursor) = insertedSelection else {
            XCTFail("Expected inserted cursor selection")
            return
        }
        store.resetCounts()

        _ = view.undoStructuralEdit()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.deletedBlockIDs, [[insertedCursor.blockID]])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)))
        store.resetCounts()

        _ = view.redoStructuralEdit()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, targetIndex + 1)
        XCTAssertEqual(store.insertedBlockBatches[0].blocks.first?.id, insertedCursor.blockID)
        XCTAssertEqual(view.selection, insertedSelection)
    }

    func testStoreBackedKeyboardUndoSkipsTextUndoSnapshotBeforeStructuralUndo() throws {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                text: index == targetIndex ? "Paragraph" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let undoController = BlockInputUndoController()
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store, undoController: undoController))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)), notify: false)
        let insertedSelection = try XCTUnwrap(view.insertBlockBelowCurrentBlock())
        guard case let .cursor(insertedCursor) = insertedSelection else {
            XCTFail("Expected inserted cursor selection")
            return
        }
        store.resetCounts()

        XCTAssertTrue(view.performUndoShortcut(.undo))

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.deletedBlockIDs, [[insertedCursor.blockID]])
    }

    func testMountedLargeListInsertionKeepsFollowingRowsVisible() throws {
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            let id = BlockInputBlockID(rawValue: "large-\(index)")
            switch index {
            case 3:
                return BlockInputBlock(id: id, kind: .bulletedListItem, text: "Bullet block 3")
            case 4:
                return BlockInputBlock(id: id, kind: .numberedListItem(start: 5), text: "Numbered block 4")
            case 5:
                return BlockInputBlock(id: id, kind: .checklistItem(isChecked: false), text: "Checklist block 5")
            default:
                return BlockInputBlock(id: id, text: "Block \(index)")
            }
        })
        let store = DocumentReadCountingStore(document: document)
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        mounted.view.applySelection(.cursor(BlockInputCursor(
            blockID: BlockInputBlockID(rawValue: "large-3"),
            utf16Offset: "Bullet block 3".utf16.count
        )), notify: false)
        store.resetCounts()

        let insertedSelection = try XCTUnwrap(mounted.view.insertBlockBelowCurrentBlock())
        guard case let .cursor(insertedCursor) = insertedSelection else {
            XCTFail("Expected inserted cursor selection")
            return
        }

        let insertedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 4))
        let numberedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 5))
        XCTAssertEqual(insertedItem.representedBlockID, insertedCursor.blockID)
        XCTAssertEqual(insertedItem.currentText, "")
        XCTAssertEqual(numberedItem.representedBlockID, BlockInputBlockID(rawValue: "large-4"))
        XCTAssertEqual(numberedItem.currentText, "Numbered block 4")
        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertLessThanOrEqual(store.indexLookupCount, 3)
    }

    func testMountedLargeInsertionResizesShiftedMixedRows() throws {
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            let id = BlockInputBlockID(rawValue: "large-\(index)")
            switch index {
            case 0:
                return BlockInputBlock(id: id, text: "Paragraph block 0")
            case 1:
                return BlockInputBlock(id: id, kind: .heading(level: 1), text: "Heading block 1")
            case 2:
                return BlockInputBlock(id: id, text: "Test")
            default:
                return BlockInputBlock(id: id, text: "Block \(index)")
            }
        })
        let store = DocumentReadCountingStore(document: document)
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        let originalHeadingHeight = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1)).view.frame.height
        let originalParagraphHeight = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2)).view.frame.height
        mounted.view.applySelection(.cursor(BlockInputCursor(
            blockID: BlockInputBlockID(rawValue: "large-0"),
            utf16Offset: "Paragraph block 0".utf16.count
        )), notify: false)

        _ = try XCTUnwrap(mounted.view.insertBlockBelowCurrentBlock())

        let shiftedHeadingItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let shiftedParagraphItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 3))
        XCTAssertEqual(shiftedHeadingItem.representedBlockID, BlockInputBlockID(rawValue: "large-1"))
        XCTAssertEqual(shiftedParagraphItem.representedBlockID, BlockInputBlockID(rawValue: "large-2"))
        XCTAssertEqual(shiftedHeadingItem.view.frame.height, originalHeadingHeight, accuracy: 0.5)
        XCTAssertEqual(shiftedParagraphItem.view.frame.height, originalParagraphHeight, accuracy: 0.5)
    }

    private func largeListDocument(targetIndex: Int) -> (BlockInputBlockID, BlockInputDocument) {
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                kind: index == targetIndex ? .bulletedListItem : .paragraph,
                text: index == targetIndex ? "List item" : "Block \(index)"
            )
        })
        return (blockID, document)
    }
}
