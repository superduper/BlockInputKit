import BlockInputKit
import XCTest
@testable import BlockInputKitDemoKit

/// Coverage for the demo's scripted AI backend `DemoMockDiagramAIProvider`, which conforms to
/// `BlockInputInteractiveBlockContent.AIBackend` (the pure-model `rewrite` — NO host `validate` arg; the plugin renders and
/// validates candidates in-page). Re-adds the backend coverage lost when the legacy panel editor was
/// deleted. Asserts via the streamed `onEvent` events plus the returned `Result<String, Error>`.
@MainActor
final class DemoMockDiagramAIProviderTests: XCTestCase {
    func testDirectionSwapToLeftRight() async throws {
        let provider = DemoMockDiagramAIProvider()
        var events: [BlockInputInteractiveBlockContent.AIEvent] = []
        let result = await provider.rewrite(
            source: "graph TD\n    A --> B",
            instruction: "make it left to right",
            contentIdentifier: "code.mermaid",
            onEvent: { events.append($0) }
        )

        let newSource = try XCTUnwrap(result.successValue, "direction swap returns a candidate")
        XCTAssertTrue(newSource.contains("graph LR"), "first keyword line switches to LR; got: \(newSource)")
        XCTAssertFalse(newSource.contains("graph TD"), "the TD direction is replaced")
        // Streamed at least one progress event (status/assistant) before returning.
        XCTAssertFalse(events.isEmpty, "the backend streams progress via onEvent")
    }

    func testCannedFixPathReturnsCandidate() async throws {
        let provider = DemoMockDiagramAIProvider()
        var sawCandidate = false
        let result = await provider.rewrite(
            source: "graph TD\n    A -->",
            instruction: "fix the syntax error: Parse error on line 2",
            contentIdentifier: "code.mermaid",
            onEvent: { event in
                if case .candidate = event { sawCandidate = true }
            }
        )

        let fixed = try XCTUnwrap(result.successValue, "the fix path returns a repair candidate")
        XCTAssertFalse(fixed.isEmpty, "the candidate is non-empty")
        // The dangling-edge repair completes "A -->" with a target rather than leaving it broken.
        XCTAssertNotEqual(fixed, "graph TD\n    A -->", "the candidate differs from the broken source")
        XCTAssertTrue(sawCandidate, "the fix path streams a .candidate event")
    }

    // MARK: - converse tests

    private func runConverse(_ prompts: [String], source: String = "") async
    -> Result<BlockInputInteractiveBlockContent.AITurn, Error> {
        let backend = DemoMockDiagramAIProvider(stepDelay: .zero)
        let messages = prompts.map { BlockInputInteractiveBlockContent.AIMessage(role: .user, text: $0) }
        return await backend.converse(contentIdentifier: "code.mermaid",
                                      blockID: BlockInputBlockID(rawValue: "b"),
                                      source: source, messages: messages, onEvent: { _ in })
    }

    func testVaguePromptAsksQuestion() async {
        guard case let .success(.question(question)) = await runConverse(["make a diagram"]) else {
            return XCTFail("expected a clarifying question")
        }
        XCTAssertFalse(question.isEmpty)
    }

    func testSpecificPromptReturnsCandidate() async {
        guard case let .success(.candidate(src)) = await runConverse(["sequence diagram of login"]) else {
            return XCTFail("expected a candidate")
        }
        XCTAssertTrue(src.contains("sequenceDiagram") || src.contains("->>"), "a sequence diagram")
    }

    func testRefinementReturnsCandidate() async {
        let src = "graph TD\nA-->B"
        guard case let .success(.candidate(out)) = await runConverse(["left to right"], source: src) else {
            return XCTFail("expected a refined candidate")
        }
        XCTAssertTrue(out.contains("LR"), "direction switched to LR")
    }

    // MARK: - Engine-appropriate syntax (converse must honor contentIdentifier)

    private func candidate(_ prompt: String, contentIdentifier: String, source: String = "") async -> String? {
        let provider = DemoMockDiagramAIProvider(stepDelay: .zero)
        let messages = [BlockInputInteractiveBlockContent.AIMessage(role: .user, text: prompt)]
        let result = await provider.converse(contentIdentifier: contentIdentifier,
                                              blockID: BlockInputBlockID(rawValue: "b"),
                                              source: source, messages: messages, onEvent: { _ in })
        if case .success(.candidate(let src)) = result { return src }
        return nil
    }

    func testPlantUMLBlockGetsPlantUMLSyntaxNotMermaid() async {
        let seq = await candidate("sequence diagram of login", contentIdentifier: "code.plantuml")
        XCTAssertNotNil(seq)
        XCTAssertTrue(seq?.contains("@startuml") == true, "PlantUML candidate must be @startuml, not Mermaid")
        XCTAssertFalse(seq?.contains("sequenceDiagram") == true, "must NOT emit Mermaid on a plantuml block")

        let flow = await candidate("a flowchart", contentIdentifier: "code.puml")
        XCTAssertTrue(flow?.contains("@startuml") == true)
        XCTAssertFalse(flow?.contains("graph TD") == true, "must NOT emit Mermaid 'graph TD' on a puml block")
    }

    func testMermaidBlockStillGetsMermaidSyntax() async {
        let seq = await candidate("sequence diagram of login", contentIdentifier: "code.mermaid")
        XCTAssertTrue(seq?.contains("sequenceDiagram") == true)
        XCTAssertFalse(seq?.contains("@startuml") == true)
    }
}

private extension Result where Success == String {
    var successValue: String? {
        if case .success(let value) = self { return value }
        return nil
    }
}
