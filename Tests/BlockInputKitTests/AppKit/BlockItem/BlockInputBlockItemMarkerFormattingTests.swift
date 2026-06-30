import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputBlockItemMarkerFormattingTests: XCTestCase {
    func testPerLineListIndentationUsesPerLineMarkersAndParagraphStyle() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "list", kind: .bulletedListItem, text: "One\nTwo\nThree"),
            allowsReordering: true,
            delegate: view
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        item.view.layoutSubtreeIfNeeded()
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let rootTextMinX = scrollView.frame.minX
        let markerView = try XCTUnwrap(item.testingMarkerView)
        let rootMarkerWidth = markerView.frame.width

        item.configure(
            block: BlockInputBlock(
                id: "list",
                kind: .bulletedListItem,
                text: "One\nTwo\nThree",
                lineIndentationLevels: [0, 1, 2]
            ),
            allowsReordering: true,
            delegate: view
        )
        item.view.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(item.testingTextView)
        let secondLineAttributes = textView.textStorage?.attributes(at: 4, effectiveRange: nil)
        let secondLineStyle = try XCTUnwrap(secondLineAttributes?[.paragraphStyle] as? NSParagraphStyle)
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        textView.textContainer?.containerSize = NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let firstLineX = layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 0)).x
        let secondLineX = layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 4)).x

        XCTAssertEqual(markerView.markerLines.map(\.text).joined(separator: "\n"), "•\n◦\n▪")
        XCTAssertEqual(markerView.markerLines, [
            BlockInputMarkerView.MarkerLine(text: "•", indentationLevel: 0),
            BlockInputMarkerView.MarkerLine(text: "◦", indentationLevel: 1),
            BlockInputMarkerView.MarkerLine(text: "▪", indentationLevel: 2)
        ])
        XCTAssertGreaterThanOrEqual(markerView.frame.width - rootMarkerWidth, 48)
        XCTAssertEqual(scrollView.frame.minX, rootTextMinX, accuracy: 0.5)
        XCTAssertEqual(markerView.font?.pointSize, BlockInputBlockItem.font(for: .bulletedListItem).pointSize)
        XCTAssertEqual(secondLineStyle.firstLineHeadIndent, 24)
        XCTAssertEqual(secondLineStyle.headIndent, 24)
        XCTAssertGreaterThan(secondLineX - firstLineX, 20)
    }

    func testPerLineNumberedMarkersKeepRootMarkerAtRootIndent() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "numbered",
                kind: .numberedListItem(start: 1),
                text: "One\nTwo",
                lineIndentationLevels: [0, 1]
            ),
            allowsReordering: true,
            delegate: view
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 80)
        item.view.layoutSubtreeIfNeeded()
        let markerView = try XCTUnwrap(item.testingMarkerView)

        XCTAssertEqual(markerView.markerLines.map(\.text).joined(separator: "\n"), "1.\na.")
        XCTAssertEqual(markerView.markerLines, [
            BlockInputMarkerView.MarkerLine(text: "1.", indentationLevel: 0),
            BlockInputMarkerView.MarkerLine(text: "a.", indentationLevel: 1)
        ])
    }

    func testMarkerViewKeepsStaticTextAccessibilityRole() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "list", kind: .bulletedListItem, text: "Accessible marker"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let markerView = try XCTUnwrap(item.testingMarkerView)

        XCTAssertEqual(markerView.accessibilityRole(), .staticText)
        XCTAssertEqual(markerView.accessibilityLabel(), "•")
    }

    func testMarkerViewIsNotAccessibilityElementWithoutVisibleMarkers() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "list", kind: .bulletedListItem, text: "Accessible marker"),
            allowsReordering: true,
            delegate: view
        )
        let markerView = try XCTUnwrap(item.testingMarkerView)
        XCTAssertTrue(markerView.isAccessibilityElement())

        item.configure(
            block: BlockInputBlock(id: "heading", kind: .heading(level: 2), text: "Heading"),
            allowsReordering: true,
            delegate: view
        )

        XCTAssertFalse(markerView.isAccessibilityElement())
        XCTAssertEqual(markerView.accessibilityLabel(), "")
    }

    func testPerLineNumberedMarkersAlignWithAssociatedTextLines() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "numbered",
                kind: .numberedListItem(start: 1),
                text: "Item 1\nItem 1a\nItem 2\nItem 2a",
                lineIndentationLevels: [0, 1, 0, 1]
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 140)
        item.view.layoutSubtreeIfNeeded()
        item.updateMarkerLineYOffsets()

        let markerView = try XCTUnwrap(item.testingMarkerView)
        XCTAssertEqual(markerView.markerLines.map(\.text).joined(separator: "\n"), "1.\na.\n2.\na.")
        XCTAssertEqual(markerView.markerLineYOffsets.count, 4)
        XCTAssertEqual(markerView.markerLineHeights.count, 4)

        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertEqual(markerView.markerLineYOffsets[1], try textMarkerYOffset(in: item, textView: textView, utf16Offset: 7), accuracy: 0.5)
        XCTAssertEqual(markerView.markerLineYOffsets[3], try textMarkerYOffset(in: item, textView: textView, utf16Offset: 22), accuracy: 0.5)
        XCTAssertEqual(markerView.markerLineHeights[1], try textMarkerHeight(in: textView, utf16Offset: 7), accuracy: 0.5)
        XCTAssertEqual(markerView.markerLineHeights[3], try textMarkerHeight(in: textView, utf16Offset: 22), accuracy: 0.5)
    }

    func testListMarkerGlyphsCenterWithinCheckboxChromeWidth() {
        let bulletWidth: CGFloat = 7.5
        let bulletX = BlockInputMarkerView.markerGlyphXPosition(indentationLevel: 0, markerWidth: bulletWidth)
        XCTAssertEqual(bulletX + bulletWidth / 2, BlockInputBlockItem.markerChromeWidth / 2, accuracy: 0.5)

        let numberWidth = ("1." as NSString).size(withAttributes: [
            .font: BlockInputBlockItem.font(for: .numberedListItem(start: 1))
        ]).width
        let numberX = BlockInputMarkerView.markerGlyphXPosition(indentationLevel: 0, markerWidth: numberWidth)
        XCTAssertEqual(numberX + numberWidth / 2, BlockInputBlockItem.markerChromeWidth / 2, accuracy: 0.5)
    }

    func testTextMarkerYPositionUsesMeasuredLineCenter() {
        XCTAssertEqual(
            BlockInputMarkerView.textMarkerYPosition(lineY: 12, lineHeight: 20, markerHeight: 16),
            14,
            accuracy: 0.5
        )
    }

    func testPerLineNumberedMarkersRestartForNestedIndentationLevels() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "numbered",
                kind: .numberedListItem(start: 1),
                text: "One\nTwo\nThree\nFour\nFive",
                lineIndentationLevels: [0, 1, 2, 1, 0]
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let markerView = try XCTUnwrap(item.testingMarkerView)

        XCTAssertEqual(markerView.markerLines.map(\.text).joined(separator: "\n"), "1.\na.\ni.\nb.\n2.")
        XCTAssertEqual(markerView.markerLines, [
            BlockInputMarkerView.MarkerLine(text: "1.", indentationLevel: 0),
            BlockInputMarkerView.MarkerLine(text: "a.", indentationLevel: 1),
            BlockInputMarkerView.MarkerLine(text: "i.", indentationLevel: 2),
            BlockInputMarkerView.MarkerLine(text: "b.", indentationLevel: 1),
            BlockInputMarkerView.MarkerLine(text: "2.", indentationLevel: 0)
        ])
    }

    func testIndentedPerLineNumberedMarkersUseStartAtBaselineIndentation() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "numbered",
                kind: .numberedListItem(start: 3),
                text: "One\nTwo\nThree",
                lineIndentationLevels: [1, 2, 1]
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let markerView = try XCTUnwrap(item.testingMarkerView)

        XCTAssertEqual(markerView.markerLines.map(\.text).joined(separator: "\n"), "c.\ni.\nd.")
        XCTAssertEqual(markerView.markerLines, [
            BlockInputMarkerView.MarkerLine(text: "c.", indentationLevel: 1),
            BlockInputMarkerView.MarkerLine(text: "i.", indentationLevel: 2),
            BlockInputMarkerView.MarkerLine(text: "d.", indentationLevel: 1)
        ])
    }

    func testClearConfigurationClearsRenderedMarkerLines() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "list",
                kind: .bulletedListItem,
                text: "One\nTwo",
                lineIndentationLevels: [0, 1]
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let markerView = try XCTUnwrap(item.testingMarkerView)
        XCTAssertEqual(markerView.markerLines, [
            BlockInputMarkerView.MarkerLine(text: "•", indentationLevel: 0),
            BlockInputMarkerView.MarkerLine(text: "◦", indentationLevel: 1)
        ])
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 80)
        item.view.layoutSubtreeIfNeeded()
        item.updateMarkerLineYOffsets()
        XCTAssertFalse(markerView.markerLineYOffsets.isEmpty)

        item.clearConfiguration()

        XCTAssertEqual(markerView.markerLines, [])
        XCTAssertEqual(markerView.markerLineYOffsets, [])
        XCTAssertEqual(markerView.markerLineHeights, [])
    }
}

@MainActor
private func textMarkerYOffset(
    in item: BlockInputBlockItem,
    textView: NSTextView,
    utf16Offset: Int
) throws -> CGFloat {
    let markerView = try XCTUnwrap(item.testingMarkerView)
    let alignmentRect = try textMarkerAlignmentRect(in: textView, utf16Offset: utf16Offset)
    let textPoint = NSPoint(x: 0, y: textView.textContainerOrigin.y + alignmentRect.minY)
    let itemPoint = textView.convert(textPoint, to: item.view)
    return markerView.convert(itemPoint, from: item.view).y
}

@MainActor
private func textMarkerHeight(
    in textView: NSTextView,
    utf16Offset: Int
) throws -> CGFloat {
    try textMarkerAlignmentRect(in: textView, utf16Offset: utf16Offset).height
}

@MainActor
private func textMarkerAlignmentRect(
    in textView: NSTextView,
    utf16Offset: Int
) throws -> NSRect {
    let layoutManager = try XCTUnwrap(textView.layoutManager)
    let textContainer = try XCTUnwrap(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let glyphIndex = layoutManager.glyphIndexForCharacter(at: utf16Offset)
    return layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
}
