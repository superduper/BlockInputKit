import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputTextCommandTabTests: XCTestCase {
    @MainActor
    func testTabCommandsIndentAndOutdentThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "First")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(view.document.blocks[0].indentationLevel, 1)

        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        XCTAssertEqual(view.document.blocks[0].indentationLevel, 0)
    }

    @MainActor
    func testTabCommandsDoNotIndentRawMarkdownThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "raw")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .rawMarkdown, text: "| A |\n| - |")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertEqual(view.document.blocks, [
            BlockInputBlock(id: blockID, kind: .rawMarkdown, text: "| A |\n| - |")
        ])
        XCTAssertEqual(textView.string, "| A |\n| - |")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    @MainActor
    func testDefaultConfigurationUndoAndRedoAppliesTabIndent() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "First")
            ])
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandZEvent()))
        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel, 0)
        XCTAssertTrue(textView.performKeyEquivalent(with: try commandShiftZEvent()))
        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel, 1)
    }

    @MainActor
    func testTabCommandsIndentAndOutdentSingleLineItemWhenCaretIsInsideText() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "First")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(view.document.blocks[0].indentationLevel, 1)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)))

        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertEqual(view.document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)))
    }

    @MainActor
    func testTabCommandStartsIndentedNumberedItemAtOne() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[1],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(view.document.blocks[1].kind, .numberedListItem(start: 1))
        XCTAssertEqual(view.document.blocks[1].indentationLevel, 1)
        XCTAssertEqual(BlockInputBlockItem.prefix(for: view.document.blocks[1].kind, indentationLevel: 1), "a.")
    }

    @MainActor
    func testNumberedListStartNormalizationUsesBoundedStoreReads() throws {
        let targetID = BlockInputBlockID(rawValue: "target")
        let blocks = (0..<220).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "previous-\(index)"),
                kind: .numberedListItem(start: index + 1),
                text: "Previous \(index)",
                indentationLevel: 2
            )
        } + [
            BlockInputBlock(id: targetID, kind: .numberedListItem(start: 221), text: "Target", indentationLevel: 2)
        ]
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: blocks))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: targetID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        store.resetCounts()

        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertEqual(store.document.block(withID: targetID)?.kind, .numberedListItem(start: 1))
        XCTAssertEqual(store.document.block(withID: targetID)?.indentationLevel, 1)
        XCTAssertLessThanOrEqual(store.blockAtReadIndexes.count, 130)
    }

    @MainActor
    func testOutdentNumberedLineContinuesPerLineSiblingSequence() throws {
        let targetID = BlockInputBlockID(rawValue: "target")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "parent", kind: .numberedListItem(start: 1), text: "Parent"),
            BlockInputBlock(
                id: "previous-child",
                kind: .numberedListItem(start: 1),
                text: "Previous child",
                lineIndentationLevels: [1]
            ),
            BlockInputBlock(
                id: targetID,
                kind: .numberedListItem(start: 1),
                text: "Target",
                lineIndentationLevels: [2]
            )
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[2],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertEqual(view.document.blocks[2].kind, .numberedListItem(start: 2))
        XCTAssertEqual(view.document.blocks[2].lineIndentationLevels, [1])
    }

    @MainActor
    func testOutdentNumberedItemRenumbersRemainingNestedSiblingsInStore() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 1), text: "Two", indentationLevel: 1),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 2), text: "Three", indentationLevel: 1)
        ]))
        let view = BlockInputView()
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: secondID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        store.resetCounts()

        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 1)
        ])
        XCTAssertEqual(store.document.blocks.map(\.indentationLevel), [0, 0, 1])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [secondID, thirdID])
        XCTAssertEqual(mutations, [
            .replaceBlock(store.document.blocks[1]),
            .replaceBlock(store.document.blocks[2])
        ])
    }

    @MainActor
    func testTabCommandRefreshesStaleStoreBackedItemAndClampsSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "list")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Stale text")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: blockID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 10, length: 0))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "New")
        ]))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(store.document.blocks[0].text, "New")
        XCTAssertEqual(store.document.blocks[0].indentationLevel, 1)
        XCTAssertEqual(textView.string, "New")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 3)))
    }

    @MainActor
    func testTabCommandRefreshesUnsynchronizedLargeDocumentCacheBeforeIndenting() throws {
        let insertionIndex = 10
        let targetIndex = 50_000
        let targetID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let insertedID = BlockInputBlockID(rawValue: "inserted")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                kind: .bulletedListItem,
                text: "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        store.insertBlocks([
            BlockInputBlock(id: insertedID, kind: .bulletedListItem, text: "Inserted")
        ], at: insertionIndex)
        view.markDocumentCacheUnsynchronized()
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: targetID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        store.resetCounts()

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [targetID])
        XCTAssertEqual(store.block(withID: targetID)?.indentationLevel, 1)
        XCTAssertEqual(view.document.blocks[insertionIndex].id, insertedID)
        XCTAssertEqual(view.document.blocks[targetIndex + 1].id, targetID)
        XCTAssertEqual(view.document.blocks[targetIndex + 1].indentationLevel, 1)
    }

    @MainActor
    func testTabCommandsDoNotMutatePlainBlocks() throws {
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
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertEqual(view.document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(view.document.blocks[0].text, "First")
        XCTAssertEqual(textView.string, "First")
    }

    @MainActor
    func testTabCommandsIndentAndOutdentCurrentLineInMultilineListBlock() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "One\nTwo\nThree")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(view.document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 1, 0])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4)))

        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4)))
    }

    @MainActor
    func testTabCommandsIndentAndOutdentCurrentLineWhenCaretIsInsideText() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "One\nTwo")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(view.document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 1])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)))

        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)))
        XCTAssertEqual(textView.string, "One\nTwo")
    }
}
