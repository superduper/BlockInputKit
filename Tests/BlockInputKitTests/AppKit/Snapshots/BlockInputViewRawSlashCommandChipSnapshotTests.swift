import AppKit
import SnapshotTesting
import XCTest
@testable import BlockInputKit

@MainActor
final class RawSlashCommandChipSnapshotTests: XCTestCase {
    func testRawSlashCommandChipSnapshot() {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 520, height: 120))
        view.appearance = NSAppearance(named: .aqua)
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "command", text: "/review-github-pr https://github.com/example/repo/pull/42")
            ]),
            allowsBlockReordering: false,
            rawSlashCommandChips: true,
            dropIndicatorColor: .systemBlue
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: view,
            as: appKitSnapshotImage(),
            named: "raw-slash-command-chip-light"
        )
    }
}
