import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputSelectionOverlayHostTests: XCTestCase {
    private final class DummyOverlayView: NSView {
        override var fittingSize: NSSize { NSSize(width: 120, height: 30) }
    }

    private let blockID = BlockInputBlockID(rawValue: "paragraph")

    private func mountWithProvider(
        text: String,
        provider: @escaping BlockInputSelectionOverlayProvider
    ) -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: blockID, text: text)]),
            selectionOverlayProvider: provider
        ))
        // Ensure the block item is mounted/laid out so anchor geometry resolves.
        _ = mounted.view.visibleBlockItemForTesting(at: 0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        return mounted
    }

    func testNonEmptySelectionMountsOverlayAboveAsSubview() throws {
        let overlay = DummyOverlayView()
        let mounted = mountWithProvider(text: "select this") { _ in overlay }

        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )), notify: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertNotNil(overlay.superview)
        let container = try XCTUnwrap(overlay.superview)
        XCTAssertTrue(container.subviews.contains(overlay))
    }

    func testCollapsingSelectionToCaretRemovesOverlay() {
        let overlay = DummyOverlayView()
        let mounted = mountWithProvider(text: "select this") { _ in overlay }

        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )), notify: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertNotNil(overlay.superview)

        mounted.view.applySelection(.cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: 3
        )), notify: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertNil(overlay.superview)
    }

    func testClearingSelectionRemovesOverlay() {
        let overlay = DummyOverlayView()
        let mounted = mountWithProvider(text: "select this") { _ in overlay }

        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )), notify: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertNotNil(overlay.superview)

        mounted.view.applySelection(nil, notify: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertNil(overlay.superview)
    }

    func testNilProviderResultSuppressesOverlay() {
        let mounted = mountWithProvider(text: "select this") { _ in nil }
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 0, length: 6)
        )), notify: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        // No provider view to assert against; assert nothing crashed and no overlay state lingers.
        XCTAssertNil(mounted.view.selectionOverlayView)
    }
}
