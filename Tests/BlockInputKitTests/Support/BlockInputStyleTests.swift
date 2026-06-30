import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputStyleTests: XCTestCase {
    func testDefaultStylePreservesBuiltInSurfaceAndChipDefaults() {
        let style = BlockInputStyle.default

        XCTAssertEqual(style.editorSurface.editorBackgroundColor, .textBackgroundColor)
        XCTAssertEqual(style.editorSurface.scrollBackgroundColor, .textBackgroundColor)
        XCTAssertEqual(style.editorSurface.collectionBackgroundColor, .textBackgroundColor)
        XCTAssertNil(style.editorSurface.chrome)
        XCTAssertEqual(style.fileChip.foregroundColor, .labelColor)
        XCTAssertEqual(style.slashCommandChip.foregroundColor, .labelColor)
        XCTAssertEqual(style.rawSlashCommandChip.foregroundColor, .labelColor)
        XCTAssertEqual(style.fileChip.cornerRadius, 6)
        XCTAssertEqual(style.slashCommandChip.cornerRadius, 6)
        XCTAssertEqual(style.rawSlashCommandChip.cornerRadius, 6)
        XCTAssertNil(style.imagePreviewStrip.backgroundColor)
        XCTAssertEqual(style.imagePreviewStrip.removeButton.size, NSSize(width: 20, height: 20))
        XCTAssertEqual(style.imagePreviewStrip.removeButton.edgeInset, 5)
        XCTAssertEqual(style.imagePreviewStrip.removeButton.cornerRadius, 10)
        XCTAssertEqual(style.imagePreviewStrip.removeButton.symbolPointSize, 11)
    }

    func testStyleInitializerPreservesSurfaceAndChipOverrides() {
        let surface = BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: .systemRed,
            collectionBackgroundColor: .systemBlue
        )
        let fileChip = BlockInputInlineChipStyle(
            fillColor: nil,
            strokeColor: .systemGreen,
            foregroundColor: .systemPink,
            cornerRadius: 3
        )
        let slashChip = BlockInputInlineChipStyle(foregroundColor: .systemOrange, cornerRadius: 9)
        let rawSlashChip = BlockInputInlineChipStyle(fillColor: .systemYellow, strokeColor: nil, foregroundColor: .systemPurple)

        let style = BlockInputStyle(
            editorSurface: surface,
            fileChip: fileChip,
            slashCommandChip: slashChip,
            rawSlashCommandChip: rawSlashChip
        )

        XCTAssertNil(style.editorSurface.editorBackgroundColor)
        XCTAssertEqual(style.editorSurface.scrollBackgroundColor, .systemRed)
        XCTAssertEqual(style.editorSurface.collectionBackgroundColor, .systemBlue)
        XCTAssertNil(style.fileChip.fillColor)
        XCTAssertEqual(style.fileChip.strokeColor, .systemGreen)
        XCTAssertEqual(style.fileChip.foregroundColor, .systemPink)
        XCTAssertEqual(style.fileChip.cornerRadius, 3)
        XCTAssertEqual(style.slashCommandChip.foregroundColor, .systemOrange)
        XCTAssertEqual(style.slashCommandChip.cornerRadius, 9)
        XCTAssertEqual(style.rawSlashCommandChip.fillColor, .systemYellow)
        XCTAssertNil(style.rawSlashCommandChip.strokeColor)
        XCTAssertEqual(style.rawSlashCommandChip.foregroundColor, .systemPurple)
    }

    func testInlineChipCornerRadiusClampsToZero() {
        let chip = BlockInputInlineChipStyle(cornerRadius: -8)

        XCTAssertEqual(chip.cornerRadius, 0)
    }

    func testImagePreviewStripStylePreservesBackgroundOverride() {
        let style = BlockInputImagePreviewStripStyle(backgroundColor: .systemPink)

        XCTAssertEqual(style.backgroundColor, .systemPink)
    }

    func testEditorChromeStyleClampsNegativeValues() {
        let chrome = BlockInputEditorChromeStyle(borderWidth: -1, cornerRadius: -8)

        XCTAssertEqual(chrome.borderWidth, 0)
        XCTAssertEqual(chrome.cornerRadius, 0)
    }
}
