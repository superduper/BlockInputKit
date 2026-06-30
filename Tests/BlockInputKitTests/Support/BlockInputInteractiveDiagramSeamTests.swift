// Tests/BlockInputKitTests/Support/BlockInputInteractiveDiagramSeamTests.swift
import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputInteractiveDiagramSeamTests: XCTestCase {
    /// A minimal conformer proves the protocol surface is usable: context carries source + validate + backend;
    /// the view exposes its NSView, current source, and a commit hook the host can read back.
    func testInteractiveViewExposesSourceAndCommitHook() {
        let context = BlockInputInteractiveDiagramContext(
            contentIdentifier: "code.mermaid",
            source: "graph TD\nA-->B",
            validate: { _ in .invalid(message: "stub") },
            aiBackend: nil
        )
        let view = StubInteractiveDiagramView(context: context)
        XCTAssertEqual(view.currentSource, "graph TD\nA-->B")

        var committed: String?
        view.onCommitSource = { committed = $0 }
        view.commitForTesting("graph LR\nX-->Y")
        XCTAssertEqual(committed, "graph LR\nX-->Y")
    }

    func testAIBackendRewriteSignatureIsDrivable() async {
        let backend = EchoBackend()
        let result = await backend.rewrite(
            source: "graph TD\nA-->B",
            instruction: "left to right",
            contentIdentifier: "code.mermaid",
            onEvent: { _ in }
        )
        if case let .success(source) = result {
            XCTAssertEqual(source, "graph TD\nA-->B")
        } else {
            XCTFail("expected echoed success")
        }
    }

    func testConfigurationCarriesInteractiveProviderAndBackend() {
        let document = BlockInputDocument(blocks: [.emptyParagraph()])
        var config = BlockInputConfiguration(document: document)
        XCTAssertNil(config.interactiveDiagramProvider)
        XCTAssertNil(config.diagramAIBackend)

        config.diagramAIBackend = EchoBackend()
        config.interactiveDiagramProvider = { context in StubInteractiveDiagramView(context: context) }
        XCTAssertNotNil(config.interactiveDiagramProvider)
        XCTAssertNotNil(config.diagramAIBackend)
    }
}

@MainActor
private final class StubInteractiveDiagramView: BlockInputInteractiveDiagramView {
    private let view = NSView()
    private var source: String
    var onCommitSource: ((String) -> Void)?
    init(context: BlockInputInteractiveDiagramContext) { self.source = context.source }
    var nsView: NSView { view }
    var currentSource: String { source }
    func tearDown() {}
    func commitForTesting(_ newSource: String) { source = newSource; onCommitSource?(newSource) }
}

private struct EchoBackend: BlockInputDiagramAIBackend {
    func rewrite(
        source: String,
        instruction: String,
        contentIdentifier: String,
        onEvent: @Sendable @MainActor (BlockInputDiagramAIEvent) -> Void
    ) async -> Result<String, Error> {
        .success(source)
    }
}
