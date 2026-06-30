import Foundation
import XCTest
@testable import BlockInputKit

final class ProgressiveStoreMarkerTests: XCTestCase {
    @MainActor
    func testProgressiveMemoryStoreLoadBatchEmitsEffectiveMarkerBlocks() async throws {
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [
            BlockInputBlock(id: "first", kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: "second", kind: .numberedListItem(start: 2), text: "Second"),
            BlockInputBlock(id: "third", kind: .numberedListItem(start: 3), text: "Third")
        ], initialLimit: 1)
        var appendedBatches: [BlockInputDocumentStoreBatch] = []
        let observation = store.observeChanges { change in
            if case .appendedBlocks(let batch) = change {
                appendedBatches.append(batch)
            }
        }
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

        try await store.loadNextBlockBatch(limit: 2)

        XCTAssertEqual(appendedBatches.first?.blocks.map(\.kind), [
            .numberedListItem(start: 3),
            .numberedListItem(start: 4)
        ])
        XCTAssertEqual(store.block(at: 1)?.kind, .numberedListItem(start: 3))
        observation.cancel()
    }

    @MainActor
    func testProgressiveMemoryStoreCompleteSnapshotAppliesMarkerTransactionToUnloadedSourceBlocks() async throws {
        let blocks = [
            BlockInputBlock(id: "first", kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: "second", kind: .numberedListItem(start: 2), text: "Second"),
            BlockInputBlock(id: "third", kind: .numberedListItem(start: 3), text: "Third"),
            BlockInputBlock(id: "paragraph", text: "Paragraph"),
            BlockInputBlock(id: "separate", kind: .numberedListItem(start: 1), text: "Separate")
        ]
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: blocks, initialLimit: 2)
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

        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertNil(store.block(at: 2))
        XCTAssertEqual(snapshot.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 3),
            .numberedListItem(start: 4),
            .paragraph,
            .numberedListItem(start: 1)
        ])
    }

    @MainActor
    func testProgressiveMemoryStoreStopsNestedMarkerAdjustmentAtLowerIndentationBoundary() async throws {
        let otherParentChildID = BlockInputBlockID(rawValue: "other-parent-child")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [
            BlockInputBlock(id: "parent-one", kind: .numberedListItem(start: 1), text: "Parent one"),
            BlockInputBlock(id: "child-one", kind: .numberedListItem(start: 1), text: "Child one", indentationLevel: 1),
            BlockInputBlock(id: "child-two", kind: .numberedListItem(start: 2), text: "Child two", indentationLevel: 1),
            BlockInputBlock(id: "parent-two", kind: .numberedListItem(start: 2), text: "Parent two"),
            BlockInputBlock(id: otherParentChildID, kind: .numberedListItem(start: 1), text: "Other child", indentationLevel: 1)
        ], initialLimit: 3)
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

        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertEqual(store.block(at: 2)?.kind, .numberedListItem(start: 3))
        XCTAssertEqual(snapshot.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 1),
            .numberedListItem(start: 3),
            .numberedListItem(start: 2),
            .numberedListItem(start: 1)
        ])
        XCTAssertEqual(snapshot.block(withID: otherParentChildID)?.kind, .numberedListItem(start: 1))
    }

    @MainActor
    func testProgressiveMemoryStoreReplacesAdjustedNumberedBlockWithoutDoubleApplyingMarkerTransaction() async throws {
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [
            BlockInputBlock(id: "first", kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Second")
        ], initialLimit: 2)
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
        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertEqual(store.block(withID: secondID)?.text, "Edited")
        XCTAssertEqual(store.block(withID: secondID)?.kind, .numberedListItem(start: 3))
        XCTAssertEqual(snapshot.block(withID: secondID)?.kind, .numberedListItem(start: 3))
    }

    @MainActor
    func testProgressiveMemoryStoreShiftsMarkerTransactionsAfterDeletingUnloadedSourceBlock() async throws {
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [
            BlockInputBlock(id: "first", kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: "second", kind: .numberedListItem(start: 2), text: "Second"),
            BlockInputBlock(id: "third", kind: .numberedListItem(start: 3), text: "Third"),
            BlockInputBlock(id: "fourth", kind: .numberedListItem(start: 4), text: "Fourth"),
            BlockInputBlock(id: "fifth", kind: .numberedListItem(start: 5), text: "Fifth")
        ], initialLimit: 2)
        store.applyNumberedListMarkerTransaction(BlockInputNumberedListMarkerTransaction(
            adjustments: [
                BlockInputNumberedListMarkerAdjustment(
                    startIndex: 3,
                    endIndex: 4,
                    listRunStartIndex: 0,
                    indentationLevel: 0,
                    delta: 1
                )
            ]
        ))

        store.deleteBlocks(withIDs: ["third"])
        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertEqual(snapshot.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 2),
            .numberedListItem(start: 5),
            .numberedListItem(start: 6)
        ])
    }

    @MainActor
    func testProgressiveMemoryStoreDropsFiniteMarkerAdjustmentWhenCoveredBlockIsDeleted() async throws {
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [
            BlockInputBlock(id: "first", kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Second"),
            BlockInputBlock(id: thirdID, kind: .numberedListItem(start: 3), text: "Third")
        ], initialLimit: 2)
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
        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertEqual(snapshot.block(withID: thirdID)?.kind, .numberedListItem(start: 3))
        XCTAssertEqual(snapshot.blocks.map(\.kind), [
            .numberedListItem(start: 1),
            .numberedListItem(start: 3)
        ])
    }

    @MainActor
    func testProgressiveMemoryStoreShiftsMarkerTransactionsForEveryDeletedDuplicateIDBlock() async throws {
        let sharedID = BlockInputBlockID(rawValue: "shared")
        let fourthID = BlockInputBlockID(rawValue: "fourth")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [
            BlockInputBlock(id: "first", kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: sharedID, kind: .numberedListItem(start: 2), text: "Duplicate one"),
            BlockInputBlock(id: sharedID, kind: .numberedListItem(start: 3), text: "Duplicate two"),
            BlockInputBlock(id: fourthID, kind: .numberedListItem(start: 4), text: "Fourth")
        ], initialLimit: 2)
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
        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertEqual(snapshot.blocks.map(\.id), ["first", fourthID])
        XCTAssertEqual(snapshot.block(withID: fourthID)?.kind, .numberedListItem(start: 14))
    }

    @MainActor
    func testProgressiveMemoryStoreCompactsPendingMarkerTransactionsBeforeMove() async throws {
        let paragraphID = BlockInputBlockID(rawValue: "paragraph")
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [
            BlockInputBlock(id: paragraphID, text: "Paragraph"),
            BlockInputBlock(id: firstID, kind: .numberedListItem(start: 1), text: "First"),
            BlockInputBlock(id: secondID, kind: .numberedListItem(start: 2), text: "Second")
        ], initialLimit: 3)
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
        let snapshot = try await store.completeDocumentSnapshot(limit: 2)

        XCTAssertEqual(snapshot.blocks.map(\.id), [firstID, secondID, paragraphID])
        XCTAssertEqual(store.block(withID: firstID)?.kind, .numberedListItem(start: 2))
        XCTAssertEqual(store.block(withID: secondID)?.kind, .numberedListItem(start: 3))
    }
}
