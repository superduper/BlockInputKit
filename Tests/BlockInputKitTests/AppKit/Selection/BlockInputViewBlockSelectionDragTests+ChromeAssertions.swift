import AppKit
import XCTest
@testable import BlockInputKit

extension BlockInputViewBlockSelectionDragTests {
    func viewX(forUTF16Offset offset: Int, in item: BlockInputBlockItem) throws -> CGFloat {
        let textView = try XCTUnwrap(item.testingTextView)
        let textContainerX = try XCTUnwrap(item.textContainerX(forUTF16Offset: offset))
        let textContainerOrigin = textView.textContainerOrigin
        return textView.convert(
            NSPoint(x: textContainerOrigin.x + textContainerX, y: textContainerOrigin.y),
            to: item.view
        ).x
    }

    func assertPartialSelectionChromeMatchesRenderedLine(
        in item: BlockInputBlockItem,
        utf16Offset: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let chromeFrame = item.testingSelectionBackgroundView.frame
        let lineFrame = try renderedLineFrame(in: item, utf16Offset: utf16Offset, file: file, line: line)

        XCTAssertEqual(chromeFrame.height, lineFrame.height, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(chromeFrame.midY, lineFrame.midY, accuracy: 0.5, file: file, line: line)
    }

    private func renderedLineFrame(
        in item: BlockInputBlockItem,
        utf16Offset: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSRect {
        let textView = try XCTUnwrap(item.testingTextView, file: file, line: line)
        let layoutManager = try XCTUnwrap(textView.layoutManager, file: file, line: line)
        let textContainer = try XCTUnwrap(textView.textContainer, file: file, line: line)
        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: utf16Offset)
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return textView.convert(lineRect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y), to: item.view)
    }
}
