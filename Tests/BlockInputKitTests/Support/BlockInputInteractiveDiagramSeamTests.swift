// Tests/BlockInputKitTests/Support/BlockInputInteractiveDiagramSeamTests.swift
import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputInteractiveDiagramSeamTests: XCTestCase {
    /// A minimal conformer proves the protocol surface is usable: context carries source + validate + backend;
    /// the view exposes its NSView, current source, and a commit hook the host can read back.
    func testInteractiveViewExposesSourceAndCommitHook() {
        let context = BlockInputInteractiveBlockContent.Context(
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
        XCTAssertNil(config.interactiveBlockContentProvider)
        XCTAssertNil(config.blockContentAIBackend)

        config.blockContentAIBackend = EchoBackend()
        config.interactiveBlockContentProvider = { context in StubInteractiveDiagramView(context: context) }
        XCTAssertNotNil(config.interactiveBlockContentProvider)
        XCTAssertNotNil(config.blockContentAIBackend)
    }
}

@MainActor
private final class StubInteractiveDiagramView: BlockInputInteractiveBlockContent.View {
    private let view = NSView()
    private var source: String
    var onCommitSource: ((String) -> Void)?
    init(context: BlockInputInteractiveBlockContent.Context) { self.source = context.source }
    var nsView: NSView { view }
    var currentSource: String { source }
    func tearDown() {}
    func commitForTesting(_ newSource: String) { source = newSource; onCommitSource?(newSource) }
}

private struct EchoBackend: BlockInputInteractiveBlockContent.AIBackend {
    func rewrite(
        source: String,
        instruction: String,
        contentIdentifier: String,
        onEvent: @Sendable @MainActor (BlockInputInteractiveBlockContent.AIEvent) -> Void
    ) async -> Result<String, Error> {
        .success(source)
    }
}
