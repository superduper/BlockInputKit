import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputImageBlockInsetTests: XCTestCase {
    func testImageBlockMultiplierKeepsMinimumDisplayHeightStable() {
        let block = BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 1, height: 1)))

        let compactHeight = BlockInputBlockItem.height(for: block, textWidth: 360, blockVerticalInsetMultiplier: 0.5)
        let zeroInsetHeight = BlockInputBlockItem.height(for: block, textWidth: 360, blockVerticalInsetMultiplier: 0)

        XCTAssertEqual(compactHeight, 44 + BlockInputBlockItem.imageExternalVerticalInset, accuracy: 0.5)
        XCTAssertEqual(zeroInsetHeight, 44, accuracy: 0.5)
    }

    func testImageBlockUsesScaledVerticalInsets() throws {
        let multiplier: CGFloat = 0.5
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(kind: .image(BlockInputImage(source: "https://example.com/image.png", width: 80, height: 40)))
            ]),
            blockVerticalInsetMultiplier: multiplier
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let imageView = item.testingImageBlockView

        XCTAssertEqual(imageView.frame.minY, BlockInputBlockItem.imageExternalVerticalInset * multiplier, accuracy: 0.5)
        XCTAssertEqual(item.view.bounds.height - imageView.frame.maxY, BlockInputBlockItem.imageExternalVerticalInset * multiplier, accuracy: 0.5)
    }
}
