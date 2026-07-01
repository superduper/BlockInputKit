import AppKit
import XCTest
@testable import BlockInputKit

/// Regression: a wrapping paragraph containing links must get a row height that FITS what the live
/// text view lays out. The live render reserves per-link open-icon kern (`showsInlineLinkOpenButton`);
/// if measurement omits it, the row is one line too short at wrap-boundary widths and the last line
/// clips. Reproduced at ~860px (user saw 845 good / 874 clipped). Anchor + scheme links alike.
@MainActor
final class BlockInputLinkParagraphHeightTests: XCTestCase {
    private let anchorText = """
    Clicking a [#slug](#heading-anchors) link scrolls to the matching heading — no host wiring needed. \
    Try [jump to Diagrams](#diagrams) or [jump to Tables](#tables) to see it in action.
    """
    private let schemeText = """
    Clicking a [#slug](https://x.com/aaaa) link scrolls to the matching heading — no host wiring needed. \
    Try [jump to Diagrams](https://x.com/bbbb) or [jump to Tables](https://x.com/cccc) to see it in action.
    """

    /// Mounts a paragraph at a window width, returns (allotted row height, actual laid-out content height).
    private func mount(_ text: String, windowWidth: CGFloat) -> (allotted: CGFloat, actual: CGFloat) {
        var config = BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(kind: .paragraph, text: text)
        ]))
        config.headingAnchorsEnabled = true
        config.showsInlineLinkOpenButton = true
        let (view, _) = makeMountedBlockInputView(configuration: config, size: NSSize(width: windowWidth, height: 700))
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        guard let item = view.visibleBlockItemForTesting(at: 0) else { return (0, 0) }
        let allotted = item.view.frame.height
        var actual: CGFloat = 0
        let textView = item.textView
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
            actual = layoutManager.usedRect(for: container).height
        }
        return (allotted, actual)
    }

    func testLinkParagraphRowFitsContentAcrossWrapWidths() {
        // Sweep the wrap-boundary band. At every width the allotted row must be >= the content height.
        for width in stride(from: 820.0, through: 900.0, by: 8.0) {
            let anchor = mount(anchorText, windowWidth: width)
            XCTAssertGreaterThanOrEqual(anchor.allotted, anchor.actual,
                "anchor-link row clipped at width \(width): allotted \(anchor.allotted) < content \(anchor.actual)")
            let scheme = mount(schemeText, windowWidth: width)
            XCTAssertGreaterThanOrEqual(scheme.allotted, scheme.actual,
                "scheme-link row clipped at width \(width): allotted \(scheme.allotted) < content \(scheme.actual)")
        }
    }
}
