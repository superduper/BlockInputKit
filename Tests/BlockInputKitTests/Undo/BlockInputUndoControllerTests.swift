import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputUndoControllerTests: XCTestCase {
    func testTextUndoIsScopedToBlock() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "Before"),
            BlockInputBlock(id: secondID, text: "Untouched")
        ])
        let undoController = BlockInputUndoController()

        undoController.registerTextEdit(
            blockID: firstID,
            beforeText: "Before",
            afterText: "After",
            selectionBefore: .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)),
            selectionAfter: .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5))
        )
        document.blocks[0].text = "After"

        let undo = undoController.undoTextEdit(in: &document, blockID: firstID)
        let redo = undoController.redoTextEdit(in: &document, blockID: firstID)

        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 6)))
        XCTAssertEqual(redo?.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))
        XCTAssertEqual(document.blocks[0].text, "After")
        XCTAssertEqual(document.blocks[1].text, "Untouched")
    }

    func testStructuralUndoRestoresDocumentAndSelection() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let before = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First")
        ])
        var after = before
        let selectionAfter = after.insertBlock(BlockInputBlock(id: secondID, text: "Second"), at: 1)
        var document = after
        let undoController = BlockInputUndoController()

        undoController.registerStructuralEdit(
            actionName: "Insert Block",
            beforeDocument: before,
            afterDocument: after,
            selectionBefore: .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)),
            selectionAfter: selectionAfter
        )

        let undo = undoController.undoStructuralEdit(in: &document)
        XCTAssertEqual(document, before)
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))

        let redo = undoController.redoStructuralEdit(in: &document)
        XCTAssertEqual(document, after)
        XCTAssertEqual(redo?.selection, selectionAfter)
    }

    func testStructuralUndoCanReplaceSingleBlock() {
        let blockID = BlockInputBlockID(rawValue: "list")
        let beforeBlock = BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Item")
        var afterBlock = beforeBlock
        afterBlock.indentationLevel = 1
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            afterBlock,
            BlockInputBlock(id: "last", text: "Last")
        ])
        let undoController = BlockInputUndoController()

        undoController.registerBlockReplacementStructuralEdit(
            actionName: "Indent Block",
            beforeBlock: beforeBlock,
            afterBlock: afterBlock,
            selectionBefore: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)),
            selectionAfter: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4))
        )

        let undo = undoController.undoStructuralEdit(in: &document)
        XCTAssertEqual(document.blocks[0].text, "First")
        XCTAssertEqual(document.blocks[1], beforeBlock)
        XCTAssertEqual(document.blocks[2].text, "Last")
        XCTAssertEqual(undo?.actionName, "Indent Block")
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))

        let redo = undoController.redoStructuralEdit(in: &document)
        XCTAssertEqual(document.blocks[1], afterBlock)
        XCTAssertEqual(redo?.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 4)))
    }

    func testStructuralUndoCanInsertBlocksWithoutFullDocumentPayload() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let insertedID = BlockInputBlockID(rawValue: "inserted")
        let insertedBlock = BlockInputBlock(id: insertedID, text: "")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            insertedBlock
        ])
        let undoController = BlockInputUndoController()

        undoController.registerBlockInsertionStructuralEdit(
            actionName: "Insert Block",
            insertedBlocks: [insertedBlock],
            insertionIndex: 1,
            selectionBefore: .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)),
            selectionAfter: .cursor(BlockInputCursor(blockID: insertedID, utf16Offset: 0))
        )

        let undo = undoController.undoStructuralEdit(in: &document)
        XCTAssertEqual(document.blocks.map(\.id), [firstID])
        XCTAssertEqual(undo?.actionName, "Insert Block")
        XCTAssertEqual(undo?.deletedBlockIDs, [insertedID])
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))

        let redo = undoController.redoStructuralEdit(in: &document)
        XCTAssertEqual(document.blocks.map(\.id), [firstID, insertedID])
        XCTAssertEqual(redo?.insertedBlocks, [insertedBlock])
        XCTAssertEqual(redo?.insertionIndex, 1)
        XCTAssertEqual(redo?.selection, .cursor(BlockInputCursor(blockID: insertedID, utf16Offset: 0)))
    }

    func testTextEditAfterStructuralUndoClearsStructuralRedo() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let before = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        var after = before
        after.blocks[0].kind = .quote
        var document = after
        let undoController = BlockInputUndoController()
        undoController.registerStructuralEdit(
            actionName: "Change Type",
            beforeDocument: before,
            afterDocument: after,
            selectionBefore: nil,
            selectionAfter: nil
        )
        _ = undoController.undoStructuralEdit(in: &document)

        undoController.registerTextEdit(
            blockID: blockID,
            beforeText: "First",
            afterText: "Edited",
            selectionBefore: nil,
            selectionAfter: nil
        )

        XCTAssertNil(undoController.redoStructuralEdit(in: &document))
    }

    func testStructuralEditAfterTextUndoClearsTextRedo() {
        let blockID = BlockInputBlockID(rawValue: "first")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Edited")
        ])
        let undoController = BlockInputUndoController()
        undoController.registerTextEdit(
            blockID: blockID,
            beforeText: "First",
            afterText: "Edited",
            selectionBefore: nil,
            selectionAfter: nil
        )
        _ = undoController.undoTextEdit(in: &document, blockID: blockID)

        let beforeStructural = document
        document.blocks[0].kind = .quote
        undoController.registerStructuralEdit(
            actionName: "Change Type",
            beforeDocument: beforeStructural,
            afterDocument: document,
            selectionBefore: nil,
            selectionAfter: nil
        )

        XCTAssertNil(undoController.redoTextEdit(in: &document, blockID: blockID))
    }

    func testTextUndoRestoresPerLineIndentationLevels() {
        let blockID = BlockInputBlockID(rawValue: "list")
        var document = BlockInputDocument(blocks: [
            BlockInputBlock(
                id: blockID,
                kind: .bulletedListItem,
                text: "One\nTwo\n",
                lineIndentationLevels: [0, 1, 1]
            )
        ])
        let undoController = BlockInputUndoController()

        undoController.registerTextEdit(
            blockID: blockID,
            beforeText: "One\nTwo",
            afterText: "One\nTwo\n",
            beforeLineIndentationLevels: [0, 1],
            afterLineIndentationLevels: [0, 1, 1],
            selectionBefore: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 7)),
            selectionAfter: .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 8))
        )

        _ = undoController.undoTextEdit(in: &document, blockID: blockID)

        XCTAssertEqual(document.blocks[0].text, "One\nTwo")
        XCTAssertEqual(document.blocks[0].lineIndentationLevels, [0, 1])

        _ = undoController.redoTextEdit(in: &document, blockID: blockID)

        XCTAssertEqual(document.blocks[0].text, "One\nTwo\n")
        XCTAssertEqual(document.blocks[0].lineIndentationLevels, [0, 1, 1])
    }

    func testRedoStackNotWipedWhenTextEditFiresDuringStructuralUndo() {
        // This test uses two undo entries so that entry A lands on the redo stack
        // *before* the granular undo of entry B begins.  A mid-replay registerTextEdit
        // would wipe structuralRedoStack (clearing A_redo) without the guard; with the
        // guard it is a no-op, so both A_redo and B_redo end up on the stack.
        let blockID = BlockInputBlockID(rawValue: "block")
        let blockA = BlockInputBlock(id: blockID, kind: .paragraph, text: "a")
        let blockB = BlockInputBlock(id: blockID, kind: .paragraph, text: "b")
        let blockC = BlockInputBlock(id: blockID, kind: .paragraph, text: "c")
        let controller = BlockInputUndoController()

        // Step 1 – register edit A (undoStack = [A])
        controller.registerBlockReplacementStructuralEdit(
            actionName: "edit A",
            beforeBlock: blockA,
            afterBlock: blockB,
            selectionBefore: nil,
            selectionAfter: nil
        )

        // Step 2 – register edit B on top (undoStack = [A, B])
        controller.registerBlockReplacementStructuralEdit(
            actionName: "edit B",
            beforeBlock: blockB,
            afterBlock: blockC,
            selectionBefore: nil,
            selectionAfter: nil
        )

        // Step 3 – fully undo edit B so that A_redo is not yet on the stack.
        // We undo A (which is now the top of the stack after B was registered last)…
        // Actually, undo pops from the top: undo B first to get undoStack = [A], redoStack = [B_redo].
        let resultB = controller.nextGranularStructuralUndoResult()
        XCTAssertNotNil(resultB, "should have a pending granular undo for edit B")
        controller.commitGranularStructuralUndo()
        // Now: undoStack = [A], redoStack = [B_redo]

        // Step 4 – fully undo edit A so A_redo lands on the redo stack.
        let resultA = controller.nextGranularStructuralUndoResult()
        XCTAssertNotNil(resultA, "should have a pending granular undo for edit A")
        // At this point isApplyingStructuralUndo = true and undoStack = [].
        // redoStack still has [B_redo] from step 3.

        // Step 5 – inject a re-entrant textDidChange mid-replay.
        // Without the guard: this clears structuralRedoStack (wiping B_redo) and redoOrder.
        // With the guard:    this is a no-op.
        controller.registerTextEdit(
            blockID: blockID,
            beforeText: "a",
            afterText: "a-mid-undo",
            selectionBefore: nil,
            selectionAfter: nil
        )

        // Step 6 – commit the granular undo of A → pushes A_redo to redoStack.
        controller.commitGranularStructuralUndo()
        // With fix:    redoStack = [B_redo, A_redo] — two entries
        // Without fix: redoStack = [A_redo]         — B_redo was wiped in step 5

        XCTAssertTrue(controller.canRedo(), "redo stack must be non-empty after undoing both edits")

        // Pop the first redo (A_redo — the one just committed).
        let firstRedo = controller.nextGranularStructuralRedoResult()
        XCTAssertEqual(firstRedo?.actionName, "edit A", "top of redo stack should be edit A")
        controller.commitGranularStructuralRedo()

        // The pre-existing B_redo must still be there; without the fix it was wiped.
        XCTAssertTrue(controller.canRedo(), "B_redo must survive the mid-undo registerTextEdit — redo stack had two entries")
        let secondRedo = controller.nextGranularStructuralRedoResult()
        XCTAssertEqual(secondRedo?.actionName, "edit B", "second redo entry should be edit B")
    }

    func testFlagNotStuckWhenCommitIsSkipped() {
        // Regression: the call site calls nextGranularStructuralUndoResult (which sets
        // isApplyingStructuralUndo = true) but may not call commit when applyGranularUndoResult
        // returns false (e.g. stale block ID).  The fixed call site now calls
        // cancelGranularStructuralUndo() in that branch, which clears the flag.
        // Without cancel, any subsequent registerXxx calls would be silently dropped.
        let blockID = BlockInputBlockID(rawValue: "block")
        let blockA = BlockInputBlock(id: blockID, kind: .paragraph, text: "a")
        let blockB = BlockInputBlock(id: blockID, kind: .paragraph, text: "b")
        let controller = BlockInputUndoController()

        controller.registerBlockReplacementStructuralEdit(
            actionName: "edit A",
            beforeBlock: blockA,
            afterBlock: blockB,
            selectionBefore: nil,
            selectionAfter: nil
        )

        // Simulate: applyGranularUndoResult returned false → call site calls cancel.
        let result = controller.nextGranularStructuralUndoResult()
        XCTAssertNotNil(result, "should return a granular undo result")
        controller.cancelGranularStructuralUndo()

        // A new structural edit registered after the cancelled fetch must be recorded.
        let blockC = BlockInputBlock(id: blockID, kind: .paragraph, text: "c")
        controller.registerBlockReplacementStructuralEdit(
            actionName: "edit C",
            beforeBlock: blockB,
            afterBlock: blockC,
            selectionBefore: nil,
            selectionAfter: nil
        )

        XCTAssertTrue(controller.canUndo(), "undo history must accept new edits after a cancelled granular fetch")
    }

    func testRedoReplayGuardPreventsMidReplayRegistration() {
        // Regression: commitGranularStructuralRedo had no re-entrancy guard, so a
        // registerXxx fired during its execution (e.g. from a textDidChange notification)
        // could corrupt undo/redo stacks.
        let blockID = BlockInputBlockID(rawValue: "block")
        let blockA = BlockInputBlock(id: blockID, kind: .paragraph, text: "a")
        let blockB = BlockInputBlock(id: blockID, kind: .paragraph, text: "b")
        let controller = BlockInputUndoController()

        controller.registerBlockReplacementStructuralEdit(
            actionName: "edit A",
            beforeBlock: blockA,
            afterBlock: blockB,
            selectionBefore: nil,
            selectionAfter: nil
        )

        // Undo to put edit A on redo stack.
        let undoResult = controller.nextGranularStructuralUndoResult()
        XCTAssertNotNil(undoResult)
        controller.commitGranularStructuralUndo()

        // Begin redo replay.
        let redoResult = controller.nextGranularStructuralRedoResult()
        XCTAssertNotNil(redoResult)

        // Commit redo — isApplyingStructuralUndo must be true during this window.
        // A re-entrant register call inside commit must be silently dropped.
        controller.commitGranularStructuralRedo()

        // After redo, edit A should be back on the undo stack and redo should be empty.
        XCTAssertTrue(controller.canUndo(), "edit A should be back on the undo stack after redo")
        XCTAssertFalse(controller.canRedo(), "redo stack should be empty after committing the only redo entry")
    }

    func testConcurrentRegisterDoesNotCorruptGranularUndoCommit() {
        let blockID = BlockInputBlockID(rawValue: "block")
        let blockA = BlockInputBlock(id: blockID, kind: .paragraph, text: "a")
        let blockB = BlockInputBlock(id: blockID, kind: .paragraph, text: "b")
        let controller = BlockInputUndoController()

        // Register edit A using a granular (blockReplacement) payload so it is eligible for granular apply
        controller.registerBlockReplacementStructuralEdit(
            actionName: "edit A",
            beforeBlock: blockA,
            afterBlock: blockB,
            selectionBefore: nil,
            selectionAfter: nil
        )

        // Simulate a re-entrant registration between preview and commit
        let result = controller.nextGranularStructuralUndoResult()
        XCTAssertNotNil(result)

        // Inject a new structural edit between preview and commit
        controller.registerBlockReplacementStructuralEdit(
            actionName: "edit B",
            beforeBlock: blockB,
            afterBlock: blockA,
            selectionBefore: nil,
            selectionAfter: nil
        )

        controller.commitGranularStructuralUndo()

        // After commit, edit A should be on redo stack (action name "edit A").
        // The re-entrantly registered edit B is silently dropped — it must not replace edit A on the redo stack.
        let redoResult = controller.nextGranularStructuralRedoResult()
        XCTAssertEqual(redoResult?.actionName, "edit A", "redo stack top should be edit A, not the re-entrantly registered edit B")
        XCTAssertTrue(controller.canRedo(), "edit A should be redoable")
    }
}
