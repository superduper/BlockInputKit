import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputRenderedContentViewModeTests: XCTestCase {
    func testInlineHostsAViewModeRenderersView() throws {
        let marker = NSView()
        let renderer = ViewModeStubRenderer(view: marker)
        let block = BlockInputBlock(kind: .code(language: "mermaid"), text: "graph TD\nA-->B")
        let config = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [block]),
            blockContentRenderers: BlockInputBlockContentRendererRegistry(renderers: [renderer])
        )
        let mounted = makeMountedBlockInputView(configuration: config)
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()
        // The view-mode renderer's view should be installed in the rendered-content surface.
        let surface = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)).renderedContentView
        XCTAssertTrue(marker.isDescendant(of: surface), "view-mode renderer's NSView is hosted inline")
    }

    private func pumpRunLoop(iterations: Int = 20) {
        for _ in 0..<iterations {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
}

private struct ViewModeStubRenderer: BlockInputBlockContentRendering {
    let view: NSView
    func canRender(contentIdentifier: String) -> Bool { contentIdentifier == "code.mermaid" }
    func render(_ request: BlockInputBlockContentRequest) async throws -> BlockInputRenderedContent {
        let captured = view
        return .view(dimensions: BlockInputImageDimensions(width: 200, height: 100), factory: { captured })
    }
}
