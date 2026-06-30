import AppKit
import XCTest
@testable import BlockInputKit

/// Guards the marker-layout stability that font zoom depends on: repeatedly reconfiguring a mounted editor
/// that contains marker-bearing blocks with a scaled base font must not crash. Before the
/// `BlockInputMarkerView` intrinsic-size guard, larger fonts drove an unbounded layout/constraint feedback
/// loop (`updateMarkerLineYOffsets` → `invalidateIntrinsicContentSize` from `viewDidLayout`), which AppKit
/// aborts with "more Update Constraints passes than views".
@MainActor
final class BlockInputZoomReconfigureTests: XCTestCase {
    private func scaledStyle(_ scale: CGFloat) -> BlockInputStyle {
        let base = NSFont.preferredFont(forTextStyle: .body)
        var style = BlockInputStyle.default
        style.baseText.font = NSFontManager.shared.convert(base, toSize: base.pointSize * scale)
        return style
    }

    private func markerHeavyDocument() -> BlockInputDocument {
        BlockInputDocument(blocks: [
            BlockInputBlock(kind: .heading(level: 1), text: "Title"),
            BlockInputBlock(kind: .bulletedListItem, text: "First bullet\nsecond line"),
            BlockInputBlock(kind: .numberedListItem(start: 1), text: "First numbered\nsecond line"),
            BlockInputBlock(kind: .checklistItem(isChecked: false), text: "Task one\ntask two"),
            BlockInputBlock(kind: .quote, text: "A quote with\ntwo lines")
        ])
    }

    private func drainMainQueue(_ rounds: Int = 20) {
        for _ in 0..<rounds {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    func testScalingFontAcrossZoomRangeDoesNotCrash() {
        let document = markerHeavyDocument()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: document,
            style: scaledStyle(1.0)
        ))
        drainMainQueue()

        // Walk the full zoom range the adapter produces: in to the max, back out, and reset.
        for scale in [1.1, 1.21, 1.331, 1.4641, 1.61, 1.0, 0.9, 0.81, 1.0] {
            mounted.view.configure(BlockInputConfiguration(document: document, style: scaledStyle(scale)))
            mounted.view.layoutSubtreeIfNeeded()
            mounted.view.collectionView.layoutSubtreeIfNeeded()
            drainMainQueue()
        }

        // The first visible list row should carry the scaled base font, proving zoom reached block text.
        let listItem = mounted.view.visibleBlockItemForTesting(at: 1)
        XCTAssertEqual(listItem?.textView.font?.pointSize, scaledStyle(1.0).baseText.font?.pointSize)
        XCTAssertEqual(mounted.view.document.blocks.count, document.blocks.count)
    }
}
