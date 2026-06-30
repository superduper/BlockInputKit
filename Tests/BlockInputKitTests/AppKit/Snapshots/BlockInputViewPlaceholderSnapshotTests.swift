import AppKit
import SnapshotTesting
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewPlaceholderSnapshotTests: XCTestCase {
    func testPlaceholderSnapshot() {
        let view = BlockInputView(frame: NSRect(origin: .zero, size: CGSize(width: 620, height: 180)))
        view.appearance = NSAppearance(named: .aqua)
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(),
            allowsBlockReordering: false,
            placeholder: "Ask anything",
            dropIndicatorColor: .systemBlue
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: view,
            as: appKitSnapshotImage(),
            named: "placeholder-light"
        )
    }
}
