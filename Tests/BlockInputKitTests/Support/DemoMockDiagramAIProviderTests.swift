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
}

private extension Result where Success == String {
    var successValue: String? {
        if case .success(let value) = self { return value }
        return nil
    }
}
