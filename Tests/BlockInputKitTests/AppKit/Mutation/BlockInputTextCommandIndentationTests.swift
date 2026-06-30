import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTextCommandIndentationTests: XCTestCase {
    func testDeletingListLineBreakPreservesFollowingLineIndentationThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(
                    id: blockID,
                    kind: .bulletedListItem,
                    text: "One\nTwo\nThree",
                    lineIndentationLevels: [0, 1, 2]
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
        _ = item.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 3, length: 1),
            replacementString: ""
        )
        textView.string = "OneTwo\nThree"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks[0].text, "OneTwo\nThree")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 2])

        _ = view.undoTextEditInActiveBlock()

        XCTAssertEqual(view.document.blocks[0].text, "One\nTwo\nThree")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 1, 2])

        _ = view.redoTextEditInActiveBlock()

        XCTAssertEqual(view.document.blocks[0].text, "OneTwo\nThree")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 2])
    }

    func testDeletingSelectedListLinePreservesFollowingLineIndentationThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(
                    id: blockID,
                    kind: .bulletedListItem,
                    text: "One\nTwo\nThree",
                    lineIndentationLevels: [0, 1, 2]
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
        _ = item.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 4, length: 4),
            replacementString: ""
        )
        textView.string = "One\nThree"
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks[0].text, "One\nThree")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 2])

        _ = view.undoTextEditInActiveBlock()

        XCTAssertEqual(view.document.blocks[0].text, "One\nTwo\nThree")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 1, 2])

        _ = view.redoTextEditInActiveBlock()

        XCTAssertEqual(view.document.blocks[0].text, "One\nThree")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 2])
    }

    func testDeletingAllListTextKeepsEmptyLineAtSelectionStartIndentationThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(
                    id: blockID,
                    kind: .bulletedListItem,
                    text: "One\nTwo",
                    lineIndentationLevels: [1, 3]
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
        _ = item.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: 7),
            replacementString: ""
        )
        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [1])

        _ = view.undoTextEditInActiveBlock()

        XCTAssertEqual(view.document.blocks[0].text, "One\nTwo")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [1, 3])

        _ = view.redoTextEditInActiveBlock()

        XCTAssertEqual(view.document.blocks[0].text, "")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [1])
    }

    func testPastingListLineContinuesCurrentLineIndentationThroughDelegatePath() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(
                    id: blockID,
                    kind: .bulletedListItem,
                    text: "One\nTwo",
                    lineIndentationLevels: [0, 1]
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
        _ = item.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 7, length: 0),
            replacementString: "\nThree"
        )
        textView.string = "One\nTwo\nThree"
        textView.setSelectedRange(NSRange(location: 13, length: 0))

        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(view.document.blocks[0].text, "One\nTwo\nThree")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 1, 1])

        _ = view.undoTextEditInActiveBlock()

        XCTAssertEqual(view.document.blocks[0].text, "One\nTwo")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 1])

        _ = view.redoTextEditInActiveBlock()

        XCTAssertEqual(view.document.blocks[0].text, "One\nTwo\nThree")
        XCTAssertEqual(view.document.blocks[0].lineIndentationLevels, [0, 1, 1])
    }
}
