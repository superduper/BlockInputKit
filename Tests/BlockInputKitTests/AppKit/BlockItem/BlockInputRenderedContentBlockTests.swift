import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputRenderedContentBlockTests: XCTestCase {
    private func mermaidBlock(_ source: String = "graph TD; A-->B") -> BlockInputBlock {
        BlockInputBlock(id: "m", kind: .code(language: "mermaid"), text: source)
    }

    private func configuration(
        renderer: any BlockInputBlockContentRendering,
        isEditable: Bool = true,
        blocks: [BlockInputBlock]? = nil
    ) -> BlockInputConfiguration {
        BlockInputConfiguration(
            document: BlockInputDocument(blocks: blocks ?? [mermaidBlock()]),
            isEditable: isEditable,
            blockContentRenderers: BlockInputBlockContentRendererRegistry(renderers: [renderer])
        )
    }

    // MARK: - Surface visibility

    func testRegisteredRendererShowsDiagramSurfaceAndHidesCodeText() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        XCTAssertTrue(item.isRenderedContentBlock)
        XCTAssertFalse(item.renderedContentView.isHidden)
        XCTAssertTrue(item.scrollView.isHidden)
        XCTAssertTrue(item.codeBackgroundView.isHidden)
    }

    func testMermaidWithoutRendererFallsBackToCodeSurface() throws {
        let mounted = makeMountedBlockInputView(blocks: [mermaidBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        XCTAssertFalse(item.isRenderedContentBlock)
        XCTAssertTrue(item.renderedContentView.isHidden)
        XCTAssertFalse(item.scrollView.isHidden)
        XCTAssertFalse(item.codeBackgroundView.isHidden)
    }

    // MARK: - Layout

    func testRenderedSurfaceHugsScaledImageWidthNotFullColumn() throws {
        // A 200x100 diagram in a wide editor must size the surface to the scaled image width, so the
        // expand button and selection border align to the diagram, not the full column.
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let surfaceWidth = item.renderedContentView.frame.width
        XCTAssertEqual(surfaceWidth, 200, accuracy: 1)
        XCTAssertLessThan(surfaceWidth, item.scrollView.frame.width)
    }

    func testWholeBlockSelectionDrawsBorderOnDiagramNotTextBackground() throws {
        // Like image blocks, the selection border is drawn on the diagram surface itself (matching its
        // frame), and the text-style selection background view stays hidden — so the border can't end up
        // half the diagram's size framed against the text container.
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()
        item.requestSelectCurrentBlock()
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        XCTAssertTrue(item.renderedContentView.hasSelectionBorderForTesting)
        XCTAssertTrue(item.selectionBackgroundView.isHidden)
    }

    func testExpandButtonSitsInsideDiagramSurface() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        // The expand button's frame must lie within the surface bounds so its hit target is over the
        // visible diagram (not floating at the document's right edge).
        let buttonFrame = item.renderedContentView.expandButtonFrameForTesting
        XCTAssertTrue(item.renderedContentView.bounds.contains(buttonFrame))
        XCTAssertGreaterThan(buttonFrame.width, 0)
    }

    func testHitTestRoutesButtonRegionToButtonAndSurfaceElsewhere() throws {
        // hitTest receives points in the SUPERVIEW coordinate space; the surface must convert before
        // testing local geometry, or the expand button is never hit and zoom does nothing.
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let surface = item.renderedContentView
        guard let parent = surface.superview else {
            return XCTFail("surface must be mounted")
        }
        // The ✏️/⤢ overlay is hover-gated; simulate hover so the button is present for the hit-test.
        surface.setHoveredForTesting(true)
        let buttonCenterLocal = NSPoint(
            x: surface.expandButtonFrameForTesting.midX,
            y: surface.expandButtonFrameForTesting.midY
        )
        let buttonCenterInParent = surface.convert(buttonCenterLocal, to: parent)
        XCTAssertTrue(surface.hitTest(buttonCenterInParent) is NSButton)

        let surfaceCenterInParent = surface.convert(
            NSPoint(x: surface.bounds.midX, y: surface.bounds.midY),
            to: parent
        )
        XCTAssertTrue(surface.hitTest(surfaceCenterInParent) === surface)
    }

    // MARK: - Async reconciliation

    func testAsyncRenderResolvesDimensionsAndRemeasuresRow() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 400, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        pumpRunLoop()

        XCTAssertEqual(
            mounted.view.resolvedContentDimensions(for: "m"),
            BlockInputImageDimensions(width: 400, height: 100)
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertNotNil(item.renderedContentView.renderedImageForTesting)
        // The ✏️/⤢ overlay is hover-gated on a rendered diagram: hidden until the pointer is over it.
        XCTAssertFalse(item.renderedContentView.isExpandButtonVisibleForTesting, "hidden until hovered")
        item.renderedContentView.setHoveredForTesting(true)
        XCTAssertTrue(item.renderedContentView.isExpandButtonVisibleForTesting, "shown on hover")
        item.renderedContentView.setHoveredForTesting(false)
        XCTAssertFalse(item.renderedContentView.isExpandButtonVisibleForTesting, "hidden again on exit")
    }

    func testOversampledImageDisplaysAtLogicalPointSize() throws {
        // The renderer reports logical dimensions but ships a 2x bitmap for crispness; the displayed image's
        // point size must equal the logical dimensions (not the 2x pixel size), or it renders 2x too big.
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let image = try XCTUnwrap(item.renderedContentView.renderedImageForTesting)
        XCTAssertEqual(image.size.width, 200, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 100, accuracy: 0.5)
    }

    func testPruneDropsDimensionsForRemovedBlocks() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()
        XCTAssertNotNil(mounted.view.resolvedContentDimensions(for: "m"))

        // Reconfigure with a document that no longer contains block "m"; its stale dimensions must be pruned.
        mounted.view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "other", kind: .paragraph, text: "x")]),
            blockContentRenderers: BlockInputBlockContentRendererRegistry(renderers: [renderer])
        ))
        XCTAssertNil(mounted.view.resolvedContentDimensions(for: "m"))
    }

    func testReadOnlyEditorStillRendersAndRemeasuresDiagram() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 300, height: 150))
        let mounted = makeMountedBlockInputView(
            configuration: configuration(renderer: renderer, isEditable: false)
        )
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        pumpRunLoop()

        XCTAssertEqual(
            mounted.view.resolvedContentDimensions(for: "m"),
            BlockInputImageDimensions(width: 300, height: 150)
        )
    }

    func testDiagramRenderDoesNotRegisterUndo() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let undoController = BlockInputUndoController()
        let configuration = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [mermaidBlock()]),
            blockContentRenderers: BlockInputBlockContentRendererRegistry(renderers: [renderer]),
            undoController: undoController
        )
        let mounted = makeMountedBlockInputView(configuration: configuration)
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        pumpRunLoop()

        XCTAssertFalse(undoController.canUndo())
    }

    func testFailedRenderShowsActionableFailureSurfaceWithSourceAndError() throws {
        let renderer = StubRenderer(dimensions: nil, fails: true)
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        pumpRunLoop()

        let surface = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)).renderedContentView
        XCTAssertTrue(surface.isFailureSurfaceVisibleForTesting, "failed render should show the actionable failure surface")
        XCTAssertTrue(
            surface.failureErrorTextForTesting.contains("could not produce an image"),
            "the failure surface should carry the engine error; got: \(surface.failureErrorTextForTesting)"
        )
        XCTAssertEqual(surface.failureSourceTextForTesting, mermaidBlock().text, "the broken source should be shown")
        // The failure surface uses a COMPACT box (not the tall 16:9 placeholder); its encoded aspect is short.
        let dims = try XCTUnwrap(mounted.view.resolvedContentDimensions(for: "m"), "failure should set a compact size")
        XCTAssertLessThan(CGFloat(dims.height) / CGFloat(dims.width), 0.4, "failure box should be short/wide, not 16:9")
    }

    /// A diagram that fails to render must show "Fix with AI" / Edit (when a diagram editor is configured) so the
    /// editor — and Fix-with-AI — stays reachable. Without this, a broken diagram is a dead end.
    func testFailedRenderShowsFixWithAIWhenDiagramEditingConfigured() throws {
        let renderer = StubRenderer(dimensions: nil, fails: true)
        var config = configuration(renderer: renderer)
        config.interactiveDiagramProvider = { _ in nil } // presence enables the actions; view value is irrelevant here
        let mounted = makeMountedBlockInputView(configuration: config)
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        pumpRunLoop()

        let surface = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)).renderedContentView
        XCTAssertTrue(surface.isFailureSurfaceVisibleForTesting)
        XCTAssertTrue(surface.isFixWithAIButtonVisibleForTesting, "Fix-with-AI/Edit must be available on a failed diagram")
        XCTAssertFalse(surface.isExpandButtonVisibleForTesting, "expand should be hidden — nothing rendered to zoom")
    }

    /// Without a diagram editor configured, a failed render shows no action buttons (there is nowhere to open).
    func testFailedRenderHidesActionsWhenNoDiagramEditor() throws {
        let renderer = StubRenderer(dimensions: nil, fails: true)
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        pumpRunLoop()

        let surface = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)).renderedContentView
        XCTAssertTrue(surface.isFailureSurfaceVisibleForTesting, "the failure surface still shows the error + source")
        XCTAssertFalse(surface.isFixWithAIButtonVisibleForTesting, "no diagram editor → no Fix/Edit actions")
    }

    func testWholeBlockSelectionSelectsDiagramBlock() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()

        item.requestSelectCurrentBlock()

        XCTAssertEqual(mounted.view.selection, .blocks(["m"]))
    }

    func testExpandPresentsAndDismissesZoomModal() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()

        mounted.view.presentRenderedContentZoomModal(expansion: BlockInputRenderedContentExpansion(
            contentIdentifier: "code.mermaid",
            source: "graph TD;A-->B",
            image: BlockInputSendableImage(NSImage(size: NSSize(width: 200, height: 100)))
        ))
        XCTAssertNotNil(mounted.view.renderedContentZoomModalView)
        XCTAssertTrue(mounted.view.renderedContentZoomModalView?.superview === mounted.view)

        mounted.view.dismissRenderedContentZoomModal()
        XCTAssertNil(mounted.view.renderedContentZoomModalView)
    }

    func testZoomModalHostsLiveViewFromProvider() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let liveView = NSView()
        var capturedSource: String?
        var configuration = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [mermaidBlock()]),
            blockContentRenderers: BlockInputBlockContentRendererRegistry(renderers: [renderer])
        )
        configuration.renderedContentZoomProvider = { context in
            capturedSource = context.source
            return context.contentIdentifier == "code.mermaid" ? liveView : nil
        }
        let mounted = makeMountedBlockInputView(configuration: configuration)
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()

        mounted.view.presentRenderedContentZoomModal(expansion: BlockInputRenderedContentExpansion(
            contentIdentifier: "code.mermaid",
            source: "graph TD;A-->B",
            image: BlockInputSendableImage(NSImage(size: NSSize(width: 200, height: 100)))
        ))

        XCTAssertEqual(capturedSource, "graph TD;A-->B")
        XCTAssertTrue(liveView.isDescendant(of: try XCTUnwrap(mounted.view.renderedContentZoomModalView)))
    }

    func testZoomModalCloseButtonDismisses() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()
        mounted.view.presentRenderedContentZoomModal(expansion: BlockInputRenderedContentExpansion(
            contentIdentifier: "code.mermaid",
            source: "graph TD;A-->B",
            image: BlockInputSendableImage(NSImage(size: NSSize(width: 200, height: 100)))
        ))
        let modal = try XCTUnwrap(mounted.view.renderedContentZoomModalView)

        modal.triggerDismissForTesting()

        XCTAssertNil(mounted.view.renderedContentZoomModalView)
        XCTAssertFalse(mounted.view.pinchZoomController.isSuspended)
    }

    func testZoomModalSuspendsCanvasPinchAndRestoresOnDismiss() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()

        XCTAssertFalse(mounted.view.pinchZoomController.isSuspended)
        mounted.view.presentRenderedContentZoomModal(expansion: BlockInputRenderedContentExpansion(
            contentIdentifier: "code.mermaid",
            source: "graph TD;A-->B",
            image: BlockInputSendableImage(NSImage(size: NSSize(width: 200, height: 100)))
        ))
        XCTAssertTrue(mounted.view.pinchZoomController.isSuspended)
        mounted.view.dismissRenderedContentZoomModal()
        XCTAssertFalse(mounted.view.pinchZoomController.isSuspended)
    }

    // MARK: - Reuse

    func testReuseResetsRenderedContentState() throws {
        let renderer = StubRenderer(dimensions: BlockInputImageDimensions(width: 200, height: 100))
        let mounted = makeMountedBlockInputView(configuration: configuration(renderer: renderer))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        pumpRunLoop()

        item.prepareForReuse()

        XCTAssertFalse(item.isRenderedContentBlock)
        XCTAssertTrue(item.renderedContentView.isHidden)
        XCTAssertNil(item.renderedContentView.renderedImageForTesting)
    }

    private func pumpRunLoop(iterations: Int = 20) {
        // Drive the run loop in short slices so the detached render Task can hop back to the main actor
        // and the granular re-measure can run. Avoids batch-sensitive XCTestExpectation timeouts.
        for _ in 0..<iterations {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
}

private final class StubRenderer: BlockInputBlockContentRendering {
    let dimensions: BlockInputImageDimensions?
    let fails: Bool

    init(dimensions: BlockInputImageDimensions?, fails: Bool = false) {
        self.dimensions = dimensions
        self.fails = fails
    }

    func canRender(contentIdentifier: String) -> Bool {
        contentIdentifier == "code.mermaid"
    }

    func render(_ request: BlockInputBlockContentRequest) async throws -> BlockInputRenderedContent {
        if fails {
            throw BlockInputBlockContentRenderingError.renderFailed
        }
        let dimensions = dimensions ?? BlockInputImageDimensions(width: 100, height: 100)
        return .image(BlockInputRenderedImage(data: Self.pngData(dimensions), dimensions: dimensions))
    }

    private static func pngData(_ dimensions: BlockInputImageDimensions) -> Data {
        // Oversample the bitmap 2x to mimic the real (Retina) renderer: the PNG is 2x the logical size.
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: dimensions.width * 2,
            pixelsHigh: dimensions.height * 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        return rep?.representation(using: .png, properties: [:]) ?? Data()
    }
}
