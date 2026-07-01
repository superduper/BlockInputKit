import AppKit
import XCTest
@testable import BlockInputKit

/// Tests the anchored-accessory API: pin a host NSView to a `(blockID, range)` region so the editor keeps it
/// positioned as the document scrolls/grows, clips it, and hides it when its anchor is off-screen. This is the
/// core seam a ⌘K / inline-edit plugin uses instead of wiring up its own scroll/frame observers.
@MainActor
final class BlockInputAnchoredAccessoryTests: XCTestCase {

    private let blockID = BlockInputBlockID(rawValue: "b1")

    private func mount(_ text: String) -> (view: BlockInputView, window: NSWindow) {
        makeMountedBlockInputView(blocks: [BlockInputBlock(id: blockID, text: text)])
    }

    /// A fixed-size accessory so `fittingSize` (and thus the expected frame) is deterministic.
    private func makeAccessory(width: CGFloat = 80, height: CGFloat = 24) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height)
        ])
        return view
    }

    // MARK: add

    func test_add_installsSubview_withNonZeroFrameNearBlockRect() {
        let (view, _) = mount("The quick brown fox jumps over the lazy dog.")
        let accessory = makeAccessory()
        let range = NSRange(location: 0, length: 9)

        let handle = view.addAnchoredAccessory(accessory, blockID: blockID, range: range)

        XCTAssertTrue(accessory.isDescendant(of: view))
        XCTAssertFalse(accessory.isHidden)
        XCTAssertGreaterThan(accessory.frame.width, 0)
        XCTAssertGreaterThan(accessory.frame.height, 0)
        XCTAssertEqual(view.anchoredAccessoryCountForTesting, 1)

        // Positioned near the anchored range's rect (within a generous vertical band accounting for gap + height).
        let rect = try? XCTUnwrap(view.rectForRange(range, in: blockID))
        if let rect {
            XCTAssertLessThan(abs(accessory.frame.midX - clampedMidX(rect: rect, width: accessory.frame.width, in: view)), 1)
            XCTAssertLessThan(abs(accessory.frame.minY - rect.minY), accessory.frame.height + 12)
        }
        _ = handle
    }

    func test_add_enablesEditorClipping() {
        let (view, _) = mount("hello world")
        XCTAssertFalse(view.clipsToBounds)
        view.addAnchoredAccessory(makeAccessory(), blockID: blockID, range: NSRange(location: 0, length: 5))
        XCTAssertTrue(view.clipsToBounds)
    }

    // MARK: alignment

    func test_alignment_trailing_placesAtRectMaxX() throws {
        let (view, _) = mount("The quick brown fox jumps over the lazy dog.")
        let accessory = makeAccessory(width: 40)
        let range = NSRange(location: 0, length: 9)

        view.addAnchoredAccessory(accessory, blockID: blockID, range: range, alignment: .trailing)

        let rect = try XCTUnwrap(view.rectForRange(range, in: blockID))
        // .trailing => origin at rect.maxX - width (before horizontal clamp, which shouldn't trigger here).
        XCTAssertEqual(accessory.frame.maxX, rect.maxX, accuracy: 1)
    }

    func test_alignment_center_centersOnRect() throws {
        let (view, _) = mount("The quick brown fox jumps over the lazy dog.")
        let accessory = makeAccessory(width: 40)
        let range = NSRange(location: 0, length: 9)

        view.addAnchoredAccessory(accessory, blockID: blockID, range: range, alignment: .center)

        let rect = try XCTUnwrap(view.rectForRange(range, in: blockID))
        XCTAssertEqual(accessory.frame.midX, rect.midX, accuracy: 1)
    }

    // MARK: update

    func test_updateRange_movesAccessory() {
        let (view, _) = mount("The quick brown fox jumps over the lazy dog.")
        let accessory = makeAccessory()
        let handle = view.addAnchoredAccessory(
            accessory,
            blockID: blockID,
            range: NSRange(location: 0, length: 3),
            alignment: .leading
        )
        let firstFrame = accessory.frame

        view.updateAnchoredAccessoryRange(handle.id, blockID: blockID, range: NSRange(location: 30, length: 4))
        let secondFrame = accessory.frame

        // Anchoring to a later range should move the accessory horizontally (leading edge follows the rect).
        XCTAssertNotEqual(firstFrame.origin.x, secondFrame.origin.x, accuracy: 0)
        XCTAssertGreaterThan(secondFrame.minX, firstFrame.minX)
    }

    // MARK: remove

    func test_remove_detachesSubview_andStopsTracking() {
        let (view, _) = mount("hello world")
        let accessory = makeAccessory()
        let handle = view.addAnchoredAccessory(accessory, blockID: blockID, range: NSRange(location: 0, length: 5))
        XCTAssertTrue(accessory.isDescendant(of: view))

        view.removeAnchoredAccessory(handle.id)

        XCTAssertFalse(accessory.isDescendant(of: view))
        XCTAssertEqual(view.anchoredAccessoryCountForTesting, 0)
    }

    func test_removeAll_detachesEverySubview() {
        let (view, _) = mount("hello world")
        let first = makeAccessory()
        let second = makeAccessory()
        view.addAnchoredAccessory(first, blockID: blockID, range: NSRange(location: 0, length: 2))
        view.addAnchoredAccessory(second, blockID: blockID, range: NSRange(location: 3, length: 2))
        XCTAssertEqual(view.anchoredAccessoryCountForTesting, 2)

        view.removeAllAnchoredAccessories()

        XCTAssertFalse(first.isDescendant(of: view))
        XCTAssertFalse(second.isDescendant(of: view))
        XCTAssertEqual(view.anchoredAccessoryCountForTesting, 0)
    }

    // MARK: off-screen hiding

    func test_offScreen_bogusBlock_hidesAccessory() {
        let (view, _) = mount("hello world")
        let accessory = makeAccessory()
        // Anchor to a block that isn't mounted → rectForRange returns nil → accessory hides.
        view.addAnchoredAccessory(
            accessory,
            blockID: BlockInputBlockID(rawValue: "does-not-exist"),
            range: NSRange(location: 0, length: 1)
        )
        XCTAssertTrue(accessory.isDescendant(of: view))
        XCTAssertTrue(accessory.isHidden)
    }

    // MARK: helpers

    /// Expected clamped midX for a `.trailing`-with-implicit-default accessory; here alignment defaults to
    /// `.trailing`, so origin is rect.maxX - width, clamped inside the editor with an 8pt margin.
    private func clampedMidX(rect: NSRect, width: CGFloat, in view: BlockInputView) -> CGFloat {
        var originX = rect.maxX - width
        let margin: CGFloat = 8
        let minX = view.bounds.minX + margin
        let maxX = view.bounds.maxX - margin - width
        if maxX >= minX {
            originX = min(max(originX, minX), maxX)
        } else {
            originX = minX
        }
        return originX + width / 2
    }
}
