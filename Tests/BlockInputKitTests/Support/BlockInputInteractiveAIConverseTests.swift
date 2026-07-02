import XCTest
@testable import BlockInputKit

final class BlockInputInteractiveAIConverseTests: XCTestCase {
    private struct RewriteOnlyBackend: BlockInputInteractiveBlockContent.AIBackend {
        func rewrite(source: String, instruction: String, contentIdentifier: String,
                     onEvent: @Sendable @MainActor (BlockInputInteractiveBlockContent.AIEvent) -> Void)
        async -> Result<String, Error> {
            .success("graph TD\nA-->B // \(instruction)")
        }
    }

    func testConverseDefaultAdaptsRewriteToCandidate() async {
        let backend = RewriteOnlyBackend()
        let messages = [
            BlockInputInteractiveBlockContent.AIMessage(role: .user, text: "make a flowchart")
        ]
        let result = await backend.converse(
            contentIdentifier: "code.mermaid",
            blockID: BlockInputBlockID(rawValue: "b1"),
            source: "",
            messages: messages,
            onEvent: { _ in }
        )
        guard case let .success(turn) = result, case let .candidate(src) = turn else {
            return XCTFail("expected .candidate")
        }
        XCTAssertTrue(src.contains("make a flowchart"), "latest user message becomes the rewrite instruction")
    }
}
