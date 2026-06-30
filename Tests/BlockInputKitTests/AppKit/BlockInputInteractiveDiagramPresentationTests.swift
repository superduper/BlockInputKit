import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputInteractiveDiagramPresentTests: XCTestCase {
    private func mermaidBlock(_ source: String = "graph TD\nA-->B") -> BlockInputBlock {
        BlockInputBlock(kind: .code(language: "mermaid"), text: source)
    }

    func testPresentsProviderViewInScaffoldAndCommitsOnSourceChange() throws {
        let block = mermaidBlock()
        let stub = StubInteractiveView(source: block.text)
        var config = BlockInputConfiguration(document: BlockInputDocument(blocks: [block]))
        config.blockContentRenderers = BlockInputBlockContentRendererRegistry(renderers: [StubMermaidImageRenderer()])
        config.interactiveBlockContentProvider = { _ in stub }
        let (view, _) = makeMountedBlockInputView(configuration: config)

        view.presentInteractiveBlockContent(blockID: block.id, contentIdentifier: "code.mermaid", source: block.text)
        XCTAssertNotNil(view.blockContentScaffoldForTesting)
        XCTAssertTrue(stub.nsView.isDescendant(of: try XCTUnwrap(view.blockContentScaffoldForTesting)))

        // The plugin commits an edited source; closing writes it to the document.
        stub.commit("graph LR\nX-->Y")
        view.dismissInteractiveBlockContent()
        XCTAssertEqual(view.block(withID: block.id)?.text, "graph LR\nX-->Y")
    }

    func testShowsFailureSurfaceWhenProviderReturnsNil() throws {
        let block = mermaidBlock()
        var config = BlockInputConfiguration(document: BlockInputDocument(blocks: [block]))
        config.blockContentRenderers = BlockInputBlockContentRendererRegistry(renderers: [StubMermaidImageRenderer()])
        config.interactiveBlockContentProvider = { _ in nil }
        let (view, _) = makeMountedBlockInputView(configuration: config)

        view.presentInteractiveBlockContent(blockID: block.id, contentIdentifier: "code.mermaid", source: block.text)
        XCTAssertTrue(view.blockContentFailureForTesting)
    }
}

@MainActor
private final class StubInteractiveView: NSObject, BlockInputInteractiveBlockContent.View {
    private let view = NSView()
    private(set) var currentSource: String
    var onCommitSource: ((String) -> Void)?
    init(source: String) { self.currentSource = source }
    var nsView: NSView { view }
    func tearDown() {}
    func commit(_ source: String) { currentSource = source; onCommitSource?(source) }
}

private struct StubMermaidImageRenderer: BlockInputBlockContentRendering {
    func canRender(contentIdentifier: String) -> Bool { contentIdentifier == "code.mermaid" }
    func render(_ request: BlockInputBlockContentRequest) async throws -> BlockInputRenderedContent {
        .image(BlockInputRenderedImage(data: Data(), dimensions: BlockInputImageDimensions(width: 1, height: 1)))
    }
}
