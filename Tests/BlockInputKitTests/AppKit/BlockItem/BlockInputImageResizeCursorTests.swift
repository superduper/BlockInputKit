import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImageResizeCursorTests: XCTestCase {
    func testDirectAppKitHostUpdatesCursorOverImageResizeEdge() throws {
        let mounted = try makeDirectHostedImageEditor()
        let imageView = mounted.item.testingImageBlockView
        let edgeEvent = try mouseMovedEvent(
            location: imageView.convert(NSPoint(x: imageView.bounds.maxX, y: imageView.bounds.midY), to: nil),
            windowNumber: mounted.window.windowNumber
        )
        let centerEvent = try mouseMovedEvent(
            location: imageView.convert(NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY), to: nil),
            windowNumber: mounted.window.windowNumber
        )

        NSCursor.arrow.set()
        defer {
            NSCursor.arrow.set()
        }
        mounted.item.view.cursorUpdate(with: edgeEvent)

        XCTAssertEqual(NSCursor.current, .resizeLeftRight)

        NSCursor.arrow.set()
        mounted.item.view.cursorUpdate(with: centerEvent)

        XCTAssertNotEqual(NSCursor.current, .resizeLeftRight)
    }

    func testDirectAppKitHostInvalidatesImageResizeCursorRectsAfterAttachAndResize() throws {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        view.configure(BlockInputConfiguration(document: Self.imageDocument))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        let window = CursorInvalidationRecordingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? window.frame)
        window.contentView = host
        view.frame = host.bounds

        window.invalidatedViews.removeAll()
        host.addSubview(view)

        XCTAssertTrue(window.invalidatedViews.contains { $0 === item.view })
        XCTAssertTrue(window.invalidatedViews.contains { $0 === item.testingImageBlockView })

        window.invalidatedViews.removeAll()
        view.setFrameSize(NSSize(width: view.frame.width - 40, height: view.frame.height))

        XCTAssertTrue(window.invalidatedViews.contains { $0 === view })
        XCTAssertTrue(window.invalidatedViews.contains { $0 === view.scrollView })
        XCTAssertTrue(window.invalidatedViews.contains { $0 === view.collectionView })
        XCTAssertTrue(window.invalidatedViews.contains { $0 === item.view })
        XCTAssertTrue(window.invalidatedViews.contains { $0 === item.testingImageBlockView })
    }

    private func makeDirectHostedImageEditor() throws -> DirectHostedImageEditor {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        view.configure(BlockInputConfiguration(document: Self.imageDocument))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? window.frame)
        window.contentView = host
        view.frame = host.bounds
        host.addSubview(view)
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        return DirectHostedImageEditor(view: view, window: window, item: item)
    }

    private static var imageDocument: BlockInputDocument {
        BlockInputDocument(blocks: [
            BlockInputBlock(id: "image", kind: .image(BlockInputImage(
                source: "https://example.com/image.png",
                width: 240,
                height: 120,
                sourceStyle: .html
            )))
        ])
    }
}

private struct DirectHostedImageEditor {
    var view: BlockInputView
    var window: NSWindow
    var item: BlockInputBlockItem
}

private final class CursorInvalidationRecordingWindow: NSWindow {
    var invalidatedViews: [NSView] = []

    override func invalidateCursorRects(for view: NSView) {
        invalidatedViews.append(view)
        super.invalidateCursorRects(for: view)
    }
}
