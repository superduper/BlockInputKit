import AppKit
import XCTest
@testable import BlockInputKit

/// Needle-highlighting coverage for the completion popup row: titles/subtitles with match ranges render an emphasized
/// (bold + accent) attributed string over the matched span, while rows without match ranges render plainly.
@MainActor
final class BlockInputCompletionPopupRowNeedleTests: XCTestCase {
    private func configuredPopup(suggestions: [BlockInputCompletionSuggestion]) -> BlockInputCompletionPopupView {
        let popup = BlockInputCompletionPopupView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        popup.configure(
            state: BlockInputCompletionPopupState(suggestions: suggestions, highlightedIndex: 0, isLoading: false),
            style: .default,
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        popup.layoutSubtreeIfNeeded()
        return popup
    }

    private func row(label: String, in popup: NSView) throws -> NSView {
        try XCTUnwrap(popup.subviews.first { $0.accessibilityLabel()?.contains(label) == true })
    }

    private func textField(plainText: String, in row: NSView) throws -> NSTextField {
        try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == plainText })
    }

    private func hasEmphasis(_ field: NSTextField, over range: NSRange) -> Bool {
        let attributed = field.attributedStringValue
        guard attributed.length >= NSMaxRange(range), range.length > 0 else {
            return false
        }
        var emphasized = true
        attributed.enumerateAttributes(in: range, options: []) { attributes, _, _ in
            let isBold = (attributes[.font] as? NSFont)
                .map { $0.fontDescriptor.symbolicTraits.contains(.bold) } ?? false
            let isAccent = (attributes[.foregroundColor] as? NSColor) == .controlAccentColor
            if !(isBold || isAccent) {
                emphasized = false
            }
        }
        return emphasized
    }

    func testTitleNeedleRendersEmphasizedOverMatchRange() throws {
        let suggestion = BlockInputCompletionSuggestion(
            id: "1",
            title: "Foobar",
            subtitle: nil,
            insertionText: "[[foobar]]",
            trigger: .custom("wikilink"),
            titleMatchRanges: [NSRange(location: 0, length: 3)]
        )
        let popup = configuredPopup(suggestions: [suggestion])
        let rowView = try row(label: "Foobar", in: popup)
        let titleField = try textField(plainText: "Foobar", in: rowView)

        XCTAssertTrue(hasEmphasis(titleField, over: NSRange(location: 0, length: 3)))
    }

    func testSubtitleNeedleRendersEmphasizedOverMatchRange() throws {
        let suggestion = BlockInputCompletionSuggestion(
            id: "1",
            title: "Unrelated",
            subtitle: "baz/foo",
            insertionText: "[[baz/foo|Unrelated]]",
            trigger: .custom("wikilink"),
            subtitleMatchRanges: [NSRange(location: 0, length: 3)]
        )
        let popup = configuredPopup(suggestions: [suggestion])
        let rowView = try row(label: "Unrelated", in: popup)
        let subtitleField = try textField(plainText: "baz/foo", in: rowView)

        XCTAssertTrue(hasEmphasis(subtitleField, over: NSRange(location: 0, length: 3)))
    }

    func testTitleWithoutMatchRangesRendersPlainly() throws {
        let suggestion = BlockInputCompletionSuggestion(
            id: "1",
            title: "Foobar",
            subtitle: nil,
            insertionText: "[[foobar]]",
            trigger: .custom("wikilink")
        )
        let popup = configuredPopup(suggestions: [suggestion])
        let rowView = try row(label: "Foobar", in: popup)
        let titleField = try textField(plainText: "Foobar", in: rowView)

        // No accent emphasis applied anywhere when no match ranges are present.
        let attributed = titleField.attributedStringValue
        var sawAccent = false
        attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length), options: []) { value, _, _ in
            if (value as? NSColor) == .controlAccentColor { sawAccent = true }
        }
        XCTAssertFalse(sawAccent)
    }
}
