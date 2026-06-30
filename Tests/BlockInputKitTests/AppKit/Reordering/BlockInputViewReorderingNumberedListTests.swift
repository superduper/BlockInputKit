import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputReorderNumberingTests: XCTestCase {
    func testCollectionDropTargetKeepsAdjacentForwardMoveInsteadOfNoOp() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three")
        ])))

        let targetIndex = view.collectionDropTargetIndex(
            forBlockID: secondID,
            proposedItemIndex: 2
        )

        XCTAssertEqual(targetIndex, 2)
    }

    func testAcceptDropSwapsAdjacentNestedNumberedItemsWhenDraggingFirstBelowSecond() throws {
        let parentID = BlockInputBlockID(rawValue: "parent")
        let firstChildID = BlockInputBlockID(rawValue: "first-child")
        let secondChildID = BlockInputBlockID(rawValue: "second-child")
        let nextID = BlockInputBlockID(rawValue: "next")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: parentID, kind: .numberedListItem(start: 1), text: "Parent"),
            BlockInputBlock(id: firstChildID, kind: .numberedListItem(start: 1), text: "First", indentationLevel: 1),
            BlockInputBlock(id: secondChildID, kind: .numberedListItem(start: 2), text: "Second", indentationLevel: 1),
            BlockInputBlock(id: nextID, kind: .numberedListItem(start: 2), text: "Next")
        ])
        let secondAttributes = try XCTUnwrap(mounted.view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 2, section: 0)
        ))
        let collectionLocation = NSPoint(x: secondAttributes.frame.midX, y: secondAttributes.frame.maxY - 1)
        let windowLocation = mounted.view.collectionView.convert(collectionLocation, to: nil)

        let accepted = mounted.view.collectionView(
            mounted.view.collectionView,
            acceptDrop: BlockInputDraggingInfo(blockID: firstChildID, location: windowLocation),
            indexPath: IndexPath(item: 0, section: 0),
            dropOperation: .before
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [parentID, secondChildID, firstChildID, nextID])
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 2)
        ])
        XCTAssertEqual(mounted.view.document.blocks.map(\.indentationLevel), [0, 1, 1, 0])
    }

    func testAcceptDropMovesNestedNumberedItemUnderNextParentAtAdjacentInsertionBoundary() throws {
        let firstParentID = BlockInputBlockID(rawValue: "first-parent")
        let firstChildID = BlockInputBlockID(rawValue: "first-child")
        let secondChildID = BlockInputBlockID(rawValue: "second-child")
        let secondParentID = BlockInputBlockID(rawValue: "second-parent")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstParentID, kind: .numberedListItem(start: 1), text: "First parent"),
            BlockInputBlock(id: firstChildID, kind: .numberedListItem(start: 1), text: "First child", indentationLevel: 1),
            BlockInputBlock(id: secondChildID, kind: .numberedListItem(start: 2), text: "Second child", indentationLevel: 1),
            BlockInputBlock(id: secondParentID, kind: .numberedListItem(start: 2), text: "Second parent")
        ])
        let secondParentAttributes = try XCTUnwrap(mounted.view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 3, section: 0)
        ))
        let collectionLocation = NSPoint(x: secondParentAttributes.frame.midX, y: secondParentAttributes.frame.maxY - 1)
        let windowLocation = mounted.view.collectionView.convert(collectionLocation, to: nil)

        let accepted = mounted.view.collectionView(
            mounted.view.collectionView,
            acceptDrop: BlockInputDraggingInfo(blockID: secondChildID, location: windowLocation),
            indexPath: IndexPath(item: 0, section: 0),
            dropOperation: .before
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [firstParentID, firstChildID, secondParentID, secondChildID])
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 1)
        ])
        XCTAssertEqual(mounted.view.document.blocks.map(\.indentationLevel), [0, 1, 0, 1])
    }

    func testMoveNumberedSubitemPublishesRenumberedBlocksToStore() {
        let firstParentID = BlockInputBlockID(rawValue: "first-parent")
        let firstChildID = BlockInputBlockID(rawValue: "first-child")
        let secondParentID = BlockInputBlockID(rawValue: "second-parent")
        let secondChildID = BlockInputBlockID(rawValue: "second-child")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstParentID, kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: firstChildID, kind: .numberedListItem(start: 1), text: "Child", indentationLevel: 1),
            BlockInputBlock(id: secondParentID, kind: .numberedListItem(start: 2), text: "Second"),
            BlockInputBlock(id: secondChildID, kind: .numberedListItem(start: 1), text: "Moved", indentationLevel: 1)
        ]))
        let view = BlockInputView()
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        store.resetCounts()

        _ = view.moveBlock(blockID: secondChildID, to: 2)

        XCTAssertEqual(store.document.blocks.map(\.id), [firstParentID, firstChildID, secondChildID, secondParentID])
        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 2)
        ])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.movedBlocks.map(\.id), [secondChildID])
        XCTAssertEqual(store.movedBlocks.map(\.index), [2])
        XCTAssertEqual(store.replaceBlockIDs, [secondChildID])
        XCTAssertEqual(mutations, [
            .moveBlock(secondChildID, index: 2),
            .replaceBlock(store.document.blocks[2])
        ])
    }

    func testMoveTopLevelNumberedItemPublishesAllRenumberedBlocksToStore() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three")
        ]))
        let view = BlockInputView()
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        store.resetCounts()

        _ = view.moveBlock(blockID: secondID, to: 2)

        XCTAssertEqual(store.document.blocks.map(\.id), [firstID, thirdID, secondID])
        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 3)
        ])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.movedBlocks.map(\.id), [secondID])
        XCTAssertEqual(store.movedBlocks.map(\.index), [2])
        XCTAssertEqual(store.replaceBlockIDs, [thirdID, secondID])
        XCTAssertEqual(mutations, [
            .moveBlock(secondID, index: 2),
            .replaceBlock(store.document.blocks[1]),
            .replaceBlock(store.document.blocks[2])
        ])
    }

    func testMoveTopLevelNumberedItemAboveSiblingPublishesMovedMarkerReplacement() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three")
        ]))
        let view = BlockInputView()
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        store.resetCounts()

        _ = view.moveBlock(blockID: thirdID, to: 0)

        XCTAssertEqual(store.document.blocks.map(\.id), [thirdID, firstID, secondID])
        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 3)
        ])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.movedBlocks.map(\.id), [thirdID])
        XCTAssertEqual(store.movedBlocks.map(\.index), [0])
        XCTAssertEqual(store.replaceBlockIDs, [thirdID, firstID, secondID])
        XCTAssertEqual(mutations, [
            .moveBlock(thirdID, index: 0),
            .replaceBlock(store.document.blocks[0]),
            .replaceBlock(store.document.blocks[1]),
            .replaceBlock(store.document.blocks[2])
        ])
    }

    func testMoveTopLevelNumberedItemAboveMiddleSiblingPublishesMovedMarkerReplacement() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three")
        ]))
        let view = BlockInputView()
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        store.resetCounts()

        _ = view.moveBlock(blockID: thirdID, to: 1)

        XCTAssertEqual(store.document.blocks.map(\.id), [firstID, thirdID, secondID])
        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 3)
        ])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.movedBlocks.map(\.id), [thirdID])
        XCTAssertEqual(store.movedBlocks.map(\.index), [1])
        XCTAssertEqual(store.replaceBlockIDs, [thirdID, secondID])
        XCTAssertEqual(mutations, [
            .moveBlock(thirdID, index: 1),
            .replaceBlock(store.document.blocks[1]),
            .replaceBlock(store.document.blocks[2])
        ])
    }

    func testMoveFirstTopLevelNumberedItemBelowSiblingPublishesRenumberedRunToStore() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "One"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Two"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Three")
        ]))
        let view = BlockInputView()
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        store.resetCounts()

        _ = view.moveBlock(blockID: firstID, to: 2)

        XCTAssertEqual(store.document.blocks.map(\.id), [secondID, thirdID, firstID])
        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 3)
        ])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.movedBlocks.map(\.id), [firstID])
        XCTAssertEqual(store.movedBlocks.map(\.index), [2])
        XCTAssertEqual(store.replaceBlockIDs, [secondID, thirdID, firstID])
        XCTAssertEqual(mutations, [
            .moveBlock(firstID, index: 2),
            .replaceBlock(store.document.blocks[0]),
            .replaceBlock(store.document.blocks[1]),
            .replaceBlock(store.document.blocks[2])
        ])
    }

    func testMoveParagraphDoesNotPublishReplacementForUnchangedNumberedList() {
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let firstListID = BlockInputBlockID(rawValue: "first-list")
        let childID = BlockInputBlockID(rawValue: "child")
        let secondListID = BlockInputBlockID(rawValue: "second-list")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: paragraphID, text: "Paragraph"),
            BlockInputBlock(id: firstListID, kind: .numberedListItem(start: 4), text: "Four"),
            BlockInputBlock(id: childID, kind: .numberedListItem(start: 7), text: "Seven", indentationLevel: 1),
            BlockInputBlock(id: secondListID, kind: .numberedListItem(start: 5), text: "Five")
        ]))
        let view = BlockInputView()
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        store.resetCounts()

        _ = view.moveBlock(blockID: paragraphID, to: 3)

        XCTAssertEqual(store.document.blocks.map(\.id), [firstListID, childID, secondListID, paragraphID])
        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .numberedListItem(start: 4),
            .numberedListItem(start: 7),
            .numberedListItem(start: 5),
            .paragraph
        ])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.movedBlocks.map(\.id), [paragraphID])
        XCTAssertEqual(store.movedBlocks.map(\.index), [3])
        XCTAssertEqual(store.replaceBlockIDs, [])
        XCTAssertEqual(mutations, [.moveBlock(paragraphID, index: 3)])
    }

    func testMoveParagraphBeforeMergedNumberedRunsPublishesRenumberedSourceList() {
        let firstListID = BlockInputBlockID(rawValue: "first-list")
        let separatorID = BlockInputBlockID(rawValue: "separator")
        let secondListID = BlockInputBlockID(rawValue: "second-list")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstListID, kind: .numberedListItem(start: 4), text: "Four"),
            BlockInputBlock(id: separatorID, text: "Separator"),
            BlockInputBlock(id: secondListID, kind: .numberedListItem(start: 9), text: "Nine")
        ]))
        let view = BlockInputView()
        var mutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        store.resetCounts()

        _ = view.moveBlock(blockID: separatorID, to: 0)

        XCTAssertEqual(store.document.blocks.map(\.id), [separatorID, firstListID, secondListID])
        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .paragraph,
            .numberedListItem(start: 4),
            .numberedListItem(start: 5)
        ])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.movedBlocks.map(\.id), [separatorID])
        XCTAssertEqual(store.movedBlocks.map(\.index), [0])
        XCTAssertEqual(store.replaceBlockIDs, [secondListID])
        XCTAssertEqual(mutations, [
            .moveBlock(separatorID, index: 0),
            .replaceBlock(store.document.blocks[2])
        ])
    }
}
