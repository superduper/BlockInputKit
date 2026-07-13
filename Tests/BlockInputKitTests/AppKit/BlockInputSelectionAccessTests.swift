import AppKit
import XCTest
@testable import BlockInputKit

/// Tests the additive cursor-anchored facade a host uses for AI edits: read the selected text,
/// reveal/focus a block-id + range after an edit, and show a passive applied-diff highlight
/// (additions green / deletions red) with NO accept/reject affordance.
@MainActor
final class BlockInputSelectionAccessTests: XCTestCase {

    private let blockA = BlockInputBlockID(rawValue: "a")
    private let blockB = BlockInputBlockID(rawValue: "b")

    private func mount(_ blocks: [BlockInputBlock]) -> (view: BlockInputView, window: NSWindow) {
        makeMountedBlockInputView(blocks: blocks)
    }

    // MARK: selectedText

    func test_selectedText_nilForCaret() {
        let (view, _) = mount([BlockInputBlock(id: blockA, text: "The quick brown fox.")])
        view.applySelection(.cursor(BlockInputCursor(blockID: blockA, utf16Offset: 4)), notify: false)
        XCTAssertNil(view.selectedText())
    }

    func test_selectedText_nilWhenNoSelection() {
        let (view, _) = mount([BlockInputBlock(id: blockA, text: "hello")])
        view.applySelection(nil, notify: false)
        XCTAssertNil(view.selectedText())
    }

    func test_selectedText_slicesTextRange() {
        let (view, _) = mount([BlockInputBlock(id: blockA, text: "The quick brown fox.")])
        view.applySelection(.text(BlockInputTextRange(blockID: blockA, range: NSRange(location: 4, length: 5))), notify: false)
        XCTAssertEqual(view.selectedText(), "quick")
    }

    func test_selectedText_joinsWholeBlockSelectionInDocumentOrder() {
        let (view, _) = mount([
            BlockInputBlock(id: blockA, text: "first"),
            BlockInputBlock(id: blockB, text: "second")
        ])
        // Deliberately pass out-of-document order to prove it re-orders by index.
        view.applySelection(.blocks([blockB, blockA]), notify: false)
        XCTAssertEqual(view.selectedText(), "first\nsecond")
    }

    func test_selectedText_mixedUsesPartialEdgesAndWholeMiddle() {
        let (view, _) = mount([
            BlockInputBlock(id: blockA, text: "The quick brown fox."),
            BlockInputBlock(id: BlockInputBlockID(rawValue: "mid"), text: "middle"),
            BlockInputBlock(id: blockB, text: "lazy dog rests.")
        ])
        let mixed = BlockInputMixedSelection(
            blockIDs: [BlockInputBlockID(rawValue: "mid")],
            leadingTextRange: BlockInputTextRange(blockID: blockA, range: NSRange(location: 4, length: 16)),
            trailingTextRange: BlockInputTextRange(blockID: blockB, range: NSRange(location: 0, length: 4))
        )
        view.applySelection(.mixed(mixed), notify: false)
        XCTAssertEqual(view.selectedText(), "quick brown fox.\nmiddle\nlazy")
    }

    // MARK: reveal (moves selection + scrolls)

    func test_reveal_movesSelectionToRange() {
        let (view, _) = mount([BlockInputBlock(id: blockA, text: "The quick brown fox.")])
        let moved = view.reveal(BlockInputTextRange(blockID: blockA, range: NSRange(location: 10, length: 5)))
        XCTAssertTrue(moved)
        XCTAssertEqual(view.selection, .text(BlockInputTextRange(blockID: blockA, range: NSRange(location: 10, length: 5))))
        XCTAssertEqual(view.mountedBlockItem(for: blockA)?.textView.selectedRange(), NSRange(location: 10, length: 5))
    }

    func test_reveal_caretForZeroLengthRange() {
        let (view, _) = mount([BlockInputBlock(id: blockA, text: "hello world")])
        let moved = view.reveal(blockID: blockA, utf16Offset: 6)
        XCTAssertTrue(moved)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockA, utf16Offset: 6)))
    }

    func test_reveal_clampsOutOfBoundsRange() {
        let (view, _) = mount([BlockInputBlock(id: blockA, text: "short")])
        let moved = view.reveal(BlockInputTextRange(blockID: blockA, range: NSRange(location: 100, length: 50)))
        XCTAssertTrue(moved)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockA, utf16Offset: 5)))
    }

    func test_reveal_falseForMissingBlock() {
        let (view, _) = mount([BlockInputBlock(id: blockA, text: "x")])
        XCTAssertFalse(view.reveal(blockID: BlockInputBlockID(rawValue: "nope"), utf16Offset: 0))
    }

    // MARK: presentAppliedDiff (passive, no accept/reject)

    func test_presentAppliedDiff_paintsAdditionsAndDeletions_withoutMutatingText() {
        let (view, _) = mount([BlockInputBlock(id: blockA, text: "The swift brown fox.")])
        view.presentAppliedDiff(
            additions: [NSRange(location: 4, length: 5)],
            deletions: [NSRange(location: 10, length: 5)],
            in: blockA
        )

        // Text is untouched — the edit was already applied by the host; this is annotation only.
        XCTAssertEqual(view.document.blocks[0].text, "The swift brown fox.")

        let highlights = view.transientHighlights(in: blockA)
        XCTAssertEqual(highlights.count, 2)

        let addition = highlights.first { !$0.strikethrough }
        let deletion = highlights.first { $0.strikethrough }
        XCTAssertEqual(addition?.range, NSRange(location: 4, length: 5))
        XCTAssertEqual(addition?.backgroundColor, BlockInputAppliedDiffStyle.default.additionBackgroundColor)
        XCTAssertEqual(deletion?.range, NSRange(location: 10, length: 5))
        XCTAssertEqual(deletion?.strikethroughColor, BlockInputAppliedDiffStyle.default.deletionStrikethroughColor)
    }

    func test_presentAppliedDiff_hasNoInteractiveState() {
        // The passive highlight is pure transient styling — there is no accept/reject/proposal state.
        // Assert the only observable effect is the transient-highlight dictionary (the shared, passive
        // mechanism), and clearing removes it entirely.
        let (view, _) = mount([BlockInputBlock(id: blockA, text: "hello world")])
        view.presentAppliedDiff(additions: [NSRange(location: 0, length: 5)], in: blockA)
        XCTAssertEqual(view.transientHighlightsByBlock[blockA]?.count, 1)

        view.clearAppliedDiffHighlight(in: blockA)
        XCTAssertNil(view.transientHighlightsByBlock[blockA])
    }
}
