import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputFullSelectionExpansionTests: XCTestCase {
    func testShiftDownPromotesWholeBlockSelectionToMixedSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 5)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 3))
        )))
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), true)
        XCTAssertEqual(textView.selectedRange().length, 0)
    }

    func testMoveDownModifySelectionSelectorPromotesWholeBlockSelectionToMixedSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        textView.doCommand(by: #selector(NSResponder.moveDownAndModifySelection(_:)))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 5)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 3))
        )))
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), true)
    }

    func testShiftUpPromotesWholeBlockSelectionToMixedSelectionInDocumentOrder() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 6))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftUpEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 0, length: 5)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 6))
        )))
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), true)
    }

    func testShiftDownFromFullNestedListBlockPromotesBeforeStartingPartialNextBlock() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let firstText = "Bulleted list item\nNested bullet item\nDeep nested bullet item"
        let secondText = "Numbered list item\nNested numbered item\nDeep nested numbered item"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(
                id: firstID,
                kind: .bulletedListItem,
                text: firstText,
                lineIndentationLevels: [0, 1, 2]
            ),
            BlockInputBlock(
                id: secondID,
                kind: .numberedListItem(start: 1),
                text: secondText,
                lineIndentationLevels: [0, 1, 2]
            )
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: (firstText as NSString).length))

        // A fully covered nested list first becomes a whole block; the next expansion starts the neighbor line-by-line.
        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks([firstID]))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try shiftDownEvent()))

        guard case let .mixed(selection) = mounted.view.selection else {
            return XCTFail("Expected mixed selection")
        }
        XCTAssertEqual(selection.blockIDs, [firstID])
        XCTAssertNil(selection.leadingTextRange)
        let trailingTextRange = try XCTUnwrap(selection.trailingTextRange)
        XCTAssertEqual(trailingTextRange.blockID, secondID)
        XCTAssertEqual(trailingTextRange.range.location, 0)
        XCTAssertGreaterThan(trailingTextRange.range.length, 0)
        XCTAssertLessThan(trailingTextRange.range.length, (secondText as NSString).length)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 0), true)
        XCTAssertEqual(itemSelectionBackgroundVisible(in: mounted.view, at: 1), true)
    }

    private func itemSelectionBackgroundVisible(in view: BlockInputView, at index: Int) -> Bool {
        view.visibleBlockItemForTesting(at: index)?.testingSelectionBackgroundView.isHidden == false
    }
}
