import Foundation

/// Stable identifier for a block in a document.
public struct BlockInputBlockID: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    /// Host-storable identifier value.
    public var rawValue: String

    /// Creates a block identifier from a host-storable raw value.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a block identifier from a string literal.
    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// Creates a random UUID-backed block identifier.
    public static func unique() -> Self {
        Self(rawValue: UUID().uuidString)
    }
}

/// Supported document block types.
public enum BlockInputBlockKind: Equatable, Codable, Sendable {
    /// Plain text with no block-level formatting.
    case paragraph
    /// Markdown heading level, clamped to levels 1 through 6 when rendered.
    case heading(level: Int)
    /// Fenced code block with an optional language identifier.
    case code(language: String?)
    /// Horizontal divider exported as `---`.
    case horizontalRule
    /// Document-leading Markdown frontmatter exported with `---` delimiters.
    ///
    /// The block's `text` stores the raw YAML body without opening or closing
    /// delimiters. The required newline before the closing delimiter is recreated
    /// during Markdown export instead of being exposed as an editable blank line.
    case frontMatter
    /// Markdown quote block.
    case quote
    /// Unordered list item.
    case bulletedListItem
    /// Ordered list item with the number to display for this block.
    case numberedListItem(start: Int)
    /// Checklist item with checked state stored in the block kind.
    case checklistItem(isChecked: Bool)
    /// GFM-style pipe table stored as normalized Markdown source.
    ///
    /// Table blocks keep their full pipe-table Markdown in ``BlockInputBlock/text`` so
    /// cell source ranges can be mapped back to the underlying document text.
    case table
    /// Image block rendered from Markdown image syntax, HTML `<img>` syntax, or a local image drop.
    case image(BlockInputImage)
    /// Unsupported block-level Markdown source that should round-trip verbatim.
    ///
    /// The block's `text` stores the original Markdown source for this block.
    /// Raw Markdown blocks are editable as source text and exported unchanged.
    case rawMarkdown
}

/// Structured document unit edited by its own AppKit text input.
public struct BlockInputBlock: Equatable, Codable, Sendable, Identifiable {
    /// Stable block identity used for focus, selection, undo, and reordering.
    public var id: BlockInputBlockID
    /// Semantic rendering and Markdown export kind.
    public var kind: BlockInputBlockKind {
        didSet {
            normalizeForKind()
        }
    }
    /// Text content owned by editable block kinds.
    ///
    /// For ``BlockInputBlockKind/table``, this stores normalized pipe-table Markdown source.
    /// For ``BlockInputBlockKind/rawMarkdown``, this stores the original Markdown source.
    /// For ``BlockInputBlockKind/frontMatter``, this stores the delimiter-free raw YAML body
    /// without the required closing-delimiter separator line break.
    /// Non-text blocks such as horizontal rules and images normalize this value to an empty string.
    public var text: String {
        didSet {
            normalizeForKind()
        }
    }
    /// Nesting level used by list-like blocks.
    public var indentationLevel: Int {
        didSet {
            normalizeForKind()
        }
    }
    /// Per-line nesting overrides for list-like blocks.
    ///
    /// An empty array means every line uses `indentationLevel`. The array is
    /// populated only when lines inside one block need different nesting levels.
    public var lineIndentationLevels: [Int] {
        didSet {
            normalizeForKind()
        }
    }

    /// Creates a normalized block with stable identity, kind, text, and indentation metadata.
    public init(
        id: BlockInputBlockID = .unique(),
        kind: BlockInputBlockKind = .paragraph,
        text: String = "",
        indentationLevel: Int = 0,
        lineIndentationLevels: [Int] = []
    ) {
        self.id = id
        self.kind = kind
        self.text = kind.normalizesTextToEmpty ? "" : text
        self.indentationLevel = indentationLevel
        self.lineIndentationLevels = lineIndentationLevels
        normalizeForKind()
    }

    /// Decodes and normalizes a stored block.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(BlockInputBlockID.self, forKey: .id)
        kind = try container.decode(BlockInputBlockKind.self, forKey: .kind)
        let decodedText = try container.decode(String.self, forKey: .text)
        text = kind.normalizesTextToEmpty ? "" : decodedText
        indentationLevel = try container.decode(Int.self, forKey: .indentationLevel)
        lineIndentationLevels = try container.decodeIfPresent(
            [Int].self,
            forKey: .lineIndentationLevels
        ) ?? []
        normalizeForKind()
    }

    /// Returns true when the block has no meaningful user-visible content.
    public var isEmpty: Bool {
        if kind == .horizontalRule {
            return false
        }
        if kind == .table {
            return false
        }
        if case .image = kind {
            return false
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Text length in UTF-16 units for AppKit selection interoperability.
    public var utf16Length: Int {
        (text as NSString).length
    }

    /// Logical caret length for selection and focus.
    ///
    /// Image blocks have no editable text, but the editor exposes two caret
    /// positions around the rendered image: `0` before it and `1` after it.
    public var cursorUTF16Length: Int {
        if case .image = kind {
            return 1
        }
        return utf16Length
    }

    private mutating func normalizeForKind() {
        if kind.normalizesTextToEmpty, !text.isEmpty {
            text = ""
        }
        let normalizedIndentation = kind.supportsIndentation ? max(0, indentationLevel) : 0
        if indentationLevel != normalizedIndentation {
            indentationLevel = normalizedIndentation
        }
        let normalizedLineIndentations = normalizedLineIndentationLevels()
        if lineIndentationLevels != normalizedLineIndentations {
            lineIndentationLevels = normalizedLineIndentations
        }
    }

    private func normalizedLineIndentationLevels() -> [Int] {
        guard kind.supportsIndentation else {
            return []
        }
        guard !lineIndentationLevels.isEmpty else {
            return []
        }
        let lineCount = BlockInputLineBreaks.lineCount(in: text)
        let normalized = (0..<lineCount).map { lineIndex in
            let level = lineIndentationLevels.indices.contains(lineIndex)
                ? lineIndentationLevels[lineIndex]
                : indentationLevel
            return max(0, level)
        }
        return normalized.allSatisfy { $0 == indentationLevel } ? [] : normalized
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case text
        case indentationLevel
        case lineIndentationLevels
    }
}

extension BlockInputBlock {
    func indentationLevel(forLine lineIndex: Int) -> Int {
        guard kind.supportsIndentation else {
            return 0
        }
        guard lineIndentationLevels.indices.contains(lineIndex) else {
            return indentationLevel
        }
        return lineIndentationLevels[lineIndex]
    }

    func lineIndex(containingUTF16Offset offset: Int) -> Int {
        let textStorage = text as NSString
        let clampedOffset = min(max(offset, 0), textStorage.length)
        guard clampedOffset > 0 else {
            return 0
        }
        var lineIndex = 0
        var utf16Index = 0
        while utf16Index < clampedOffset {
            let character = textStorage.character(at: utf16Index)
            if character.isCarriageReturn,
               utf16Index + 1 < clampedOffset,
               textStorage.character(at: utf16Index + 1).isLineFeed {
                lineIndex += 1
                utf16Index += 2
                continue
            }
            if character.isLineEnding {
                lineIndex += 1
            }
            utf16Index += 1
        }
        return lineIndex
    }

    mutating func setIndentationLevel(_ indentationLevel: Int, forLine lineIndex: Int) {
        guard kind.supportsIndentation else {
            return
        }
        let lineCount = BlockInputLineBreaks.lineCount(in: text)
        guard (0..<lineCount).contains(lineIndex) else {
            return
        }
        var levels = lineIndentationLevels.isEmpty
            ? Array(repeating: self.indentationLevel, count: lineCount)
            : lineIndentationLevels
        if levels.count < lineCount {
            levels += Array(repeating: self.indentationLevel, count: lineCount - levels.count)
        } else if levels.count > lineCount {
            levels = Array(levels.prefix(lineCount))
        }
        levels[lineIndex] = max(0, indentationLevel)
        lineIndentationLevels = levels
    }

    func lineIndentationLevelsAfterReplacingTextWithLineEnding(
        utf16Offset: Int,
        selectedUTF16Length: Int,
        updatedText: String
    ) -> [Int]? {
        let textStorage = text as NSString
        let offset = min(max(utf16Offset, 0), textStorage.length)
        let replacementLength = min(max(selectedUTF16Length, 0), textStorage.length - offset)
        let updatedTextStorage = updatedText as NSString
        guard updatedTextStorage.length == textStorage.length - replacementLength + 1,
              offset < updatedTextStorage.length,
              updatedTextStorage.character(at: offset).isLineEnding else {
            return nil
        }
        return lineIndentationLevelsAfterReplacingText(
            utf16Offset: utf16Offset,
            selectedUTF16Length: selectedUTF16Length,
            updatedText: updatedText
        )
    }

    func lineIndentationLevelsAfterReplacingText(
        utf16Offset: Int,
        selectedUTF16Length: Int,
        updatedText: String
    ) -> [Int]? {
        guard kind.supportsIndentation else {
            return nil
        }
        let textStorage = text as NSString
        let offset = min(max(utf16Offset, 0), textStorage.length)
        let replacementLength = min(max(selectedUTF16Length, 0), textStorage.length - offset)
        let updatedTextStorage = updatedText as NSString
        let insertedLength = updatedTextStorage.length - textStorage.length + replacementLength
        guard insertedLength >= 0,
              updatedTextStorage.length == textStorage.length - replacementLength + insertedLength else {
            return nil
        }
        let removedRange = NSRange(location: offset, length: replacementLength)
        let insertedRange = NSRange(location: offset, length: insertedLength)
        guard Self.rangeContainsLineEnding(removedRange, in: textStorage) ||
              Self.rangeContainsLineEnding(insertedRange, in: updatedTextStorage) else {
            return nil
        }
        let insertedUpperBound = offset + insertedLength
        let sourceInsertionLineIndex = lineIndex(containingUTF16Offset: offset)
        if updatedTextStorage.length == 0 {
            return [indentationLevel(forLine: sourceInsertionLineIndex)]
        }
        // Map each resulting line start back to the source line that supplied
        // its indentation; inserted lines inherit the edited line.
        return BlockInputLineBreaks.lineStartOffsets(in: updatedText).map { updatedLineStart in
            if updatedLineStart < offset {
                return indentationLevel(forLine: lineIndex(containingUTF16Offset: updatedLineStart))
            }
            if insertedLength > 0, updatedLineStart < insertedUpperBound {
                return indentationLevel(forLine: sourceInsertionLineIndex)
            }
            let sourceLineStart = updatedLineStart - insertedLength + replacementLength
            return indentationLevel(forLine: lineIndex(containingUTF16Offset: sourceLineStart))
        }
    }

    private static func rangeContainsLineEnding(_ range: NSRange, in text: NSString) -> Bool {
        let lowerBound = min(max(range.location, 0), text.length)
        let upperBound = min(max(NSMaxRange(range), lowerBound), text.length)
        guard lowerBound < upperBound else {
            return false
        }
        for index in lowerBound..<upperBound where text.character(at: index).isLineEnding {
            return true
        }
        return false
    }

    func requiresStructuralReturnHandling(utf16Offset: Int, selectedUTF16Length: Int) -> Bool {
        if isEmpty, kind.exitsToParagraphOnEmptyReturn {
            return true
        }
        guard kind.acceptsInlineReturn else {
            return true
        }
        guard selectedUTF16Length == 0 else {
            return false
        }
        return kind.exitsInlineBlockOnEmptyReturn && emptyInlineLineRemovalRangeForReturn(utf16Offset: utf16Offset) != nil
    }

    /// Range of trailing blank lines to drop when Return should ESCAPE an inline block.
    ///
    /// Inside a code/quote/frontMatter block, Return inserts a newline normally — including on a
    /// blank line in the middle of the block — UNTIL the block already ends in two trailing blank
    /// lines AND the caret sits at the very end. Only then does this return a non-nil range (the two
    /// trailing line endings that formed the "escape gesture"); the caller exits to a paragraph below
    /// and drops those blanks so the inline block keeps no trailing blank lines. A blank line anywhere
    /// other than two-at-the-end never escapes.
    func emptyInlineLineRemovalRangeForReturn(utf16Offset: Int) -> NSRange? {
        guard kind.exitsInlineBlockOnEmptyReturn, !isEmpty else {
            return nil
        }
        let textStorage = text as NSString
        let offset = min(max(utf16Offset, 0), textStorage.length)
        guard offset == textStorage.length else {
            return nil
        }
        return Self.trailingTwoBlankLineRange(in: textStorage)
    }

    /// Range covering the last two trailing line endings (each `\r\n` counts as one), or nil when the
    /// text does not end with at least two of them. The range starts where the second-to-last line
    /// ending begins and runs to the end of the text.
    private static func trailingTwoBlankLineRange(in textStorage: NSString) -> NSRange? {
        var cursor = textStorage.length
        for _ in 0..<2 {
            guard cursor > 0, textStorage.character(at: cursor - 1).isLineEnding else {
                return nil
            }
            if cursor >= 2,
               textStorage.character(at: cursor - 1).isLineFeed,
               textStorage.character(at: cursor - 2).isCarriageReturn {
                cursor -= 2
            } else {
                cursor -= 1
            }
        }
        return NSRange(location: cursor, length: textStorage.length - cursor)
    }
}

extension BlockInputBlockKind {
    var supportsIndentation: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }

    var canUnwrapToParagraph: Bool {
        switch self {
        case .paragraph, .code, .table, .image, .rawMarkdown:
            return false
        case .heading, .horizontalRule, .frontMatter, .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        }
    }

    var exitsToParagraphOnEmptyReturn: Bool {
        switch self {
        case .heading, .code, .frontMatter, .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .horizontalRule, .table, .image, .rawMarkdown:
            return false
        }
    }

    var acceptsInlineReturn: Bool {
        switch self {
        case .code, .frontMatter, .quote, .rawMarkdown:
            return true
        case .paragraph, .heading, .horizontalRule, .bulletedListItem, .numberedListItem, .checklistItem, .table, .image:
            return false
        }
    }

    var exitsInlineBlockOnEmptyReturn: Bool {
        switch self {
        case .code, .frontMatter, .quote:
            return true
        case .paragraph, .heading, .horizontalRule, .bulletedListItem, .numberedListItem, .checklistItem, .table, .image, .rawMarkdown:
            return false
        }
    }

    var insertsSiblingListItemOnReturn: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }

    var normalizesTextToEmpty: Bool {
        switch self {
        case .horizontalRule, .image:
            return true
        case .paragraph, .heading, .code, .frontMatter, .quote, .bulletedListItem, .numberedListItem, .checklistItem,
                .table, .rawMarkdown:
            return false
        }
    }

    var isImage: Bool {
        if case .image = self {
            return true
        }
        return false
    }

    var isSelectableStandaloneBlock: Bool {
        self == .horizontalRule || isImage
    }
}
