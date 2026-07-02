import AppKit
import XCTest
@testable import BlockInputKit

/// Mounts the item's root view in a borderless window sized to the requested row size and runs layout.
///
/// Detached block-item view trees have no superview, so the root's autoresizing constraints never anchor
/// the layout engine to the frame a test sets; constraint solving then floats to the tree's fitting size
/// and every vertical measurement is taken in that unrelated coordinate space. Hosting the root view as a
/// window subview mirrors how the collection view mounts rows and makes subview frames track the row size.
@MainActor
@discardableResult
func mountForLayoutTesting(_ item: BlockInputBlockItem, size: NSSize) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    item.view.frame = NSRect(origin: .zero, size: size)
    window.contentView?.addSubview(item.view)
    item.view.layoutSubtreeIfNeeded()
    return window
}

/// The rendered text's used rect converted into the item root view's coordinate space.
@MainActor
func textUsedRect(in item: BlockInputBlockItem) throws -> NSRect {
    let textView = try XCTUnwrap(item.testingTextView)
    let layoutManager = try XCTUnwrap(textView.layoutManager)
    let textContainer = try XCTUnwrap(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer).offsetBy(
        dx: textView.textContainerOrigin.x,
        dy: textView.textContainerOrigin.y
    )
    return textView.convert(usedRect, to: item.view)
}

/// The first rendered text line's used rect converted into the item root view's coordinate space.
@MainActor
func firstTextLineRect(in item: BlockInputBlockItem) throws -> NSRect {
    let textView = try XCTUnwrap(item.testingTextView)
    let layoutManager = try XCTUnwrap(textView.layoutManager)
    let textContainer = try XCTUnwrap(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil).offsetBy(
        dx: textView.textContainerOrigin.x,
        dy: textView.textContainerOrigin.y
    )
    return textView.convert(lineRect, to: item.view)
}
