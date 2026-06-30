import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputChipAccessoryHeightTests: XCTestCase {
    private func tagAccessoryProvider(hidesExtension: Bool = false) -> @MainActor (BlockInputChipContext) -> BlockInputChipAccessory? {
        { _ in
            BlockInputChipAccessory(reservedWidth: 28, hidesLabelExtension: hidesExtension) { rect in
                NSColor.systemBlue.setFill()
                NSBezierPath(rect: rect).fill()
            }
        }
    }

    private func chipBlock() -> BlockInputBlock {
        BlockInputBlock(id: "p", text:
            "Drag a file to the end of this sentence right here now [a-long-attached-document.pdf](<file:///tmp/a-long-attached-document.pdf>)")
    }

    /// The accessory's reserved width must influence measured height: at the widths where it tips a wrap, the accessory
    /// version measures taller than the no-accessory version. (Guards that the kern is applied in the height pass.)
    func testStaticHeightAccountsForAccessoryWidthAtSomeWidth() {
        let block = chipBlock()
        var taller = false
        for width in stride(from: CGFloat(200), through: 600, by: 2) {
            let without = BlockInputBlockItem.height(for: block, textWidth: width)
            let with = BlockInputBlockItem.height(for: block, textWidth: width, chipAccessoryProvider: tagAccessoryProvider())
            if with > without {
                taller = true
                break
            }
            XCTAssertGreaterThanOrEqual(with, without, "Accessory must never shrink measured height (width \(width)).")
        }
        XCTAssertTrue(taller, "Accessory width never increased measured height at any width; kern is not applied.")
    }

    private func mounted(width: CGFloat, text: String, withAccessory: Bool) -> BlockInputView {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: width, height: 240))
        view.appearance = NSAppearance(named: .aqua)
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "p", text: text)]),
            allowsBlockReordering: false,
            inlineChipAccessoryProvider: withAccessory ? tagAccessoryProvider() : nil
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return view
    }

    private func assertNoClip(in view: BlockInputView, context: String) throws {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let renderedTextHeight = layoutManager.usedRect(for: textContainer).height
        let rowHeight = item.view.frame.height
        XCTAssertGreaterThanOrEqual(
            rowHeight, renderedTextHeight,
            "\(context): row height \(rowHeight) clips rendered text height \(renderedTextHeight)."
        )
    }

    /// The real drag&drop scenario: inserting a file chip inline must grow the row to fit the wrapped, accessory-bearing
    /// content. Regression guard for the clip reported on drop.
    func testInlineInsertionRecalculatesRowHeight() throws {
        let view = mounted(width: 320, text: "Drag a file to the end of this sentence right here now ", withAccessory: true)
        let endOffset = (view.document.blocks[0].text as NSString).length
        _ = view.insertFileReferencesInline(
            [BlockInputFileDropReference(
                kind: .fileLink, source: "file:///tmp/a-long-attached-document.pdf", label: "a-long-attached-document.pdf"
            )],
            into: "p",
            atUTF16Offset: endOffset
        )
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        try assertNoClip(in: view, context: "after inline insertion")
    }

    /// Sweeps widths with the accessory so at least one lands the chip at a wrap boundary; none may clip.
    func testRowHeightNeverClipsAcrossWidths() throws {
        let text = "Drag dropped a file here right now [a-fairly-long-file-name.pdf](<file:///tmp/a-fairly-long-file-name.pdf>) ok"
        for width in stride(from: CGFloat(240), through: 540, by: 6) {
            try assertNoClip(in: mounted(width: width, text: text, withAccessory: true), context: "width \(width)")
        }
    }

    /// Hiding the extension shortens the visible label, which must also be reflected in measurement (no over-reserve).
    func testRowHeightNeverClipsWithHiddenExtension() throws {
        let text = "Open [a-fairly-long-file-name.pdf](<file:///tmp/a-fairly-long-file-name.pdf>) right at this boundary now ok"
        for width in stride(from: CGFloat(240), through: 540, by: 6) {
            let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: width, height: 240))
            view.appearance = NSAppearance(named: .aqua)
            view.configure(BlockInputConfiguration(
                document: BlockInputDocument(blocks: [BlockInputBlock(id: "p", text: text)]),
                allowsBlockReordering: false,
                inlineChipAccessoryProvider: tagAccessoryProvider(hidesExtension: true)
            ))
            view.layoutSubtreeIfNeeded()
            view.collectionView.layoutSubtreeIfNeeded()
            try assertNoClip(in: view, context: "hidden-ext width \(width)")
        }
    }
}
