import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewReloadRenderedContentTests: XCTestCase {
    /// A renderer whose output depends on EXTERNAL state (not the block's own text), so the only way it
    /// re-renders is via reloadRenderedContent — exactly the TOC situation.
    final class CountingRenderer: BlockInputBlockContentRendering, @unchecked Sendable {
        var renderCount = 0
        func canRender(contentIdentifier: String) -> Bool { contentIdentifier == "code.toc" }
        func render(_ request: BlockInputBlockContentRequest) async throws -> BlockInputRenderedContent {
            renderCount += 1
            return .view(dimensions: BlockInputImageDimensions(width: 100, height: 20),
                         factory: { NSView() })
        }
    }

    func testReloadReRendersTheBlock() throws {
        let renderer = CountingRenderer()
        let config = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "toc", kind: .code(language: "toc"), text: "")
            ]),
            blockContentRenderers: BlockInputBlockContentRendererRegistry(renderers: [renderer])
        )
        let mounted = makeMountedBlockInputView(configuration: config)
        _ = mounted.view.visibleBlockItemForTesting(at: 0)
        pumpRunLoop()
        let before = renderer.renderCount
        mounted.view.reloadRenderedContent(for: BlockInputBlockID(rawValue: "toc"))
        pumpRunLoop()
        XCTAssertGreaterThan(renderer.renderCount, before)
    }

    func testReloadAllReRendersEveryRenderedBlock() throws {
        let renderer = CountingRenderer()
        let config = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "toc1", kind: .code(language: "toc"), text: ""),
                BlockInputBlock(id: "toc2", kind: .code(language: "toc"), text: "")
            ]),
            blockContentRenderers: BlockInputBlockContentRendererRegistry(renderers: [renderer])
        )
        let mounted = makeMountedBlockInputView(configuration: config)
        _ = mounted.view.visibleBlockItemForTesting(at: 0)
        _ = mounted.view.visibleBlockItemForTesting(at: 1)
        pumpRunLoop()
        let before = renderer.renderCount
        mounted.view.reloadRenderedContent()
        pumpRunLoop()
        XCTAssertGreaterThanOrEqual(renderer.renderCount, before + 2)
    }

    func testReloadUnknownIDIsNoop() {
        let renderer = CountingRenderer()
        let config = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "toc", kind: .code(language: "toc"), text: "")
            ]),
            blockContentRenderers: BlockInputBlockContentRendererRegistry(renderers: [renderer])
        )
        let mounted = makeMountedBlockInputView(configuration: config)
        _ = mounted.view.visibleBlockItemForTesting(at: 0)
        pumpRunLoop()
        let before = renderer.renderCount
        mounted.view.reloadRenderedContent(for: BlockInputBlockID(rawValue: "nonexistent"))
        pumpRunLoop()
        XCTAssertEqual(renderer.renderCount, before)
    }

    // MARK: - Helpers

    private func pumpRunLoop(iterations: Int = 20) {
        for _ in 0..<iterations {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
}
