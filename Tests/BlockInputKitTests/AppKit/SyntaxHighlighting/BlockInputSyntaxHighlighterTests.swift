import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputSyntaxHighlighterTests: XCTestCase {
    func testHighlightsEverySupportedLanguageFixture() {
        for fixture in languageFixtures {
            let highlighted = BlockInputSyntaxHighlighter.highlighted(
                fixture.source,
                language: fixture.language,
                colorScheme: .light,
                font: .monospacedSystemFont(ofSize: 13, weight: .regular)
            )

            XCTAssertGreaterThan(
                runCount(in: highlighted),
                1,
                "Expected \(fixture.language) to produce highlighted runs."
            )
        }
    }

    func testUnknownLanguageFallsBackToPlainCode() {
        let highlighted = BlockInputSyntaxHighlighter.highlighted(
            "plain text with 123",
            language: "made-up-language",
            colorScheme: .light
        )

        XCTAssertEqual(highlighted.string, "plain text with 123")
        XCTAssertEqual(runCount(in: highlighted), 1)
    }

    func testPublicFacadeHighlightsMermaidSource() {
        let highlighted = BlockInputCodeHighlighting.highlighted(
            "graph TD\n  A[Start] --> B{Choice}\n  %% comment",
            language: "mermaid",
            appearance: NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing(),
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )

        XCTAssertGreaterThan(runCount(in: highlighted), 1, "the public facade should apply mermaid highlighting")
    }

    func testPublicFacadeUnknownLanguageStaysPlain() {
        let highlighted = BlockInputCodeHighlighting.highlighted(
            "just text",
            language: "made-up",
            appearance: NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        )

        XCTAssertEqual(highlighted.string, "just text")
    }

    func testNormalizesCommonAliases() {
        XCTAssertEqual(BlockInputSyntaxHighlighter.normalizedLanguage("js"), "javascript")
        XCTAssertEqual(BlockInputSyntaxHighlighter.normalizedLanguage("ts"), "typescript")
        XCTAssertEqual(BlockInputSyntaxHighlighter.normalizedLanguage("sh"), "bash")
        XCTAssertEqual(BlockInputSyntaxHighlighter.normalizedLanguage("yml"), "yaml")
        XCTAssertEqual(BlockInputSyntaxHighlighter.normalizedLanguage("md"), "markdown")
        XCTAssertEqual(BlockInputSyntaxHighlighter.normalizedLanguage("mm"), "objectivec")
        XCTAssertEqual(BlockInputSyntaxHighlighter.normalizedLanguage("objective-c"), "objectivec")
        XCTAssertEqual(BlockInputSyntaxHighlighter.normalizedLanguage("c++"), "cpp")
        XCTAssertEqual(BlockInputSyntaxHighlighter.normalizedLanguage("htm"), "html")
        XCTAssertEqual(BlockInputSyntaxHighlighter.normalizedLanguage("plist"), "xml")
    }

    func testTokenColoringDistinguishesKeywordFromBaseText() throws {
        let highlighted = BlockInputSyntaxHighlighter.highlighted(
            "let value = 42",
            language: "swift",
            colorScheme: .light
        )

        let keywordColor = try XCTUnwrap(color(at: 0, in: highlighted))
        let baseColor = try XCTUnwrap(color(at: 4, in: highlighted))
        XCTAssertNotEqual(keywordColor, baseColor)
    }

    func testSmartQuotedSwiftStringKeepsStringColor() throws {
        let source = "println(\u{201C}test\u{201D})"
        let highlighted = BlockInputSyntaxHighlighter.highlighted(
            source,
            language: "swift",
            colorScheme: .light
        )

        let stringColor = try XCTUnwrap(color(at: ("println(" as NSString).length, in: highlighted))
        let baseColor = try XCTUnwrap(color(at: 0, in: highlighted))
        XCTAssertNotEqual(stringColor, baseColor)
    }

    func testLargeInputFallsBackToPlainCode() {
        let source = String(repeating: "let value = 42\n", count: 20_000)
        XCTAssertGreaterThan((source as NSString).length, BlockInputSyntaxHighlighter.maximumHighlightedUTF16Length)

        let highlighted = BlockInputSyntaxHighlighter.highlighted(
            source,
            language: "swift",
            colorScheme: .light
        )

        XCTAssertEqual(highlighted.string, source)
        XCTAssertEqual(runCount(in: highlighted), 1)
    }

    func testPreservesLineNumberPrefixesInsideMarkdownFence() throws {
        let highlighted = BlockInputSyntaxHighlighter.highlighted(
            "12\t```bash\n13\tpython3 ai-rules/watermark.py\n14\t```\n15\t",
            language: "markdown",
            colorScheme: .dark,
            preserveLineNumberPrefixes: true
        )

        let lineNumberRun = try XCTUnwrap(runText(containing: "13\t", in: highlighted))
        XCTAssertEqual(lineNumberRun, "13\t")
        XCTAssertEqual(runText(containing: "python3", in: highlighted), "python3 ai-rules/watermark.py\n")
    }

    private func runCount(in attributed: NSAttributedString) -> Int {
        var count = 0
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { _, _, _ in
            count += 1
        }
        return count
    }

    private func color(at location: Int, in attributed: NSAttributedString) -> NSColor? {
        attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    private func runText(containing needle: String, in attributed: NSAttributedString) -> String? {
        var result: String?
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { _, range, stop in
            let text = (attributed.string as NSString).substring(with: range)
            if text.contains(needle) {
                result = text
                stop.pointee = true
            }
        }
        return result
    }
}

private struct SyntaxFixture {
    let language: String
    let source: String
}

private let languageFixtures: [SyntaxFixture] = [
    .init(language: "swift", source: #"let value = "hello" // comment"#),
    .init(language: "python", source: #"def run(): return "hello" 42 # comment"#),
    .init(language: "javascript", source: #"const value = "hello"; // comment"#),
    .init(language: "typescript", source: #"interface User { name: string }"#),
    .init(language: "json", source: #"{"enabled": true, "count": 2}"#),
    .init(language: "bash", source: #"if [ "$value" = 1 ]; then echo "$HOME"; fi"#),
    .init(language: "ruby", source: #"def run; puts "hello"; end # comment"#),
    .init(language: "go", source: #"func main() { var count = 2 } // comment"#),
    .init(language: "rust", source: #"fn main() { let value = "hello"; } // comment"#),
    .init(language: "kotlin", source: #"fun main() { val value = "hello" }"#),
    .init(language: "java", source: #"class Main { public static void main(String[] args) {} }"#),
    .init(language: "yaml", source: #"enabled: true # comment"#),
    .init(language: "c", source: #"#include <stdio.h>\nint main(void) { return 0; }"#),
    .init(language: "cpp", source: #"template <typename T> class Box { public: T value; }"#),
    .init(language: "objectivec", source: #"@interface App : NSObject\n@property(nonatomic) BOOL enabled;\n@end"#),
    .init(language: "html", source: #"<section class="hero">Hello</section>"#),
    .init(language: "css", source: #".hero { color: #ffcc00; margin: 12px !important; }"#),
    .init(language: "xml", source: #"<?xml version="1.0"?><root enabled="true" />"#),
    .init(language: "sql", source: #"SELECT count(*) FROM users WHERE enabled = true;"#),
    .init(language: "toml", source: #"[tool]\nenabled = true\ncount = 2"#),
    .init(language: "markdown", source: #"# Title\n\n- [link](https://example.com)\n\n`code`"#),
    .init(language: "mermaid", source: "graph TD\n  A[Start] --> B{Choice}\n  %% comment")
]
