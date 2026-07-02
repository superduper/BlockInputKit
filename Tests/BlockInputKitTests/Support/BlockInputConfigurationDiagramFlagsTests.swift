import XCTest
@testable import BlockInputKit

final class BlockInputConfigurationDiagramFlagsTests: XCTestCase {
    func testDiagramLifecycleFlagsDefaultFalse() {
        let config = BlockInputConfiguration(document: BlockInputDocument(blocks: [BlockInputBlock(text: "x")]))
        XCTAssertFalse(config.autoPresentsEmptyRenderableContent)
        XCTAssertFalse(config.removesEmptyRenderableOnClose)
    }

    func testDiagramLifecycleFlagsSettable() {
        var config = BlockInputConfiguration(document: BlockInputDocument(blocks: [BlockInputBlock(text: "x")]))
        config.autoPresentsEmptyRenderableContent = true
        config.removesEmptyRenderableOnClose = true
        XCTAssertTrue(config.autoPresentsEmptyRenderableContent)
        XCTAssertTrue(config.removesEmptyRenderableOnClose)
    }
}
