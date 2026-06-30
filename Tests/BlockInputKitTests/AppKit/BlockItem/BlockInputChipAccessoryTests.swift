import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputChipAccessoryTests: XCTestCase {
    private let chipText = "See [README.md](<file:///tmp/README.md>) for details"
    private let blockID: BlockInputBlockID = "paragraph"

    private func accessory(reservedWidth: CGFloat = 20, hidesExtension: Bool = false) -> BlockInputChipAccessory {
        BlockInputChipAccessory(reservedWidth: reservedWidth, hidesLabelExtension: hidesExtension) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(rect: rect).fill()
        }
    }

    private func mountedView(provider: (@MainActor (BlockInputChipContext) -> BlockInputChipAccessory?)?) -> BlockInputView {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 620, height: 120))
        view.appearance = NSAppearance(named: .aqua)
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: blockID, text: chipText)]),
            allowsBlockReordering: false,
            inlineChipAccessoryProvider: provider
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return view
    }

    private func textView(in view: BlockInputView) throws -> BlockInputTextView {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return try XCTUnwrap(item.testingTextView)
    }

    private func leadingBracketIndex(in textView: BlockInputTextView) throws -> Int {
        let bracket = (textView.string as NSString).range(of: "[")
        XCTAssertNotEqual(bracket.location, NSNotFound)
        return bracket.location
    }

    func testProviderMarksLeadingBracketWithAccessoryAndKern() throws {
        let view = mountedView { _ in self.accessory(reservedWidth: 20) }
        let textView = try textView(in: view)
        let storage = try XCTUnwrap(textView.textStorage)
        let index = try leadingBracketIndex(in: textView)

        XCTAssertTrue(storage.attribute(.blockInputChipLeadingAccessory, at: index, effectiveRange: nil) is BlockInputChipAccessoryAttachment)
        let kern = storage.attribute(.kern, at: index, effectiveRange: nil) as? CGFloat
        XCTAssertEqual(kern, 20)
    }

    func testNoProviderLeavesLeadingBracketUndecorated() throws {
        let view = mountedView(provider: nil)
        let textView = try textView(in: view)
        let storage = try XCTUnwrap(textView.textStorage)
        let index = try leadingBracketIndex(in: textView)
        XCTAssertNil(storage.attribute(.blockInputChipLeadingAccessory, at: index, effectiveRange: nil))
    }

    func testChipBackgroundExtendsToCoverAccessoryGap() throws {
        let withAccessory = mountedView { _ in self.accessory(reservedWidth: 20) }
        let without = mountedView(provider: nil)
        let accessoryWidth = try textView(in: withAccessory).inlineChipBackgroundRectsForTesting().reduce(0) { $0 + $1.width }
        let plainWidth = try textView(in: without).inlineChipBackgroundRectsForTesting().reduce(0) { $0 + $1.width }
        XCTAssertGreaterThan(accessoryWidth, plainWidth)
    }

    func testHidesLabelExtensionWhenRequested() throws {
        // With hidden extension, the ".md" characters are marked hidden (null-glyphed) but stay in the source string.
        let view = mountedView { _ in self.accessory(hidesExtension: true) }
        let textView = try textView(in: view)
        let storage = try XCTUnwrap(textView.textStorage)
        XCTAssertTrue(textView.string.contains("README.md"), "Source text must be unchanged.")
        let dotRange = (textView.string as NSString).range(of: ".md")
        let hidden = storage.attribute(.blockInputHiddenDelimiter, at: dotRange.location, effectiveRange: nil) as? Bool
        XCTAssertEqual(hidden, true, "Extension characters should be hidden.")
    }

    func testHiddenExtensionRangeUsesSourceCoordinatesNotUnescapedLabel() throws {
        // Escaped label: source label `a\]b.pdf` has length 8; the dot is at source offset 5. The hidden range must be
        // computed in SOURCE coordinates so the extension chars (".pdf") are hidden, not shifted by the escape.
        let source = "x [a\\]b.pdf](<file:///tmp/a.pdf>)"
        let contentRange = (source as NSString).range(of: "a\\]b.pdf")
        let hidden = try XCTUnwrap(BlockInputBlockItem.chipHiddenExtensionRange(in: source, contentRange: contentRange))
        XCTAssertEqual((source as NSString).substring(with: hidden), ".pdf")
    }

    func testHiddenExtensionRangeIgnoresNonExtensionDotsBeforeLast() throws {
        // "report.final.pdf" → only ".pdf" (the LAST dot's segment) is hidden, never ".final.pdf".
        let source = "[report.final.pdf](<file:///tmp/report.final.pdf>)"
        let contentRange = (source as NSString).range(of: "report.final.pdf")
        let hidden = try XCTUnwrap(BlockInputBlockItem.chipHiddenExtensionRange(in: source, contentRange: contentRange))
        XCTAssertEqual((source as NSString).substring(with: hidden), ".pdf")
    }

    func testHiddenExtensionRangeNilWhenNoExtension() {
        let source = "[README](<file:///tmp/README>)"
        let contentRange = (source as NSString).range(of: "README")
        XCTAssertNil(BlockInputBlockItem.chipHiddenExtensionRange(in: source, contentRange: contentRange))
    }

    func testTrailingAccessoryMarksClosingBracketWithKern() throws {
        let accessoryWithTrailing = BlockInputChipAccessory(
            reservedWidth: 0,
            draw: { _ in },
            trailingReservedWidth: 18,
            drawTrailing: { rect in NSColor.systemGreen.setFill(); NSBezierPath(rect: rect).fill() }
        )
        let view = mountedView { _ in accessoryWithTrailing }
        let textView = try textView(in: view)
        let storage = try XCTUnwrap(textView.textStorage)
        // The closing `]` is the first delimiter char after the label content.
        let labelEnd = (textView.string as NSString).range(of: "README.md")
        let closingIndex = NSMaxRange(labelEnd)
        XCTAssertTrue(storage.attribute(.blockInputChipTrailingAccessory, at: closingIndex, effectiveRange: nil) is BlockInputChipAccessoryAttachment)
        XCTAssertEqual(storage.attribute(.kern, at: closingIndex, effectiveRange: nil) as? CGFloat, 18)
    }

    func testChipBackgroundCoversTrailingAccessory() throws {
        let withTrailing = mountedView { _ in
            BlockInputChipAccessory(reservedWidth: 0, draw: { _ in }, trailingReservedWidth: 18, drawTrailing: { _ in })
        }
        let plain = mountedView(provider: nil)
        let trailingWidth = try textView(in: withTrailing).inlineChipBackgroundRectsForTesting().reduce(0) { $0 + $1.width }
        let plainWidth = try textView(in: plain).inlineChipBackgroundRectsForTesting().reduce(0) { $0 + $1.width }
        XCTAssertGreaterThan(trailingWidth, plainWidth)
    }

    func testRendersToImageForVisualInspection() throws {
        let view = mountedView { _ in self.accessory(reservedWidth: 22) }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("chip-accessory-render.png"))
        XCTAssertGreaterThan(data.count, 0)
    }
}
