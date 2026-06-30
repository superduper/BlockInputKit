import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputBlockItemMarkerSpacingTests: XCTestCase {
    func testListMarkerToTextGapUsesMarkerSlotForNumberedLists() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "numbered",
                kind: .numberedListItem(start: 1),
                text: "Item 1\nItem 1a",
                lineIndentationLevels: [0, 1]
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 80)
        item.view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(
            try listTextGap(in: item, textView: textView, utf16Offset: 0, indentationLevel: 0),
            0,
            accuracy: 0.5
        )
        XCTAssertEqual(
            try listTextGap(in: item, textView: textView, utf16Offset: 7, indentationLevel: 1),
            0,
            accuracy: 0.5
        )
    }

    func testWideNumberedMarkersDoNotOverlapText() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "numbered",
                kind: .numberedListItem(start: 100),
                text: "Hundred"
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 60)
        item.view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(item.testingTextView)

        let markerGap = try textMarkerGap(in: item, textView: textView, markerText: "100.", utf16Offset: 0, indentationLevel: 0)
        XCTAssertGreaterThanOrEqual(markerGap, BlockInputBlockItem.minimumMarkerTextGap - 0.5)
    }

    func testListMarkerToTextGapUsesMarkerSlotForBulletedLists() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "bulleted",
                kind: .bulletedListItem,
                text: "Item 1\nItem 1a",
                lineIndentationLevels: [0, 1]
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 80)
        item.view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(
            try listTextGap(in: item, textView: textView, utf16Offset: 0, indentationLevel: 0),
            0,
            accuracy: 0.5
        )
        XCTAssertEqual(
            try listTextGap(in: item, textView: textView, utf16Offset: 7, indentationLevel: 1),
            0,
            accuracy: 0.5
        )
    }

    func testListMarkerToTextGapUsesMarkerSlotForWholeBlockIndentation() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "indented",
                kind: .bulletedListItem,
                text: "Indented",
                indentationLevel: 2
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 44)
        item.view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(
            try listTextGap(in: item, textView: textView, utf16Offset: 0, indentationLevel: 0),
            0,
            accuracy: 0.5
        )
    }

    func testListMarkerSpacingAppliesToChecklistText() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "checklist",
                kind: .checklistItem(isChecked: false),
                text: "Todo"
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 44)
        item.view.layoutSubtreeIfNeeded()

        let checkbox = try XCTUnwrap(item.testingChecklistButton)
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(
            try textGlyphLeadingX(in: item, textView: textView, utf16Offset: 0) - checkbox.frame.maxX,
            BlockInputBlockItem.markerGutterWidth - checkbox.frame.width,
            accuracy: 0.5
        )
    }

    func testListMarkerSpacingAppliesToIndentedChecklistText() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "checklist",
                kind: .checklistItem(isChecked: false),
                text: "Nested",
                indentationLevel: 2
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 44)
        item.view.layoutSubtreeIfNeeded()

        let checkbox = try XCTUnwrap(item.testingChecklistButton)
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(
            try textGlyphLeadingX(in: item, textView: textView, utf16Offset: 0) - checkbox.frame.maxX,
            BlockInputBlockItem.markerGutterWidth - checkbox.frame.width,
            accuracy: 0.5
        )
    }

    func testListMarkerSpacingAppliesToPerLineChecklistText() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "checklist",
                kind: .checklistItem(isChecked: false),
                text: "Root\nNested",
                lineIndentationLevels: [0, 1]
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 80)
        item.view.layoutSubtreeIfNeeded()

        let checkbox = try XCTUnwrap(item.testingChecklistButton)
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(
            try textGlyphLeadingX(in: item, textView: textView, utf16Offset: 0) - checkbox.frame.maxX,
            BlockInputBlockItem.markerGutterWidth - checkbox.frame.width,
            accuracy: 0.5
        )
        XCTAssertEqual(
            try listTextGap(in: item, textView: textView, utf16Offset: 5, indentationLevel: 1),
            0,
            accuracy: 0.5
        )
    }
}

@MainActor
private func listTextGap(
    in item: BlockInputBlockItem,
    textView: NSTextView,
    utf16Offset: Int,
    indentationLevel: Int
) throws -> CGFloat {
    let markerView = try XCTUnwrap(item.testingMarkerView)
    let textItemPointX = try textGlyphLeadingX(in: item, textView: textView, utf16Offset: utf16Offset)
    let markerTrailing = markerView.frame.minX
        + BlockInputBlockItem.contentIndent(forIndentationLevel: indentationLevel)
        + BlockInputBlockItem.markerGutterWidth
    return textItemPointX - markerTrailing
}

@MainActor
private func textMarkerGap(
    in item: BlockInputBlockItem,
    textView: NSTextView,
    markerText: String,
    utf16Offset: Int,
    indentationLevel: Int
) throws -> CGFloat {
    let markerView = try XCTUnwrap(item.testingMarkerView)
    let markerWidth = (markerText as NSString).size(withAttributes: [
        .font: BlockInputBlockItem.font(for: .numberedListItem(start: 1))
    ]).width
    let markerTrailing = markerView.frame.minX
        + BlockInputMarkerView.markerGlyphXPosition(indentationLevel: indentationLevel, markerWidth: markerWidth)
        + markerWidth
    return try textGlyphLeadingX(in: item, textView: textView, utf16Offset: utf16Offset) - markerTrailing
}

@MainActor
private func textGlyphLeadingX(
    in item: BlockInputBlockItem,
    textView: NSTextView,
    utf16Offset: Int
) throws -> CGFloat {
    let layoutManager = try XCTUnwrap(textView.layoutManager)
    let textContainer = try XCTUnwrap(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let glyphIndex = layoutManager.glyphIndexForCharacter(at: utf16Offset)
    let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
    let textPoint = NSPoint(
        x: textView.textContainerOrigin.x + glyphLocation.x,
        y: textView.textContainerOrigin.y
    )
    return textView.convert(textPoint, to: item.view).x
}
