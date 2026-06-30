import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputFrontMatterSelectionTests: XCTestCase {
    func testCommandASelectsEmptyFrontMatterAsWholeBlock() throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter)
        let paragraph = BlockInputBlock(id: "paragraph", text: "Body")
        let mounted = makeMountedBlockInputView(blocks: [front, paragraph])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))

        XCTAssertEqual(mounted.view.selection, .blocks([front.id]))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testCommandAEscalatesFullFrontMatterBodyToWholeBlockThenAllBlocks() throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let paragraph = BlockInputBlock(id: "paragraph", text: "Body")
        let mounted = makeMountedBlockInputView(blocks: [front, paragraph])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: front.id,
            range: NSRange(location: 0, length: front.utf16Length)
        )))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks([front.id]))

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandAEvent()))
        XCTAssertEqual(mounted.view.selection, .blocks([front.id, paragraph.id]))
    }

    func testShiftDownFromFullFrontMatterBodyPromotesToMixedSelection() throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo")
        let paragraph = BlockInputBlock(id: "paragraph", text: "Body")
        let mounted = makeMountedBlockInputView(blocks: [front, paragraph])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: front.utf16Length))
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: front.id,
            range: NSRange(location: 0, length: front.utf16Length)
        )), notify: false)

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(
                blockID: front.id,
                range: NSRange(location: 0, length: front.utf16Length)
            ),
            trailingTextRange: BlockInputTextRange(blockID: paragraph.id, range: NSRange(location: 0, length: 4))
        )))
        XCTAssertEqual(mounted.window.firstResponder, mounted.view)
    }

    func testShiftDownFromPartialFrontMatterBodyKeepsTextSelection() throws {
        let front = BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo\nslug: demo")
        let paragraph = BlockInputBlock(id: "paragraph", text: "Body")
        let mounted = makeMountedBlockInputView(blocks: [front, paragraph])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        XCTAssertTrue(textView.performKeyEquivalent(with: try shiftDownEvent()))

        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(
            blockID: front.id,
            range: NSRange(location: 0, length: 12)
        )))
    }
}
