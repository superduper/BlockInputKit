import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputSetBlockKindCommandTests: XCTestCase {
    private let paragraphID = BlockInputBlockID(rawValue: "paragraph")

    private func mountedParagraph(
        text: String = "convert me",
        undoController: BlockInputUndoController = BlockInputUndoController()
    ) -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: paragraphID, text: text)]),
            undoController: undoController
        )
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: paragraphID,
            range: NSRange(location: 0, length: (text as NSString).length)
        )), notify: false)
        return mounted
    }

    func testSetBlockKindConvertsActiveBlockKeepingText() {
        let cases: [BlockInputBlockKind] = [
            .heading(level: 1),
            .quote,
            .code(language: nil),
            .bulletedListItem,
            .numberedListItem(start: 1)
        ]
        for kind in cases {
            let mounted = mountedParagraph()
            XCTAssertTrue(
                mounted.view.performCommand(.setBlockKind(kind)),
                "expected conversion to \(kind) to succeed"
            )
            XCTAssertEqual(mounted.view.document.blocks[0].kind, kind)
            XCTAssertEqual(mounted.view.document.blocks[0].text, "convert me")
        }
    }

    func testStateReturnsOnForMatchingKindAndOffOtherwise() {
        let mounted = mountedParagraph()
        XCTAssertEqual(mounted.view.state(for: .setBlockKind(.heading(level: 1))), .off)
        XCTAssertEqual(mounted.view.state(for: .setBlockKind(.quote)), .off)

        XCTAssertTrue(mounted.view.performCommand(.setBlockKind(.heading(level: 1))))
        XCTAssertEqual(mounted.view.state(for: .setBlockKind(.heading(level: 1))), .on)
        XCTAssertEqual(mounted.view.state(for: .setBlockKind(.heading(level: 2))), .off)
        XCTAssertEqual(mounted.view.state(for: .setBlockKind(.quote)), .off)
    }

    func testStateRespectsHeadingLevelButIgnoresListStart() {
        let blockID = BlockInputBlockID(rawValue: "numbered")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .numberedListItem(start: 5), text: "item")
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 4)
        )), notify: false)
        // List start is ignored for matching: start 5 still reports .on for start 1.
        XCTAssertEqual(mounted.view.state(for: .setBlockKind(.numberedListItem(start: 1))), .on)
        XCTAssertEqual(mounted.view.state(for: .setBlockKind(.heading(level: 1))), .off)
    }

    func testSetBlockKindIsNoOpWhenAlreadyThatKind() {
        let mounted = mountedParagraph()
        XCTAssertTrue(mounted.view.performCommand(.setBlockKind(.quote)))
        // Re-applying the same kind is a no-op and reports failure.
        XCTAssertFalse(mounted.view.performCommand(.setBlockKind(.quote)))
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .quote)
    }

    func testSetBlockKindIsUndoableRestoringPriorKindAndSelection() {
        let undoController = BlockInputUndoController()
        let mounted = mountedParagraph(undoController: undoController)
        let priorSelection = mounted.view.selection

        XCTAssertTrue(mounted.view.performCommand(.setBlockKind(.heading(level: 2))))
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .heading(level: 2))

        let undo = mounted.view.undoStructuralEdit()
        XCTAssertEqual(undo?.actionName, "Format Block")
        XCTAssertEqual(mounted.view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(undo?.selection, priorSelection)
    }

    func testCanPerformReflectsEligibility() {
        let mounted = mountedParagraph()
        XCTAssertTrue(mounted.view.canPerformCommand(.setBlockKind(.heading(level: 1))))

        let imageID = BlockInputBlockID(rawValue: "image")
        let imageMounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: imageID, kind: .image(BlockInputImage(source: "https://example.com/a.png", altText: "")))
        ])
        imageMounted.view.applySelection(.blocks([imageID]), notify: false)
        // Image blocks are not eligible source blocks for a kind conversion.
        XCTAssertFalse(imageMounted.view.canPerformCommand(.setBlockKind(.heading(level: 1))))
        XCTAssertEqual(imageMounted.view.state(for: .setBlockKind(.heading(level: 1))), .unavailable)
    }
}
