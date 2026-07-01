import AppKit
import XCTest
@testable import BlockInputKit

/// Tests the programmatic-editing + transient-highlight APIs that a ⌘K / AI inline-edit plugin drives:
/// select a range, apply range/block edits, paint non-mutating diff highlights, read the anchor rect,
/// and revert. This is the headless analogue of "simulate selection → ⌘K → send".
@MainActor
final class BlockInputProgrammaticEditingTests: XCTestCase {

    private let blockID = BlockInputBlockID(rawValue: "b1")

    private func mount(_ text: String) -> (view: BlockInputView, window: NSWindow) {
        makeMountedBlockInputView(blocks: [BlockInputBlock(id: blockID, text: text)])
    }

    // MARK: replaceText / replaceBlockText

    func test_replaceText_replacesRange_andReRenders() {
        let (view, _) = mount("The quick brown fox.")
        view.applySelection(.text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 4, length: 5))), notify: false)

        let selection = view.replaceText(in: blockID, range: NSRange(location: 4, length: 5), with: "swift")

        XCTAssertEqual(view.document.blocks[0].text, "The swift brown fox.")
        XCTAssertEqual(selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)))
    }

    func test_replaceText_typedCharByChar_buildsUpText() {
        // Simulate the player's insertion animation: repeated zero-length range inserts at a moving cursor.
        let (view, _) = mount("Hi")
        var cursor = 2
        for piece in [" ", "t", "h", "e", "r", "e"] {
            view.replaceText(in: blockID, range: NSRange(location: cursor, length: 0), with: piece)
            cursor += (piece as NSString).length
        }
        XCTAssertEqual(view.document.blocks[0].text, "Hi there")
    }

    func test_replaceBlockText_replacesWholeBlock() {
        let (view, _) = mount("original text")
        view.replaceBlockText(blockID: blockID, with: "brand new text")
        XCTAssertEqual(view.document.blocks[0].text, "brand new text")
    }

    func test_replaceText_missingBlock_isNoOp() {
        let (view, _) = mount("x")
        let result = view.replaceText(in: BlockInputBlockID(rawValue: "nope"), range: NSRange(location: 0, length: 1), with: "y")
        XCTAssertNil(result)
        XCTAssertEqual(view.document.blocks[0].text, "x")
    }

    // MARK: insertBlock / deleteBlock

    func test_insertBlock_after_andDelete_roundTrips() {
        let (view, _) = mount("first")
        let newBlock = BlockInputBlock(kind: .bulletedListItem, text: "second")
        view.insertBlock(newBlock, after: blockID)

        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(view.document.blocks[1].text, "second")

        view.deleteBlock(blockID: newBlock.id)
        XCTAssertEqual(view.document.blocks.count, 1)
        XCTAssertEqual(view.document.blocks[0].text, "first")
    }

    // MARK: transient highlights (the diff display)

    func test_transientHighlights_doNotMutateText_andClear() {
        let (view, _) = mount("The quick brown fox.")
        view.setTransientHighlights([
            BlockInputTransientHighlight(range: NSRange(location: 4, length: 5),
                                         backgroundColor: .systemRed, strikethrough: true, strikethroughColor: .systemRed),
            BlockInputTransientHighlight(range: NSRange(location: 10, length: 5), backgroundColor: .systemGreen)
        ], in: blockID)

        // The document text is untouched by highlighting.
        XCTAssertEqual(view.document.blocks[0].text, "The quick brown fox.")
        XCTAssertEqual(view.transientHighlightsByBlock[blockID]?.count, 2)

        view.clearTransientHighlights(in: blockID)
        XCTAssertNil(view.transientHighlightsByBlock[blockID])
    }

    func test_transientHighlights_surviveASubsequentEdit() {
        // Regression: a structural edit reloads text views and wipes NSLayoutManager temp attributes;
        // stored highlights must be re-applied on reconfigure. We assert the stored state persists and
        // the block item repaints (via the stored dictionary) rather than the raw temp-attr, which is
        // the observable, testable contract.
        let (view, _) = mount("The quick brown fox.")
        view.setTransientHighlights([
            BlockInputTransientHighlight(range: NSRange(location: 4, length: 5), backgroundColor: .systemGreen)
        ], in: blockID)

        // Cause a re-render / reload of the block.
        view.replaceBlockText(blockID: blockID, with: "The quick brown fox.")   // same text, forces reconfigure

        XCTAssertEqual(view.transientHighlightsByBlock[blockID]?.count, 1,
                       "stored highlights must survive an edit so they can be re-applied on reconfigure")
    }

    // MARK: rectForRange (anchoring)

    func test_rectForRange_returnsRectForVisibleBlock() {
        let (view, _) = mount("The quick brown fox jumps over the lazy dog.")
        let rect = view.rectForRange(NSRange(location: 0, length: 9), in: blockID)
        XCTAssertNotNil(rect)
        XCTAssertGreaterThan(rect?.width ?? 0, 0)
        XCTAssertGreaterThan(rect?.height ?? 0, 0)
    }

    func test_rectForRange_nilForUnknownBlock() {
        let (view, _) = mount("x")
        XCTAssertNil(view.rectForRange(NSRange(location: 0, length: 1), in: BlockInputBlockID(rawValue: "nope")))
    }

    // MARK: end-to-end: the ⌘K sequence at the API level

    func test_selectRewriteHighlightCommitRevert_sequence() {
        // "Select → rewrite → highlight the diff → then either commit or revert."
        let original = "The quick brown fox."
        let target = "The swift auburn fox."
        let (view, _) = mount(original)
        let fullRange = NSRange(location: 0, length: (original as NSString).length)
        view.applySelection(.text(BlockInputTextRange(blockID: blockID, range: fullRange)), notify: false)

        // Rewrite the block to the target (the player animates this; here we jump to the end state).
        view.replaceBlockText(blockID: blockID, with: target)
        view.setTransientHighlights([
            BlockInputTransientHighlight(range: NSRange(location: 4, length: 5), backgroundColor: .systemGreen)
        ], in: blockID)
        XCTAssertEqual(view.document.blocks[0].text, target)

        // Reject → restore original + clear highlights.
        view.clearTransientHighlights(in: blockID)
        view.replaceBlockText(blockID: blockID, with: original)
        XCTAssertEqual(view.document.blocks[0].text, original)
        XCTAssertNil(view.transientHighlightsByBlock[blockID])
    }
}
