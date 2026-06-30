import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputInlineChipSelectionTests: XCTestCase {
    func testFileLinkChipBackgroundCentersOnRenderedTextLine() throws {
        let text = "Linked [../README.md](<file:///tmp/README.md>) from the launch folder"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
        ])
        resizeMountedBlockInputView(mounted, to: NSSize(width: 620, height: 140))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let chipRect = try XCTUnwrap(textView.inlineChipBackgroundRectsForTesting().only)
        let textLineBounds = try renderedTextLineBounds(in: textView, containing: "../README.md")

        XCTAssertEqual(chipRect.midY, textLineBounds.midY, accuracy: 1.0)
    }

    func testSelectedFileLinkChipBackgroundAlignsWithSelectionChrome() throws {
        let text = "Open [../README.md](<file:///tmp/README.md>) today"
        let blockID: BlockInputBlockID = "paragraph"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .paragraph, text: text)
        ])
        resizeMountedBlockInputView(mounted, to: NSSize(width: 620, height: 140))
        let chipRange = try XCTUnwrap(inlineChipRange(in: text))

        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: chipRange.contentRange)),
            notify: false
        )
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let chipRect = textView.convert(try XCTUnwrap(textView.inlineChipBackgroundRectsForTesting().only), to: item.view)
        let selectionRect = try XCTUnwrap(item.testingSelectionBackgroundSegmentFrames.only)
        let topOffset = chipRect.maxY - selectionRect.maxY
        let bottomOffset = selectionRect.minY - chipRect.minY

        XCTAssertEqual(chipRect.midY, selectionRect.midY, accuracy: 1.0)
        XCTAssertEqual(topOffset, bottomOffset, accuracy: 1.0)
    }

    func testWholeBlockSelectedFileLinkChipBackgroundAlignsWithSelectionChrome() throws {
        let text = "[.agents/checks/javascript-rules.md](<file:///tmp/.agents/checks/javascript-rules.md>) "
        let blockID: BlockInputBlockID = "paragraph"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, kind: .paragraph, text: text)
        ])
        resizeMountedBlockInputView(mounted, to: NSSize(width: 620, height: 120))

        mounted.view.applySelection(.blocks([blockID]), notify: false)
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let chipRect = textView.convert(try XCTUnwrap(textView.inlineChipBackgroundRectsForTesting().only), to: item.view)
        let selectionRect = item.testingSelectionBackgroundView.frame

        XCTAssertEqual(selectionRect.minY, chipRect.minY, accuracy: 0.5)
        XCTAssertEqual(selectionRect.maxY, chipRect.maxY, accuracy: 0.5)
    }

    private func inlineChipRange(in text: String) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        )
        .first { $0.inlineChipKind(in: text) != nil }
    }

    private func renderedTextLineBounds(in textView: NSTextView, containing substring: String) throws -> NSRect {
        let text = textView.string as NSString
        let range = text.range(of: substring)
        let characterOffset = try XCTUnwrap(range.location == NSNotFound ? nil : range.location)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterOffset)
        var lineGlyphRange = NSRange()
        _ = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
        let lineBounds = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)
        return lineBounds.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
