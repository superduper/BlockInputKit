import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputDocumentStoreTests: XCTestCase {
    func testMemoryDocumentStoreExposesBlocksAndIndexes() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]))

        XCTAssertEqual(store.loadedBlockCount, 2)
        XCTAssertEqual(store.block(at: 1)?.id, secondID)
        XCTAssertEqual(store.block(withID: firstID)?.text, "First")
        XCTAssertEqual(store.index(of: secondID), 1)
        XCTAssertNil(store.block(at: 2))
    }

    func testMemoryDocumentStoreReplacesDocument() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let replacementID = BlockInputBlockID(rawValue: "replacement")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First")
        ]))

        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: replacementID, text: "Replacement")
        ]))

        XCTAssertEqual(store.document.blocks.map(\.id), [replacementID])
        XCTAssertEqual(store.index(of: replacementID), 0)
        XCTAssertNil(store.index(of: firstID))
        XCTAssertEqual(store.block(withID: replacementID)?.text, "Replacement")
    }

    func testMemoryDocumentStoreAppliesGranularMutations() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]))

        store.replaceBlock(BlockInputBlock(id: firstID, text: "Updated"))
        store.insertBlocks([BlockInputBlock(id: thirdID, text: "Third")], at: 2)
        store.moveBlock(withID: thirdID, to: 0)
        store.deleteBlocks(withIDs: [secondID])

        XCTAssertEqual(store.document.blocks.map(\.id), [thirdID, firstID])
        XCTAssertEqual(store.document.blocks.map(\.text), ["Third", "Updated"])
        XCTAssertEqual(store.index(of: thirdID), 0)
        XCTAssertEqual(store.index(of: firstID), 1)
        XCTAssertNil(store.index(of: secondID))
        XCTAssertEqual(store.block(withID: thirdID)?.text, "Third")
    }

    func testMemoryDocumentStoreAppliesNumberedListMarkerTransactions() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let separateID = BlockInputBlockID(rawValue: "separate")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Second"),
            BlockInputBlock(id: "paragraph", text: "Paragraph"),
            BlockInputBlock(id: separateID, kind: .numberedListItem(start: 1), text: "Separate")
        ]))

        store.applyNumberedListMarkerTransaction(BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: 1,
                    endIndex: nil,
                    listRunStartIndex: 0,
                    indentationLevel: 0,
                    delta: 1
                )
            ],
            overrides: [
                BlockInputNumberedListMarkerOverride(blockID: firstID, start: 4, previousStart: 1)
            ]
        ))

        XCTAssertEqual(store.block(withID: firstID)?.kind, .numberedListItem(start: 4))
        XCTAssertEqual(store.block(withID: secondID)?.kind, .numberedListItem(start: 3))
        XCTAssertEqual(store.block(withID: separateID)?.kind, .numberedListItem(start: 1))
        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .numberedListItem(start: 4),
            .numberedListItem(start: 3),
            .paragraph,
            .numberedListItem(start: 1)
        ])
    }

    func testMemoryDocumentStoreStopsNestedMarkerAdjustmentAtLowerIndentationBoundary() {
        let otherParentChildID = BlockInputBlockID(rawValue: "other-parent-child")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "parent-one", kind: .numberedListItem(start: 1), text: "Parent one"),
            BlockInputBlock(id: "child-one", kind: .numberedListItem(start: 1), text: "Child one", indentationLevel: 1),
            BlockInputBlock(id: "child-two", kind: .numberedListItem(start: 2), text: "Child two", indentationLevel: 1),
            BlockInputBlock(id: "parent-two", kind: .numberedListItem(start: 2), text: "Parent two"),
            BlockInputBlock(id: otherParentChildID, kind: .numberedListItem(start: 1), text: "Other child", indentationLevel: 1)
        ]))

        store.applyNumberedListMarkerTransaction(BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: 2,
                    endIndex: nil,
                    listRunStartIndex: 1,
                    indentationLevel: 1,
                    delta: 1
                )
            ]
        ))

        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 1),
            .numberedListItem(start: 3),
            .numberedListItem(start: 2),
            .numberedListItem(start: 1)
        ])
        XCTAssertEqual(store.block(withID: otherParentChildID)?.kind, .numberedListItem(start: 1))
    }

    func testMemoryDocumentStoreReplacesAdjustedNumberedBlockWithoutDoubleApplyingMarkerTransaction() throws {
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Second")
        ]))
        store.applyNumberedListMarkerTransaction(BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: 1,
                    endIndex: nil,
                    listRunStartIndex: 0,
                    indentationLevel: 0,
                    delta: 1
                )
            ]
        ))
        var editedBlock = try XCTUnwrap(store.block(withID: secondID))
        editedBlock.text = "Edited"

        store.replaceBlock(editedBlock)

        XCTAssertEqual(store.block(withID: secondID)?.text, "Edited")
        XCTAssertEqual(store.block(withID: secondID)?.kind, .numberedListItem(start: 3))
        XCTAssertEqual(store.document.block(withID: secondID)?.kind, .numberedListItem(start: 3))
    }

    func testMemoryDocumentStoreCompactsPendingMarkerTransactionsBeforeMove() {
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: paragraphID, text: "Paragraph"),
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Second")
        ]))
        store.applyNumberedListMarkerTransaction(BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: 1,
                    endIndex: 2,
                    indentationLevel: 0,
                    delta: 1
                )
            ]
        ))

        store.moveBlock(withID: paragraphID, to: 2)

        XCTAssertEqual(store.document.blocks.map(\.id), [firstID, secondID, paragraphID])
        XCTAssertEqual(store.block(withID: firstID)?.kind, .numberedListItem(start: 2))
        XCTAssertEqual(store.block(withID: secondID)?.kind, .numberedListItem(start: 3))
    }

    func testMemoryDocumentStoreDropsFiniteMarkerAdjustmentWhenCoveredBlockIsDeleted() {
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Second"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Third")
        ]))
        store.applyNumberedListMarkerTransaction(BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: 1,
                    endIndex: 1,
                    indentationLevel: 0,
                    delta: 10
                )
            ]
        ))

        store.deleteBlocks(withIDs: [secondID])

        XCTAssertEqual(store.block(withID: thirdID)?.kind, .numberedListItem(start: 3))
        XCTAssertEqual(store.document.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 3)
        ])
    }

    func testMemoryDocumentStoreShiftsMarkerTransactionsForEveryDeletedDuplicateIDBlock() {
        let sharedID = BlockInputBlockID(rawValue: "shared")
        let fourthID = BlockInputBlockID(rawValue: "fourth")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: sharedID, kind: .numberedListItem(start: 2), text: "Duplicate one"),
            BlockInputBlock(id: sharedID, kind: .numberedListItem(start: 3), text: "Duplicate two"),
            BlockInputBlock(id: fourthID, kind: .numberedListItem(start: 4), text: "Fourth")
        ]))
        store.applyNumberedListMarkerTransaction(BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: 3,
                    endIndex: 3,
                    indentationLevel: 0,
                    delta: 10
                )
            ]
        ))

        store.deleteBlocks(withIDs: [sharedID, "missing"])

        XCTAssertEqual(store.document.blocks.map(\.id), ["first", fourthID])
        XCTAssertEqual(store.block(withID: fourthID)?.kind, .numberedListItem(start: 14))
    }

    func testMemoryDocumentStoreRemovesDeletedMarkerOverrides() {
        let replacedID = BlockInputBlockID(rawValue: "reused")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: replacedID, kind: .numberedListItem(start: 1), text: "Original")
        ]))
        store.applyNumberedListMarkerTransaction(BlockInputNumberedListMarkerTransaction(
            overrides: [
                BlockInputNumberedListMarkerOverride(blockID: replacedID, start: 9, previousStart: 1)
            ]
        ))

        store.deleteBlocks(withIDs: [replacedID])
        store.insertBlocks([
            BlockInputBlock(id: replacedID, kind: .numberedListItem(start: 1), text: "Reused")
        ], at: 0)

        XCTAssertEqual(store.block(withID: replacedID)?.kind, .numberedListItem(start: 1))
    }

    func testMemoryDocumentStoreUpdatesIndexesAfterMiddleInsertion() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let insertedID = BlockInputBlockID(rawValue: "inserted")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ]))

        store.insertBlocks([BlockInputBlock(id: insertedID, text: "Inserted")], at: 1)

        XCTAssertEqual(store.document.blocks.map(\.id), [firstID, insertedID, secondID, thirdID])
        XCTAssertEqual(store.index(of: firstID), 0)
        XCTAssertEqual(store.index(of: insertedID), 1)
        XCTAssertEqual(store.index(of: secondID), 2)
        XCTAssertEqual(store.index(of: thirdID), 3)
        XCTAssertEqual(store.block(withID: secondID)?.text, "Second")
    }

    func testMemoryDocumentStoreInsertionAtStartKeepsLeadingFrontMatterPinned() {
        let frontID = BlockInputBlockID(rawValue: "front")
        let insertedID = BlockInputBlockID(rawValue: "inserted")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "body", text: "Body")
        ]))

        store.insertBlocks([BlockInputBlock(id: insertedID, text: "Inserted")], at: 0)

        XCTAssertEqual(store.document.blocks.map(\.id), [frontID, insertedID, "body"])
        XCTAssertEqual(store.index(of: frontID), 0)
        XCTAssertEqual(store.index(of: insertedID), 1)
        XCTAssertEqual(store.block(withID: insertedID)?.text, "Inserted")
    }

    func testMemoryDocumentStoreMovePathsDoNotDisplaceLeadingFrontMatter() {
        let leadingID = BlockInputBlockID(rawValue: "leading")
        let duplicateID = BlockInputBlockID(rawValue: "duplicate")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: leadingID, kind: .frontMatter, text: "title: Leading"),
            BlockInputBlock(id: "body", text: "Body"),
            BlockInputBlock(id: duplicateID, kind: .frontMatter, text: "title: Duplicate")
        ]))

        store.moveBlock(withID: duplicateID, to: 0)
        store.moveBlockWithoutNormalizing(withID: duplicateID, to: 0)

        XCTAssertEqual(store.document.blocks.map(\.id), [leadingID, "body", duplicateID])
        XCTAssertEqual(store.index(of: leadingID), 0)
        XCTAssertEqual(store.index(of: duplicateID), 2)
    }

    func testMemoryDocumentStoreUpdatesIndexesAfterMiddleDeletion() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ]))

        store.deleteBlocks(withIDs: [secondID])

        XCTAssertEqual(store.document.blocks.map(\.id), [firstID, thirdID])
        XCTAssertEqual(store.index(of: firstID), 0)
        XCTAssertEqual(store.index(of: thirdID), 1)
        XCTAssertNil(store.index(of: secondID))
        XCTAssertEqual(store.block(withID: thirdID)?.text, "Third")
    }

    func testMemoryDocumentStoreUpdatesIndexesAfterMoves() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let fourthID = BlockInputBlockID(rawValue: "fourth")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third"),
            BlockInputBlock(id: fourthID, text: "Fourth")
        ]))

        store.moveBlock(withID: secondID, to: 3)

        XCTAssertEqual(store.document.blocks.map(\.id), [firstID, thirdID, fourthID, secondID])
        XCTAssertEqual(store.index(of: firstID), 0)
        XCTAssertEqual(store.index(of: thirdID), 1)
        XCTAssertEqual(store.index(of: fourthID), 2)
        XCTAssertEqual(store.index(of: secondID), 3)

        store.moveBlock(withID: fourthID, to: 0)

        XCTAssertEqual(store.document.blocks.map(\.id), [fourthID, firstID, thirdID, secondID])
        XCTAssertEqual(store.index(of: fourthID), 0)
        XCTAssertEqual(store.index(of: firstID), 1)
        XCTAssertEqual(store.index(of: thirdID), 2)
        XCTAssertEqual(store.index(of: secondID), 3)
    }

    func testMemoryDocumentStorePreservesFirstIndexWhenIDsAreDuplicated() {
        let sharedID = BlockInputBlockID(rawValue: "shared")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: sharedID, text: "First"),
            BlockInputBlock(id: sharedID, text: "Second")
        ]))

        XCTAssertEqual(store.index(of: sharedID), 0)
        XCTAssertEqual(store.block(withID: sharedID)?.text, "First")
    }

    func testMemoryDocumentStorePreservesFirstIndexWhenInsertedIDsAreDuplicated() {
        let sharedID = BlockInputBlockID(rawValue: "shared")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "First")
        ]))

        store.insertBlocks([
            BlockInputBlock(id: sharedID, text: "Inserted first"),
            BlockInputBlock(id: sharedID, text: "Inserted second")
        ], at: 1)

        XCTAssertEqual(store.index(of: sharedID), 1)
        XCTAssertEqual(store.block(withID: sharedID)?.text, "Inserted first")
    }

    func testMemoryDocumentStorePreservesFirstIndexWhenMovingDuplicateIDs() {
        let sharedID = BlockInputBlockID(rawValue: "shared")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: sharedID, text: "First"),
            BlockInputBlock(id: "middle", text: "Middle"),
            BlockInputBlock(id: sharedID, text: "Second")
        ]))

        store.moveBlock(withID: sharedID, to: 2)

        XCTAssertEqual(store.document.blocks.map(\.text), ["Middle", "Second", "First"])
        XCTAssertEqual(store.index(of: sharedID), 1)
        XCTAssertEqual(store.block(withID: sharedID)?.text, "Second")
    }

    func testDefaultGranularMutationsFallBackToDocumentReplacement() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let fallbackStore = FallbackDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First")
        ]))

        fallbackStore.replaceBlock(BlockInputBlock(id: firstID, text: "Updated"))
        fallbackStore.insertBlocks([BlockInputBlock(id: secondID, text: "Second")], at: 1)
        fallbackStore.insertBlocks([BlockInputBlock(id: thirdID, text: "Third")], at: 2)
        fallbackStore.moveBlock(withID: thirdID, to: 0)
        fallbackStore.deleteBlocks(withIDs: [secondID])

        XCTAssertEqual(fallbackStore.document.blocks.map(\.id), [thirdID, firstID])
        XCTAssertEqual(fallbackStore.document.blocks.map(\.text), ["Third", "Updated"])
        XCTAssertEqual(fallbackStore.replaceDocumentCount, 5)
    }

    func testDefaultStoreInsertionAtStartKeepsLeadingFrontMatterPinned() {
        let frontID = BlockInputBlockID(rawValue: "front")
        let insertedID = BlockInputBlockID(rawValue: "inserted")
        let fallbackStore = FallbackDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: frontID, kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "body", text: "Body")
        ]))

        fallbackStore.insertBlocks([BlockInputBlock(id: insertedID, text: "Inserted")], at: 0)

        XCTAssertEqual(fallbackStore.document.blocks.map(\.id), [frontID, insertedID, "body"])
        XCTAssertEqual(fallbackStore.replaceDocumentCount, 1)
    }

    func testDefaultGranularNoOpsDoNotReplaceDocument() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let fallbackStore = FallbackDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First")
        ]))

        fallbackStore.replaceBlock(BlockInputBlock(id: "missing", text: "Missing"))
        fallbackStore.replaceBlock(BlockInputBlock(id: firstID, text: "First"))
        fallbackStore.insertBlocks([], at: 0)
        fallbackStore.deleteBlocks(withIDs: ["missing"])
        fallbackStore.moveBlock(withID: "missing", to: 0)

        XCTAssertEqual(fallbackStore.document.blocks.map(\.id), [firstID])
        XCTAssertEqual(fallbackStore.replaceDocumentCount, 0)
    }

}

private final class FallbackDocumentStore: BlockInputDocumentStore {
    private(set) var document: BlockInputDocument
    private(set) var replaceDocumentCount = 0

    init(document: BlockInputDocument) {
        self.document = document
    }

    var loadedBlockCount: Int {
        document.blocks.count
    }

    func replaceDocument(_ document: BlockInputDocument) {
        replaceDocumentCount += 1
        self.document = document
    }

    func block(at index: Int) -> BlockInputBlock? {
        guard document.blocks.indices.contains(index) else {
            return nil
        }
        return document.blocks[index]
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        document.block(withID: id)
    }

    func index(of id: BlockInputBlockID) -> Int? {
        document.index(of: id)
    }
}
