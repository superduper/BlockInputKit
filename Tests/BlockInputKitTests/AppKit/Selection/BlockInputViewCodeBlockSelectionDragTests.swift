import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class CodeBlockSelectionDragTests: XCTestCase {
    func testMouseDragWithinMultilineCodeBlockSelectsRenderedLinesSeparately() throws {
        let blockID = BlockInputBlockID(rawValue: "code")
        let text = "let one = 1\nlet two = 2\nlet three = 3"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .code(language: nil), text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = text as NSString
        let startOffset = textStorage.range(of: "one").location
        let endOffset = textStorage.range(of: "two").location + 3
        let startLocation = try windowLocation(forUTF16Offset: startOffset, in: textView)
        let endLocation = try windowLocation(forUTF16Offset: endOffset, in: textView)

        textView.mouseDown(with: try mouseDownEvent(location: startLocation, windowNumber: mounted.window.windowNumber))
        textView.mouseDragged(with: try mouseDraggedEvent(location: endLocation, windowNumber: mounted.window.windowNumber))
        textView.mouseUp(with: try mouseUpEvent(location: endLocation, windowNumber: mounted.window.windowNumber))

        let selectedRange = NSRange(location: startOffset, length: endOffset - startOffset)
        XCTAssertEqual(textView.selectedRange(), selectedRange)
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: blockID, range: selectedRange)))
        XCTAssertEqual(item.testingSelectionBackgroundSegmentFrames.count, 2)
    }
}
