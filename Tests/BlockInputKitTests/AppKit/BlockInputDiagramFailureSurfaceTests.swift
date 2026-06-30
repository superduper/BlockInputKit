// Tests/BlockInputKitTests/AppKit/BlockInputDiagramFailureSurfaceTests.swift
import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputDiagramFailureSurfaceTests: XCTestCase {
    func testShowsConfiguredMessage() {
        let view = BlockInputDiagramFailureSurfaceView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.configure(message: "This diagram plugin could not start.")
        XCTAssertEqual(view.messageForTesting, "This diagram plugin could not start.")
    }
}
