import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCodeBlockRenderingTests: XCTestCase {
    func testCodeBlockAppliesSyntaxHighlightingAndSkipsBraceMarker() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 42"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let markerView = try XCTUnwrap(item.testingMarkerView)

        let keywordColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let baseColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor)
        XCTAssertNotEqual(keywordColor, baseColor)
        XCTAssertEqual(markerView.markerLines, [])
    }

    func testCodeBlockSurfaceIsClearedOnReuse() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 42"),
            allowsReordering: true,
            delegate: view
        )

        item.configure(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain"),
            allowsReordering: true,
            delegate: view
        )

        XCTAssertTrue(item.testingCodeBackgroundView.isHidden)
        XCTAssertEqual(item.testingCodeBackgroundView.alphaValue, 0)
    }

    func testCodeBlockSelectionChromeStaysAboveCodeSurface() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 42"),
            allowsReordering: true,
            isSelected: true,
            delegate: BlockInputView()
        )

        let codeSurfaceIndex = try XCTUnwrap(item.view.subviews.firstIndex(of: item.testingCodeBackgroundView))
        let selectionIndex = try XCTUnwrap(item.view.subviews.firstIndex(of: item.testingSelectionBackgroundView))
        XCTAssertLessThan(codeSurfaceIndex, selectionIndex)
    }

    func testCodeBlockAppearanceRefreshesSurfaceAndTokenColors() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 42"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 60)
        item.view.appearance = NSAppearance(named: .aqua)
        item.view.layoutSubtreeIfNeeded()
        let lightBackground = item.testingCodeBackgroundView.layer?.backgroundColor
        let lightKeywordColor = try XCTUnwrap(
            item.testingTextView?.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )

        item.view.appearance = NSAppearance(named: .darkAqua)
        item.view.layoutSubtreeIfNeeded()
        let darkBackground = item.testingCodeBackgroundView.layer?.backgroundColor
        let darkKeywordColor = try XCTUnwrap(
            item.testingTextView?.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )

        XCTAssertNotEqual(lightBackground, darkBackground)
        XCTAssertNotEqual(lightKeywordColor, darkKeywordColor)
    }
}
