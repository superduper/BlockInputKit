import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTextCommandReturnTests: XCTestCase {
    func testReturnCommandInsertsBlockThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0].id, blockID)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testReturnCommandAtFrontOfHeadingMovesHeadingDownThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "heading")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .heading(level: 2), text: "Heading")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .paragraph))
        XCTAssertEqual(view.document.blocks[1].kind, .heading(level: 2))
        XCTAssertEqual(view.document.blocks[1].text, "Heading")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testReturnCommandAtFrontOfQuoteMovesQuoteDownThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "quote")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .quote, text: "Quoted")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .paragraph))
        XCTAssertEqual(view.document.blocks[1].kind, .quote)
        XCTAssertEqual(view.document.blocks[1].text, "Quoted")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testReturnCommandAtFrontOfListItemMovesListItemDownThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "bullet")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Item", indentationLevel: 1)
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .bulletedListItem, indentationLevel: 1))
        XCTAssertEqual(view.document.blocks[1].kind, .bulletedListItem)
        XCTAssertEqual(view.document.blocks[1].text, "Item")
        XCTAssertEqual(view.document.blocks[1].indentationLevel, 1)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testReturnCommandConvertsCodeFenceThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "code")
        let undoController = BlockInputUndoController()
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "``` swift")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        store.resetCounts()

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"))
        ])
        XCTAssertEqual(store.document.blocks, [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"))
        ])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [blockID])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))

        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Format Block")
        XCTAssertEqual(store.document.blocks, [
            BlockInputBlock(id: blockID, text: "``` swift")
        ])

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Format Block")
        XCTAssertEqual(store.document.blocks, [
            BlockInputBlock(id: blockID, kind: .code(language: "swift"))
        ])
    }

    func testReturnCommandInRawMarkdownEmptyLineStaysInlineThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "raw")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .rawMarkdown, text: "Before\n\nAfter")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 7, length: 0))

        XCTAssertFalse(view.blockItemDidRequestReturn(item, blockID: blockID))
        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .rawMarkdown, text: "Before\n\nAfter")
        ])
    }

    func testReturnCommandContinuesListThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "First", indentationLevel: 1)
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0].kind, .bulletedListItem)
        XCTAssertEqual(view.document.blocks[0].indentationLevel, 1)
        XCTAssertEqual(view.document.blocks[0].text, "First")
        XCTAssertEqual(view.document.blocks[1].kind, .bulletedListItem)
        XCTAssertEqual(view.document.blocks[1].indentationLevel, 1)
        XCTAssertEqual(view.document.blocks[1].text, "")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))

        _ = view.undoStructuralEdit()

        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(view.document.blocks[0].text, "First")

        _ = view.redoStructuralEdit()

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0].text, "First")
        XCTAssertEqual(view.document.blocks[1].kind, .bulletedListItem)
    }

    func testReturnCommandInChecklistCreatesSiblingChecklistBlockThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: false), text: "First")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: false), text: "First"))
        XCTAssertEqual(view.document.blocks[1].kind, .checklistItem(isChecked: false))
        XCTAssertEqual(view.document.blocks[1].text, "")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testReturnCommandInChecklistReplacesSelectionThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: true), text: "BeforeAfter")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 6, length: 5))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: true), text: "Before"))
        XCTAssertEqual(view.document.blocks[1].kind, .checklistItem(isChecked: false))
        XCTAssertEqual(view.document.blocks[1].text, "")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testReturnCommandContinuesCurrentIndentationThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(
                    id: blockID,
                    kind: .bulletedListItem,
                    text: "One",
                    indentationLevel: 1
                )
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0].text, "One")
        XCTAssertEqual(view.document.blocks[1].kind, .bulletedListItem)
        XCTAssertEqual(view.document.blocks[1].indentationLevel, 1)

        _ = view.undoStructuralEdit()

        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "One", indentationLevel: 1)
        ])

        _ = view.redoStructuralEdit()

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[1].indentationLevel, 1)
    }

    func testReturnCommandReplacingSelectedTextCreatesSiblingListItemThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(
                id: blockID,
                kind: .bulletedListItem,
                text: "BeforeMiddleAfter",
                indentationLevel: 1
            )
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 6, length: 6))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(
            id: blockID,
            kind: .bulletedListItem,
            text: "Before",
            indentationLevel: 1
        ))
        XCTAssertEqual(view.document.blocks[1].kind, .bulletedListItem)
        XCTAssertEqual(view.document.blocks[1].text, "After")
        XCTAssertEqual(view.document.blocks[1].indentationLevel, 1)
    }

    func testReturnCommandSplitsNumberedListIntoSiblingNumberedBlockThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(
                id: blockID,
                kind: .numberedListItem(start: 4),
                text: "BeforeAfter"
            )
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[0], BlockInputBlock(
            id: blockID,
            kind: .numberedListItem(start: 4),
            text: "Before"
        ))
        XCTAssertEqual(view.document.blocks[1].kind, .numberedListItem(start: 5))
        XCTAssertEqual(view.document.blocks[1].text, "After")
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
    }

    func testReturnCommandOnEmptyListBlockExitsToParagraphThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem)
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks, [BlockInputBlock(id: blockID, kind: .paragraph)])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testReturnCommandOnIndentedEmptyListBlockOutdentsThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(
                    id: blockID,
                    kind: .bulletedListItem,
                    indentationLevel: 2
                )
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(
                id: blockID,
                kind: .bulletedListItem,
                indentationLevel: 1
            )
        ])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))

        _ = view.undoStructuralEdit()

        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(
                id: blockID,
                kind: .bulletedListItem,
                indentationLevel: 2
            )
        ])
    }

    func testReturnCommandExitsEmptyFormattedBlockThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .quote)
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(view.document.blocks, [BlockInputBlock(id: blockID, kind: .paragraph)])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }
}
