import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewSelectionContractionTests: XCTestCase {
    func testShiftDownShrinksSelectionCreatedUpward() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))
        // A restored full-text selection re-expands through the mixed endpoint path instead of whole-selecting
        // the newly crossed block.
        XCTAssertEqual(mounted.view.selection, mixedSelection(leading: textRange(secondID, 0, 6), trailing: textRange(thirdID, 0, 5)))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: thirdID,
            range: NSRange(location: 0, length: 5)
        )))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftNumericPadUpEvent()))
        XCTAssertEqual(mounted.view.selection, mixedSelection(leading: textRange(secondID, 0, 6), trailing: textRange(thirdID, 0, 5)))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertEqual(mounted.view.selection, mixedSelection(
            blockIDs: [secondID],
            leading: textRange(firstID, 0, 5),
            trailing: textRange(thirdID, 0, 5)
        ))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, mixedSelection(leading: textRange(secondID, 0, 6), trailing: textRange(thirdID, 0, 5)))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: thirdID,
            range: NSRange(location: 0, length: 5)
        )))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertEqual(mounted.view.selection, mixedSelection(leading: textRange(secondID, 0, 6), trailing: textRange(thirdID, 0, 5)))
    }

    func testShiftUpShrinksSelectionCreatedDownward() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))
        // A restored full-text selection re-expands through the mixed endpoint path instead of whole-selecting
        // the newly crossed block.
        XCTAssertEqual(mounted.view.selection, mixedSelection(leading: textRange(firstID, 0, 5), trailing: textRange(secondID, 0, 3)))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, mixedSelection(
            blockIDs: [secondID],
            leading: textRange(firstID, 0, 5),
            trailing: textRange(thirdID, 0, 4)
        ))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertEqual(mounted.view.selection, mixedSelection(leading: textRange(firstID, 0, 5), trailing: textRange(secondID, 0, 3)))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 5)
        )))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, mixedSelection(leading: textRange(firstID, 0, 5), trailing: textRange(secondID, 0, 3)))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: firstID,
            range: NSRange(location: 0, length: 5)
        )))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftNumericPadDownEvent()))
        // A restored full-text selection re-expands through the mixed endpoint path instead of whole-selecting
        // the newly crossed block.
        XCTAssertEqual(mounted.view.selection, mixedSelection(leading: textRange(firstID, 0, 5), trailing: textRange(secondID, 0, 3)))
    }

    func testShiftUpShrinksMixedSelectionCreatedDownwardToPreviousPartialEndpoint() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))
        let firstExpansion = mounted.view.selection
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 1))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(mounted.view.selection, firstExpansion)
    }

    func testShiftDownShrinksMixedSelectionCreatedUpwardToPreviousPartialEndpoint() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 2))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))
        let firstExpansion = mounted.view.selection
        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftUpEvent()))
        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 4, length: 1)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 3))
        )))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, firstExpansion)
    }

    private func mixedSelection(
        blockIDs: [BlockInputBlockID] = [],
        leading: BlockInputTextRange? = nil,
        trailing: BlockInputTextRange? = nil
    ) -> BlockInputSelection {
        .mixed(BlockInputMixedSelection(
            blockIDs: blockIDs,
            leadingTextRange: leading,
            trailingTextRange: trailing
        ))
    }

    private func textRange(_ blockID: BlockInputBlockID, _ location: Int, _ length: Int) -> BlockInputTextRange {
        BlockInputTextRange(blockID: blockID, range: NSRange(location: location, length: length))
    }
}
