import BlockInputKit
import XCTest
@testable import BlockInputKitDemoKit

/// Coverage for the DemoKit-side seam: the protocol and its no-op `NullDemoEditorExtension`.
/// The bundled (plugin) conformer is covered in `BundledDemoEditorExtensionTests` against the executable target.
@MainActor
final class DemoEditorExtensionTests: XCTestCase {
    func testNullExtensionMakesNoCompletionProvider() {
        let ext: DemoEditorExtension = NullDemoEditorExtension()
        let file = DemoFileCompletionProvider()
        XCTAssertNil(ext.makeCompletionProvider(fileProvider: file))
    }

    func testNullExtensionStylePassesThrough() {
        let ext: DemoEditorExtension = NullDemoEditorExtension()
        let base = BlockInputStyle.default
        XCTAssertNotNil(ext.scaledStyle(base))
    }
}
