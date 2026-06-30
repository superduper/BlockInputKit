import AppKit
@testable import BlockInputKit

@MainActor
func makeMountedBlockInputView(
    configuration: BlockInputConfiguration,
    size: NSSize = NSSize(width: 720, height: 480),
    styleMask: NSWindow.StyleMask = [.titled]
) -> (view: BlockInputView, window: NSWindow) {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: styleMask,
        backing: .buffered,
        defer: false
    )
    let view = BlockInputView(frame: window.contentView?.bounds ?? window.frame)
    window.contentView = view
    view.configure(configuration)
    view.layoutSubtreeIfNeeded()
    view.collectionView.layoutSubtreeIfNeeded()
    return (view, window)
}

@MainActor
func makeMountedBlockInputView(
    document: BlockInputDocument,
    undoController: BlockInputUndoController = BlockInputUndoController()
) -> (view: BlockInputView, window: NSWindow) {
    makeMountedBlockInputView(configuration: BlockInputConfiguration(
        document: document,
        undoController: undoController
    ))
}

@MainActor
func makeMountedBlockInputView(blocks: [BlockInputBlock]) -> (view: BlockInputView, window: NSWindow) {
    makeMountedBlockInputView(document: BlockInputDocument(blocks: blocks))
}

@MainActor
func resizeMountedBlockInputView(
    _ mounted: (view: BlockInputView, window: NSWindow),
    to size: NSSize
) {
    mounted.window.setContentSize(size)
    mounted.view.frame = mounted.window.contentView?.bounds ?? mounted.view.frame
    mounted.view.layoutSubtreeIfNeeded()
    mounted.view.scrollView.layoutSubtreeIfNeeded()
    mounted.view.collectionView.layoutSubtreeIfNeeded()
}

extension BlockInputView {
    func visibleBlockItemForTesting(at item: Int) -> BlockInputBlockItem? {
        collectionView.scrollToItems(at: [IndexPath(item: item, section: 0)], scrollPosition: .nearestVerticalEdge)
        collectionView.layoutSubtreeIfNeeded()
        return collectionView.item(at: IndexPath(item: item, section: 0)) as? BlockInputBlockItem
    }
}
