import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputEmptyDiagramAutoPresentTests: XCTestCase {
    /// A stub interactive view so a "provider" exists for code.mermaid.
    private final class StubView: NSView, BlockInputInteractiveBlockContent.View {
        var nsView: NSView { self }
        var currentSource: String = ""
        var onCommitSource: ((String) -> Void)?
        func tearDown() {}
    }

    func testEmptyRenderableAutoPresentsWhenEnabled() {
        let store = BlockInputMemoryDocumentStore(
            document: BlockInputDocument(blocks: [BlockInputBlock(kind: .code(language: "mermaid"), text: "")])
        )
        var config = BlockInputConfiguration(documentStore: store)
        config.autoPresentsEmptyRenderableContent = true
        config.interactiveBlockContentProvider = { _ in StubView() }
        // Register a renderer so the block is "renderable" (a no-op stub is fine for identification).
        config.blockContentRenderers = BlockInputBlockContentRendererRegistry(renderers: [StubRenderer()])

        let view = BlockInputView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.configure(config)
        window.layoutIfNeeded()

        // Pump the run loop so async block-item configuration + auto-present run.
        let exp = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exp.fulfill() }
        wait(for: [exp], timeout: 3)

        XCTAssertNotNil(view.blockContentScaffoldForTesting, "empty renderable block auto-presented the editor")
    }

    /// Minimal renderer that claims code.mermaid so the block counts as renderable.
    private final class StubRenderer: NSObject, BlockInputBlockContentRendering {
        func canRender(contentIdentifier: String) -> Bool { contentIdentifier == "code.mermaid" }
        func render(_ request: BlockInputBlockContentRequest) async throws -> BlockInputRenderedContent {
            throw BlockInputBlockContentRenderingError.renderFailed
        }
    }
}
