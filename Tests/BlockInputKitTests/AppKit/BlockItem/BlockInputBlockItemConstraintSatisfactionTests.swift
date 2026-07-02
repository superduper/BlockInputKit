import AppKit
import Synchronization
import XCTest
@testable import BlockInputKit

/// Watchdog for silent Auto Layout breakage in block item rows.
///
/// Permanently-installed hidden chrome (like the rendered-content failure surface) pinned at required
/// priority once made every row shorter than the chrome's internal minimum unsatisfiable; AppKit only
/// NSLogged "Unable to simultaneously satisfy constraints" and broke a random constraint per row.
/// Laying out each representative kind at its own measured height turns that stderr spew into a named,
/// deterministic failure instead of an incidental geometry mismatch elsewhere.
final class BlockInputConstraintSatisfactionTests: XCTestCase {
    @MainActor
    func testRepresentativeKindsAtMeasuredHeightReportNoUnsatisfiableConstraints() throws {
        let view = BlockInputView()
        for block in Self.representativeBlocks() {
            let rowSize = NSSize(width: 420, height: BlockInputBlockItem.height(for: block, textWidth: 340))
            let captured = try capturedStandardError {
                let item = BlockInputBlockItem.configuredForTesting(
                    block: block,
                    allowsReordering: true,
                    delegate: view
                )
                mountForLayoutTesting(item, size: rowSize)
            }
            XCTAssertFalse(
                captured.contains(Self.unsatisfiableConstraintsMarker),
                "Auto Layout broke a constraint for \(block.kind) at measured row height \(rowSize.height):\n\(captured)"
            )
        }
    }
}

private extension BlockInputConstraintSatisfactionTests {
    static let unsatisfiableConstraintsMarker = "Unable to simultaneously satisfy constraints"

    /// Short realistic rows across every rendering family — the exact class the required-pin bug hit.
    static func representativeBlocks() -> [BlockInputBlock] {
        [
            BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain"),
            BlockInputBlock(id: "heading", kind: .heading(level: 2), text: "Heading"),
            BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1"),
            BlockInputBlock(id: "quote", kind: .quote, text: "Quoted"),
            BlockInputBlock(id: "bullet", kind: .bulletedListItem, text: "Bullet"),
            BlockInputBlock(id: "number", kind: .numberedListItem(start: 1), text: "Number"),
            BlockInputBlock(id: "checklist", kind: .checklistItem(isChecked: false), text: "Task"),
            BlockInputBlock(id: "rule", kind: .horizontalRule, text: ""),
            BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "raw", kind: .rawMarkdown, text: "| A |\n| - |"),
            BlockInputBlock(id: "table", kind: .table, text: """
            | A | B |
            | --- | --- |
            | 1 | 2 |
            """)
        ]
    }

    /// Redirects `STDERR_FILENO` into a pipe around `body` and returns everything written.
    ///
    /// AppKit NSLogs the unsatisfiable-constraint report to stderr in the test process. The pipe is
    /// drained concurrently off the main thread so a report larger than the 64KB pipe buffer cannot
    /// block the writer and deadlock the test.
    @MainActor
    func capturedStandardError(while body: () -> Void) throws -> String {
        let pipe = Pipe()
        let buffer = Mutex(Data())
        let drained = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                drained.signal()
            } else {
                buffer.withLock { $0.append(chunk) }
            }
        }

        fflush(stderr)
        let savedStandardError = dup(STDERR_FILENO)
        guard savedStandardError >= 0 else {
            throw StandardErrorCaptureError.redirectFailed
        }
        guard dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO) >= 0 else {
            close(savedStandardError)
            throw StandardErrorCaptureError.redirectFailed
        }
        body()
        fflush(stderr)
        dup2(savedStandardError, STDERR_FILENO)
        close(savedStandardError)
        try pipe.fileHandleForWriting.close()

        guard drained.wait(timeout: .now() + 10) == .success else {
            throw StandardErrorCaptureError.drainTimedOut
        }
        return buffer.withLock { String(bytes: $0, encoding: .utf8) ?? "" }
    }
}

private enum StandardErrorCaptureError: Error {
    case redirectFailed
    case drainTimedOut
}
