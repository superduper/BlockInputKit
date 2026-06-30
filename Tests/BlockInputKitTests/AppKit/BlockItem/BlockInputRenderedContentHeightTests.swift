import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputRenderedContentHeightTests: XCTestCase {
    private let mermaid = BlockInputBlock(id: "m", kind: .code(language: "mermaid"), text: "graph TD; A-->B")
    private let registry = BlockInputBlockContentRendererRegistry(
        renderers: [HeightStubRenderer(handles: ["code.mermaid"])]
    )

    func testWithoutRendererMermaidUsesCodeTextHeight() {
        let codeHeight = BlockInputBlockItem.height(for: mermaid, textWidth: 400)
        let renderedHeight = BlockInputBlockItem.height(
            for: mermaid,
            textWidth: 400,
            contentRenderers: registry,
            resolvedContentDimensions: nil
        )
        // The diagram-surface (placeholder) height should differ from the code-text height,
        // confirming the rendered branch only activates when a renderer is registered.
        XCTAssertNotEqual(codeHeight, renderedHeight)
    }

    func testPlaceholderHeightUsesDefaultAspectRatioBeforeRender() {
        let height = BlockInputBlockItem.height(
            for: mermaid,
            textWidth: 320,
            contentRenderers: registry,
            resolvedContentDimensions: nil
        )
        let expected = BlockInputBlockItem.renderedContentHeight(
            resolvedDimensions: nil,
            textWidth: 320 - BlockInputBlockItem.perLineContentIndent(for: mermaid),
            defaultAspectRatio: 16.0 / 9.0
        )
        XCTAssertEqual(height, expected, accuracy: 0.5)
    }

    func testResolvedDimensionsDriveScaleToFitHeight() {
        // A 200x100 (2:1) diagram in a 400pt column fits at full width -> ~200pt tall content.
        let resolved = BlockInputImageDimensions(width: 200, height: 100)
        let displaySize = BlockInputBlockItem.renderedContentDisplaySize(
            resolvedDimensions: resolved,
            textWidth: 400,
            defaultAspectRatio: 16.0 / 9.0
        )
        XCTAssertEqual(displaySize.width, 200, accuracy: 0.5)
        XCTAssertEqual(displaySize.height, 100, accuracy: 0.5)
    }

    func testWideDiagramScalesDownToColumnWidth() {
        // A 1000x500 diagram must scale down to a 300pt column, preserving 2:1 aspect.
        let resolved = BlockInputImageDimensions(width: 1000, height: 500)
        let displaySize = BlockInputBlockItem.renderedContentDisplaySize(
            resolvedDimensions: resolved,
            textWidth: 300,
            defaultAspectRatio: 16.0 / 9.0
        )
        XCTAssertEqual(displaySize.width, 300, accuracy: 1)
        XCTAssertEqual(displaySize.height, 150, accuracy: 1)
    }

    func testResolvedDimensionsChangeHeightFromPlaceholder() {
        let placeholder = BlockInputBlockItem.height(
            for: mermaid,
            textWidth: 400,
            contentRenderers: registry,
            resolvedContentDimensions: nil
        )
        let resolved = BlockInputBlockItem.height(
            for: mermaid,
            textWidth: 400,
            contentRenderers: registry,
            resolvedContentDimensions: BlockInputImageDimensions(width: 400, height: 120)
        )
        XCTAssertNotEqual(placeholder, resolved)
    }
}

private struct HeightStubRenderer: BlockInputBlockContentRendering {
    let handles: Set<String>

    func canRender(contentIdentifier: String) -> Bool {
        handles.contains(contentIdentifier)
    }

    func render(_ request: BlockInputBlockContentRequest) async throws -> BlockInputRenderedContent {
        BlockInputRenderedContent.image(
            BlockInputRenderedImage(data: Data(), dimensions: BlockInputImageDimensions(width: 1, height: 1))
        )
    }
}
