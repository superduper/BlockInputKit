import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class CodeSelectionExpansionTests: XCTestCase {
    func testRepeatedShiftDownInCodeBlockSelectsRenderedLinesSeparately() throws {
        let blockID = BlockInputBlockID(rawValue: "code")
        let text = "let one = 1\nlet two = 2\nlet three = 3"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: nil), text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = text as NSString
        let firstLineRange = textStorage.lineRange(for: NSRange(location: 0, length: 0))
        let secondLineRange = textStorage.lineRange(for: NSRange(location: NSMaxRange(firstLineRange), length: 0))
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.keyDown(with: try shiftDownEvent())
        textView.keyDown(with: try shiftDownEvent())

        let selectedRange = NSRange(location: 0, length: firstLineRange.length + secondLineRange.length)
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: blockID, range: selectedRange)))
        XCTAssertEqual(item.testingSelectionBackgroundSegmentFrames.count, 2)
    }
}
