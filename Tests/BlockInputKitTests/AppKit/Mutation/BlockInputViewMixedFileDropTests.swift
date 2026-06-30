import AppKit
import XCTest
@testable import BlockInputKit

/// Tests for the mixed inline+image file drop path — verifies that both insertions
/// happen atomically under a single undo entry so a partial failure cannot leave
/// orphaned image blocks in the document.
@MainActor
final class BlockInputViewMixedFileDropTests: XCTestCase {
    func testMixedImageAndFileDropIsUndoneAsASingleStep() throws {
        // A mixed drop of an image + a file link into a paragraph (in .inlineBlocks mode)
        // should insert the image block below AND the file chip inline atomically.
        // Before the fix, two separate undo entries were registered, so one undo step
        // left an orphaned image block. After the fix, a single undo restores the
        // document to its pre-drop state.
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Open docs")
            ]),
            imagePresentation: .inlineBlocks,
            undoController: BlockInputUndoController()
        ))
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 5, in: textView)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [
                URL(fileURLWithPath: "/tmp/Photo.png"),
                URL(fileURLWithPath: "/tmp/README.md")
            ],
            location: location
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        // After drop: paragraph got an inline file chip, and an image block was inserted below
        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertTrue(mounted.view.document.blocks[0].text.contains("[README.md]"))
        XCTAssertEqual(
            mounted.view.document.blocks[1].kind,
            .image(BlockInputImage(source: "file:///tmp/Photo.png", altText: "Photo"))
        )

        // A single undo must revert both mutations atomically — no orphaned image block
        let undo = mounted.view.undoStructuralEdit()
        XCTAssertNotNil(undo, "Undo should be available after the mixed drop")
        XCTAssertEqual(mounted.view.document.blocks.count, 1, "Undo must remove the orphaned image block")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open docs", "Undo must revert the inline insertion too")

        // A second undo should have nothing to do
        XCTAssertNil(mounted.view.undoStructuralEdit(), "There must be no further undo entries after the mixed drop is reverted")
    }

    func testMixedImageAndFileDropViaHandlerIsUndoneAsASingleStep() async throws {
        // Same atomicity guarantee when the drop goes through the async fileDropHandler path.
        let blockID = BlockInputBlockID(rawValue: "block")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Open docs")
            ]),
            imagePresentation: .inlineBlocks,
            undoController: BlockInputUndoController(),
            fileDropHandler: { _ in .useDefault }
        ))
        let textView = try textView(in: mounted.view)
        let location = try windowLocation(forUTF16Offset: 5, in: textView)
        let draggingInfo = BlockInputDraggingInfo(
            fileURLs: [
                URL(fileURLWithPath: "/tmp/Photo.png"),
                URL(fileURLWithPath: "/tmp/README.md")
            ],
            location: location
        )

        XCTAssertTrue(textView.performDragOperation(draggingInfo))
        await drainFileDropTasks(in: mounted.view)

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
        XCTAssertTrue(mounted.view.document.blocks[0].text.contains("[README.md]"))
        XCTAssertEqual(
            mounted.view.document.blocks[1].kind,
            .image(BlockInputImage(source: "file:///tmp/Photo.png", altText: "Photo"))
        )

        let undo = mounted.view.undoStructuralEdit()
        XCTAssertNotNil(undo, "Undo should be available after the mixed drop via handler")
        XCTAssertEqual(mounted.view.document.blocks.count, 1, "Undo must remove the orphaned image block from handler path")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Open docs", "Undo must revert the inline insertion from handler path too")

        XCTAssertNil(mounted.view.undoStructuralEdit(), "There must be no further undo entries after the handler drop is reverted")
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func drainFileDropTasks(in view: BlockInputView) async {
        while !view.fileDropTasks.isEmpty {
            await Task.yield()
        }
        await Task.yield()
    }
}
