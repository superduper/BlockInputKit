import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputBlockItemStyleTests: XCTestCase {
    func testCodeBlockUsesCustomStyleOverrides() throws {
        let codeFont = NSFont.monospacedSystemFont(ofSize: 19, weight: .semibold)
        let codeBackgroundColor = NSColor(srgbRed: 0.90, green: 0.78, blue: 0.22, alpha: 1)
        let style = BlockInputStyle(
            baseText: BlockInputTextStyle(foregroundColor: .systemGreen),
            codeBlock: BlockInputCodeBlockStyle(
                font: codeFont,
                foregroundColor: .systemRed,
                backgroundColor: codeBackgroundColor,
                cornerRadius: 11
            )
        )
        let block = BlockInputBlock(id: "code", kind: .code(language: nil), text: "let value = 1")
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            style: style,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 60)
        item.view.layoutSubtreeIfNeeded()
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let codeSurface = item.testingCodeBackgroundView

        XCTAssertEqual(try XCTUnwrap(item.testingTextView?.font).pointSize, codeFont.pointSize)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemRed)
        XCTAssertEqual(codeSurface.layer?.cornerRadius, 11)
        XCTAssertEqual(NSColor(cgColor: try XCTUnwrap(codeSurface.layer?.backgroundColor)), codeBackgroundColor)
        XCTAssertEqual(
            codeSurface.frame.width,
            BlockInputBlockItem.codeSurfaceWidth(
                for: block.text,
                font: codeFont,
                availableWidth: Self.codeSurfaceAvailableWidth(in: item, allowsReordering: true)
            ),
            accuracy: 0.5
        )
    }

    func testCodeBlockForegroundColorOverridesSyntaxTokenColors() throws {
        let style = BlockInputStyle(codeBlock: BlockInputCodeBlockStyle(foregroundColor: .systemRed))
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1"),
            allowsReordering: true,
            style: style,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemRed)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor, .systemRed)
    }

    func testInlineCodeHeightUsesCustomFontSize() {
        let block = BlockInputBlock(id: "paragraph", text: "Use `git` now")
        let baseStyle = BlockInputStyle(baseText: BlockInputTextStyle(font: .systemFont(ofSize: 12)))
        let inlineStyle = BlockInputStyle(
            baseText: BlockInputTextStyle(font: .systemFont(ofSize: 12)),
            inlineCode: BlockInputInlineCodeStyle(font: .monospacedSystemFont(ofSize: 30, weight: .regular))
        )

        XCTAssertGreaterThan(
            BlockInputBlockItem.height(for: block, textWidth: 320, style: inlineStyle),
            BlockInputBlockItem.height(for: block, textWidth: 320, style: baseStyle)
        )
    }

    private static func codeSurfaceAvailableWidth(in item: BlockInputBlockItem, allowsReordering: Bool) -> CGFloat {
        let minX = BlockInputBlockItem.codeBackgroundLeadingInset(allowsReordering: allowsReordering)
        let trailingInset = BlockInputBlockItem.codeBackgroundTrailingInset(allowsReordering: allowsReordering)
        return max(0, item.view.bounds.maxX - trailingInset - minX)
    }
}
