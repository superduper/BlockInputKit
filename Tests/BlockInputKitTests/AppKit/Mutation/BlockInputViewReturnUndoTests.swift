import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewReturnUndoTests: XCTestCase {
    func testReturnAtFrontOfHeadingUsesInsertBlockStructuralUndoAction() {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
            ]),
            undoController: undoController
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)

        _ = view.insertBlockBelowCurrentBlock()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
        ])
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .paragraph))
        XCTAssertEqual(view.document.blocks[1].kind, .heading(level: 2))
        XCTAssertEqual(view.document.blocks[1].text, "Heading")
        XCTAssertEqual(redo?.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testReturnAtFrontOfNumberedListUndoRestoresNormalizedFollowingBlock() {
        let blockID = BlockInputBlockID(rawValue: "number")
        let nextID = BlockInputBlockID(rawValue: "next")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .numberedListItem(start: 3), text: "Item"),
                BlockInputBlock(id: nextID, kind: .numberedListItem(start: 4), text: "Next")
            ]),
            undoController: undoController
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)

        _ = view.insertBlockBelowCurrentBlock()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .numberedListItem(start: 3), text: "Item"),
            BlockInputBlock(id: nextID, kind: .numberedListItem(start: 4), text: "Next")
        ])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .numberedListItem(start: 3)))
        XCTAssertEqual(view.document.blocks[1].kind, .numberedListItem(start: 4))
        XCTAssertEqual(view.document.blocks[1].text, "Item")
        XCTAssertEqual(view.document.blocks[2], BlockInputBlock(id: nextID, kind: .numberedListItem(start: 5), text: "Next"))
    }

    func testReturnInEmptyFormattedBlockUsesUnformatStructuralUndoAction() {
        let blockID = BlockInputBlockID(rawValue: "quote")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .quote)
            ]),
            undoController: undoController
        ))
        view.focus(blockID: blockID)

        _ = view.insertBlockBelowCurrentBlock()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Unformat Block")
        XCTAssertEqual(view.document.blocks, [BlockInputBlock(id: blockID, kind: .quote)])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Unformat Block")
        XCTAssertEqual(view.document.blocks, [BlockInputBlock(id: blockID, kind: .paragraph)])
    }

    func testReturnInListBlockUsesInsertBlockStructuralUndoAction() {
        let blockID = BlockInputBlockID(rawValue: "bullet")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "BeforeAfter")
            ]),
            undoController: undoController
        ))
        view.applySelection(.text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 6, length: 1))), notify: false)

        _ = view.insertBlockBelowCurrentBlock()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "BeforeAfter")
        ])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Before"))
        XCTAssertEqual(view.document.blocks[1].kind, .bulletedListItem)
        XCTAssertEqual(view.document.blocks[1].text, "fter")
    }

    func testReturnOnEmptyInlineListLineUsesInsertBlockStructuralUndoAction() {
        let blockID = BlockInputBlockID(rawValue: "bullet")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Before\n")
            ]),
            undoController: undoController
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 7)), notify: false)

        _ = view.insertBlockBelowCurrentBlock()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Before\n")
        ])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Before"))
        XCTAssertEqual(view.document.blocks[1].kind, .bulletedListItem)
        XCTAssertEqual(view.document.blocks[1].text, "")
    }

    func testReturnInChecklistItemUsesInsertBlockStructuralUndoAction() {
        let blockID = BlockInputBlockID(rawValue: "checklist")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: true), text: "BeforeAfter")
            ]),
            undoController: undoController
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)), notify: false)

        _ = view.insertBlockBelowCurrentBlock()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: true), text: "BeforeAfter")
        ])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(
            id: blockID,
            kind: .checklistItem(isChecked: true),
            text: "Before"
        ))
        XCTAssertEqual(view.document.blocks[1].kind, .checklistItem(isChecked: false))
        XCTAssertEqual(view.document.blocks[1].text, "After")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testReturnOnIndentedTrailingListLineInsertsIndentedSiblingBlock() {
        let blockID = BlockInputBlockID(rawValue: "bullet")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(
                    id: blockID,
                    kind: .bulletedListItem,
                    text: "Before\n",
                    lineIndentationLevels: [0, 1]
                )
            ]),
            undoController: undoController
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 7)), notify: false)

        _ = view.insertBlockBelowCurrentBlock()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(
                id: blockID,
                kind: .bulletedListItem,
                text: "Before\n",
                lineIndentationLevels: [0, 1]
            )
        ])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Before"))
        XCTAssertEqual(view.document.blocks[1].kind, .bulletedListItem)
        XCTAssertEqual(view.document.blocks[1].indentationLevel, 1)
        XCTAssertEqual(view.document.blocks[1].text, "")
    }

    func testReturnOnIndentedEmptyChecklistItemUsesOutdentStructuralUndoAction() {
        let blockID = BlockInputBlockID(rawValue: "checklist")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: false), indentationLevel: 1)
            ]),
            undoController: undoController
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)

        _ = view.insertBlockBelowCurrentBlock()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Outdent Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: false), indentationLevel: 1)
        ])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Outdent Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: false))
        ])
    }

    func testReturnOnIndentedEmptyNumberedListItemContinuesParentSequence() {
        let childID = BlockInputBlockID(rawValue: "child")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "parent", kind: .numberedListItem(start: 1), text: "Parent"),
            BlockInputBlock(id: childID, kind: .numberedListItem(start: 1), indentationLevel: 1)
        ])))
        view.applySelection(.cursor(BlockInputCursor(blockID: childID, utf16Offset: 0)), notify: false)

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(view.document.blocks[1].kind, .numberedListItem(start: 2))
        XCTAssertEqual(view.document.blocks[1].indentationLevel, 0)
        XCTAssertEqual(view.document.blocks[1].lineIndentationLevels, [])
    }

    func testReturnOnPerLineIndentedEmptyNumberedListItemOutdentsLine() {
        let childID = BlockInputBlockID(rawValue: "child")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "parent", kind: .numberedListItem(start: 1), text: "Parent"),
                BlockInputBlock(id: childID, kind: .numberedListItem(start: 1), lineIndentationLevels: [1])
            ]),
            undoController: undoController
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: childID, utf16Offset: 0)), notify: false)

        _ = view.insertBlockBelowCurrentBlock()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Outdent Block")
        XCTAssertEqual(view.document.blocks[1], BlockInputBlock(
            id: childID,
            kind: .numberedListItem(start: 1),
            lineIndentationLevels: [1]
        ))

        _ = view.redoStructuralEdit()

        XCTAssertEqual(view.document.blocks[1].kind, .numberedListItem(start: 2))
        XCTAssertEqual(view.document.blocks[1].indentationLevel, 0)
        XCTAssertEqual(view.document.blocks[1].lineIndentationLevels, [])
    }

    func testReturnOnPerLineIndentedEmptyNumberedListItemContinuesPerLineSiblingSequence() {
        let childID = BlockInputBlockID(rawValue: "child")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "parent", kind: .numberedListItem(start: 1), text: "Parent"),
            BlockInputBlock(
                id: "previous-child",
                kind: .numberedListItem(start: 1),
                text: "Previous child",
                lineIndentationLevels: [1]
            ),
            BlockInputBlock(id: childID, kind: .numberedListItem(start: 1), lineIndentationLevels: [2])
        ])))
        view.applySelection(.cursor(BlockInputCursor(blockID: childID, utf16Offset: 0)), notify: false)

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(view.document.blocks[2].kind, .numberedListItem(start: 2))
        XCTAssertEqual(view.document.blocks[2].lineIndentationLevels, [1])
    }

    func testReturnOnMiddleEmptyInlineListLineRestoresSplitWithStructuralUndo() {
        let blockID = BlockInputBlockID(rawValue: "number")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .numberedListItem(start: 4), text: "First\n\nThird")
            ]),
            undoController: undoController
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)), notify: false)

        _ = view.insertBlockBelowCurrentBlock()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .numberedListItem(start: 4), text: "First\n\nThird")
        ])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Insert Block")
        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .numberedListItem(start: 4), text: "First"))
        XCTAssertEqual(view.document.blocks[1].kind, .numberedListItem(start: 5))
        XCTAssertEqual(view.document.blocks[1].text, "\nThird")
    }

    func testReturnAtEndOfNumberedListItemIsUndoable() {
        let blockID = BlockInputBlockID(rawValue: "number")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .numberedListItem(start: 1), text: "first")
            ]),
            undoController: undoController
        ))
        // Cursor at end-of-text triggers the sibling-insertion granular path
        view.applySelection(
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
            notify: false
        )

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(view.document.blocks.count, 2, "Return should insert a new block")

        // Undo should remove the inserted block and restore the original
        _ = view.undoStructuralEdit()

        XCTAssertEqual(view.document.blocks.count, 1, "Undo should restore 1-block document")
        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(view.document.blocks[0].text, "first")
    }

    func testReturnInNumberedListIsUndoableWithStore() {
        let store = BlockInputMemoryDocumentStore()
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(kind: .numberedListItem(start: 1), text: "first")
        ]))
        guard let firstBlock = store.block(at: 0) else {
            XCTFail("Store should have a block at index 0")
            return
        }
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController()
        ))
        view.applySelection(
            .cursor(BlockInputCursor(blockID: firstBlock.id, utf16Offset: firstBlock.utf16Length)),
            notify: false
        )

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(store.loadedBlockCount, 2, "Return should insert a new block")

        // Undo should remove the inserted block
        _ = view.undoStructuralEdit()

        XCTAssertEqual(store.loadedBlockCount, 1, "Undo should restore 1-block document")
        XCTAssertEqual(store.block(at: 0)?.text, "first")
    }

    func testMountedTrailingQuoteLineExitDoesNotOverlapFollowingBlock() throws {
        let quoteID = BlockInputBlockID(rawValue: "quote")
        let trailingID = BlockInputBlockID(rawValue: "trailing")
        // Two trailing blank lines plus a caret at the very end are the escape gesture under the
        // new threshold; this third Return exits the quote into a paragraph below.
        let quoteText = "Focus, selection, return, delete, and Cmd+A are coordinated across blocks.\nd\nd\n\n"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "intro", text: "Each visible block owns its own AppKit text input."),
            BlockInputBlock(id: quoteID, kind: .quote, text: quoteText),
            BlockInputBlock(id: trailingID, text: "Try slash query: /code")
        ])
        mounted.view.applySelection(.cursor(BlockInputCursor(
            blockID: quoteID,
            utf16Offset: (quoteText as NSString).length
        )), notify: false)

        _ = mounted.view.insertBlockBelowCurrentBlock()
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), ["intro", quoteID, mounted.view.document.blocks[2].id, trailingID])
        let quoteItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let insertedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let trailingItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 3))

        XCTAssertLessThanOrEqual(quoteItem.view.frame.maxY, insertedItem.view.frame.minY + 0.5)
        XCTAssertLessThanOrEqual(insertedItem.view.frame.maxY, trailingItem.view.frame.minY + 0.5)
    }
}
