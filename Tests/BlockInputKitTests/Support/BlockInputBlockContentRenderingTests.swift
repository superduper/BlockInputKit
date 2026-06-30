import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputBlockContentRenderingTests: XCTestCase {
    // MARK: - Content identifier derivation

    func testMermaidCodeBlockResolvesToCodeMermaidIdentifier() {
        let block = BlockInputBlock(id: "m", kind: .code(language: "mermaid"), text: "graph TD; A-->B")
        XCTAssertEqual(block.renderedContentIdentifier, "code.mermaid")
    }

    func testCodeLanguageIsLowercasedInIdentifier() {
        let block = BlockInputBlock(id: "m", kind: .code(language: "Mermaid"), text: "graph TD;")
        XCTAssertEqual(block.renderedContentIdentifier, "code.mermaid")
    }

    func testCodeBlockWithoutLanguageHasNoIdentifier() {
        XCTAssertNil(BlockInputBlock(id: "c", kind: .code(language: nil), text: "x").renderedContentIdentifier)
        XCTAssertNil(BlockInputBlock(id: "c", kind: .code(language: ""), text: "x").renderedContentIdentifier)
    }

    func testNonCodeBlocksHaveNoIdentifier() {
        XCTAssertNil(BlockInputBlock(id: "p", kind: .paragraph, text: "hi").renderedContentIdentifier)
        XCTAssertNil(BlockInputBlock(id: "h", kind: .heading(level: 1), text: "hi").renderedContentIdentifier)
    }

    // MARK: - Registry resolution

    func testRegistryResolvesFirstClaimingRenderer() {
        let mermaid = StubContentRenderer(id: "mermaid", handles: ["code.mermaid"])
        let katex = StubContentRenderer(id: "katex", handles: ["code.katex"])
        let registry = BlockInputBlockContentRendererRegistry(renderers: [mermaid, katex])

        XCTAssertEqual(resolvedID(registry, "code.mermaid"), "mermaid")
        XCTAssertEqual(resolvedID(registry, "code.katex"), "katex")
        XCTAssertNil(registry.renderer(for: "code.unknown"))
    }

    func testRegistryRespectsOrderingOnOverlap() {
        let first = StubContentRenderer(id: "first", handles: ["code.mermaid"])
        let second = StubContentRenderer(id: "second", handles: ["code.mermaid"])
        let registry = BlockInputBlockContentRendererRegistry(renderers: [first, second])

        XCTAssertEqual(resolvedID(registry, "code.mermaid"), "first")
    }

    private func resolvedID(_ registry: BlockInputBlockContentRendererRegistry, _ identifier: String) -> String? {
        (registry.renderer(for: identifier) as? StubContentRenderer)?.id
    }

    func testEmptyRegistryRendersNothing() {
        let registry = BlockInputBlockContentRendererRegistry()
        XCTAssertFalse(registry.canRender(contentIdentifier: "code.mermaid"))
        XCTAssertNil(registry.renderer(for: "code.mermaid"))
    }

    // MARK: - Configuration threading

    func testConfigurationDefaultsToEmptyRendererRegistry() {
        let configuration = BlockInputConfiguration()
        XCTAssertTrue(configuration.blockContentRenderers.renderers.isEmpty)
        XCTAssertFalse(configuration.blockContentRenderers.canRender(contentIdentifier: "code.mermaid"))
    }

    func testConfigurationCarriesProvidedRendererRegistry() {
        let registry = BlockInputBlockContentRendererRegistry(
            renderers: [StubContentRenderer(id: "mermaid", handles: ["code.mermaid"])]
        )
        let configuration = BlockInputConfiguration(blockContentRenderers: registry)
        XCTAssertTrue(configuration.blockContentRenderers.canRender(contentIdentifier: "code.mermaid"))
    }

    // MARK: - Unavailable renderer

    func testUnavailableRendererNeverClaimsAndThrows() async {
        let renderer = BlockInputUnavailableContentRenderer()
        XCTAssertFalse(renderer.canRender(contentIdentifier: "code.mermaid"))

        let request = BlockInputBlockContentRequest(
            contentIdentifier: "code.mermaid",
            source: "graph TD;",
            targetWidth: 400,
            pixelScale: 2,
            cacheKey: "k"
        )
        do {
            _ = try await renderer.render(request)
            XCTFail("Expected noRendererRegistered")
        } catch {
            XCTAssertEqual(error as? BlockInputBlockContentRenderingError, .noRendererRegistered)
        }
    }
}

private final class StubContentRenderer: BlockInputBlockContentRendering {
    let id: String
    let handles: Set<String>

    init(id: String, handles: Set<String>) {
        self.id = id
        self.handles = handles
    }

    func canRender(contentIdentifier: String) -> Bool {
        handles.contains(contentIdentifier)
    }

    func render(_ request: BlockInputBlockContentRequest) async throws -> BlockInputRenderedContent {
        BlockInputRenderedContent.image(
            BlockInputRenderedImage(data: Data(), dimensions: BlockInputImageDimensions(width: 100, height: 100))
        )
    }
}
