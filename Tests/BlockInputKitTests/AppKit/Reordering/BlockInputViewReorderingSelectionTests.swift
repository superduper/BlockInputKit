import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewReorderingSelectionTests: XCTestCase {
    func testCollectionReorderStartCancelsMultiSelection() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = configuredReorderView(blockIDs: [firstID, secondID])
        view.applySelection(.blocks([firstID, secondID]), notify: true)

        _ = view.collectionView(
            view.collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        )

        XCTAssertNil(view.selection)
    }

    func testHandleReorderStartCancelsMixedSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: secondID, range: NSRange(location: 0, length: 1))
        )), notify: true)

        mounted.view.blockItemDidBeginReordering(firstItem, blockID: firstID)

        XCTAssertNil(mounted.view.selection)
        XCTAssertTrue(firstItem.testingSelectionBackgroundView.isHidden)
        XCTAssertEqual(mounted.view.visibleBlockItemForTesting(at: 1)?.testingSelectionBackgroundView.isHidden, true)
    }

    private func configuredReorderView(blockIDs: [BlockInputBlockID]) -> BlockInputView {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: blockIDs.map { blockID in
                BlockInputBlock(id: blockID, text: blockID.rawValue)
            }),
            allowsBlockReordering: true
        ))
        return view
    }
}
