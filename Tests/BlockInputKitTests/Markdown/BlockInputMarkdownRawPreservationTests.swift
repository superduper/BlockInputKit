import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputMarkdownRawPreservationTests: XCTestCase {
    func testMarkdownParsesFrontMatterAsStructuredBlock() {
        let source = """
        ---
        title: Demo
        tags:
          - swift
        ---
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.frontMatter, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, "title: Demo\ntags:\n  - swift")
        XCTAssertEqual(parsed.markdown, """
        ---
        title: Demo
        tags:
          - swift
        ---

        # Heading
        """)
    }

    func testMarkdownNormalizesBlankLineAfterFrontMatterBlock() {
        let source = """
        ---
        title: Demo
        ---

        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.frontMatter, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, "title: Demo")
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesHTMLBlockAsRawMarkdown() {
        let source = """
        <section>
        <p>Raw HTML</p>
        </section>
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown])
        XCTAssertEqual(parsed.blocks[0].text, source)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesHTMLBlockWithoutConsumingFollowingSupportedBlock() {
        let source = """
        <section>
        <p>Raw HTML</p>
        </section>
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, """
        <section>
        <p>Raw HTML</p>
        </section>
        """)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesUnclosedHTMLBlockThroughBlankLineBoundary() {
        let source = """
        <section>
        Raw HTML

        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, """
        <section>
        Raw HTML

        """)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesUnclosedHTMLBlockThroughEndOfFile() {
        let source = """
        <section>
        Raw HTML
        # Not a semantic heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown])
        XCTAssertEqual(parsed.blocks[0].text, source)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesInlineHTMLCommentWithoutConsumingFollowingSupportedBlock() {
        let source = """
        <!-- Raw comment -->
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, "<!-- Raw comment -->")
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesHTMLDeclarationWithoutConsumingFollowingSupportedBlock() {
        let source = """
        <!DOCTYPE html>
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, "<!DOCTYPE html>")
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesMultilineHTMLDeclarationAsRawMarkdown() {
        let source = """
        <!DOCTYPE html
          SYSTEM "about:legacy-compat">
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, """
        <!DOCTYPE html
          SYSTEM "about:legacy-compat">
        """)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesMultilineHTMLProcessingInstructionAsRawMarkdown() {
        let source = """
        <?block-input
        mode="raw"?>
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, """
        <?block-input
        mode="raw"?>
        """)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesInlineCDATAWithoutConsumingFollowingSupportedBlock() {
        let source = """
        <![CDATA[Raw HTML-ish text]]>
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, "<![CDATA[Raw HTML-ish text]]>")
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesSelfContainedHTMLWithoutConsumingFollowingSupportedBlock() {
        let source = """
        <br>
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, "<br>")
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesScriptHTMLBlockAsRawMarkdown() {
        let source = """
        <script>
        const value = "# not a heading";
        </script>
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, """
        <script>
        const value = "# not a heading";
        </script>
        """)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesDelimitedHTMLBlockThroughBlankLines() {
        let source = """
        <script>
        const value = "# not a heading";

        # Still raw
        </script>
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, """
        <script>
        const value = "# not a heading";

        # Still raw
        </script>
        """)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownKeepsAutolinkParagraphsSemantic() {
        let parsed = BlockInputDocument(markdown: """
        <https://example.com>
        # Heading
        """)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.paragraph, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, "<https://example.com>")
    }

    func testMarkdownKeepsInlineHTMLParagraphsSemantic() {
        let parsed = BlockInputDocument(markdown: """
        <span>Inline HTML</span> text
        # Heading
        """)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.paragraph, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, "<span>Inline HTML</span> text")
    }

    func testMarkdownPreservesHyphenatedHTMLTagAsRawMarkdown() {
        let source = """
        <callout-box>
        Important
        </callout-box>
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, """
        <callout-box>
        Important
        </callout-box>
        """)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesUppercaseHTMLTagAsOneRawMarkdownBlock() {
        let source = """
        <SECTION>
        Raw HTML
        </SECTION>
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, """
        <SECTION>
        Raw HTML
        </SECTION>
        """)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesSetextHeadingAsRawMarkdown() {
        let source = """
        Heading
        =======
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown])
        XCTAssertEqual(parsed.blocks[0].text, source)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownKeepsSupportedBlocksBeforeRuleSemantic() {
        let parsed = BlockInputDocument(markdown: """
        # Heading
        ---
        - Item
        ---
        """)

        XCTAssertEqual(parsed.blocks.map(\.kind), [
            .heading(level: 1),
            .horizontalRule,
            .bulletedListItem,
            .horizontalRule
        ])
        XCTAssertEqual(parsed.blocks.map(\.text), ["Heading", "", "Item", ""])
    }

    func testMarkdownKeepsStartingHorizontalRulesSemantic() {
        let parsed = BlockInputDocument(markdown: """
        ---
        ---
        # Heading
        """)

        XCTAssertEqual(parsed.blocks.map(\.kind), [
            .frontMatter,
            .heading(level: 1)
        ])
        XCTAssertEqual(parsed.blocks.map(\.text), ["", "Heading"])
    }

    func testMarkdownKeepsConsecutiveHorizontalRulesAfterSupportedBlockSemantic() {
        let parsed = BlockInputDocument(markdown: """
        # Heading
        ---
        ---
        """)

        XCTAssertEqual(parsed.blocks.map(\.kind), [
            .heading(level: 1),
            .horizontalRule,
            .horizontalRule
        ])
        XCTAssertEqual(parsed.blocks.map(\.text), ["Heading", "", ""])
    }

    func testMarkdownPreservesMultilineSetextHeadingAsOneRawMarkdownBlock() {
        let source = """
        First heading line
        second heading line
        -------------------
        # Next
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, """
        First heading line
        second heading line
        -------------------
        """)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesFootnoteDefinitionsAsRawMarkdown() {
        let source = """
        [^note]: A footnote.
            Continued detail.
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown])
        XCTAssertEqual(parsed.blocks[0].text, source)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownPreservesMultiParagraphFootnoteDefinitionAsRawMarkdown() {
        let source = """
        [^note]: First paragraph.

            Continued paragraph.
        # Heading
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .heading(level: 1)])
        XCTAssertEqual(parsed.blocks[0].text, """
        [^note]: First paragraph.

            Continued paragraph.
        """)
        XCTAssertEqual(parsed.markdown, source)
    }

    func testMarkdownDoesNotAbsorbOneSpaceParagraphAfterFootnoteDefinition() {
        let source = """
        [^note]: A footnote.

         Plain paragraph.
        """

        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.rawMarkdown, .paragraph])
        XCTAssertEqual(parsed.blocks[0].text, """
        [^note]: A footnote.

        """)
        XCTAssertEqual(parsed.blocks[1].text, " Plain paragraph.")
        XCTAssertEqual(parsed.markdown, source)
    }

    func testRawMarkdownSerializesVerbatimBetweenSupportedBlocks() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(kind: .heading(level: 2), text: "Before"),
            BlockInputBlock(kind: .rawMarkdown, text: "| A |\n| - |"),
            BlockInputBlock(kind: .paragraph, text: "After")
        ])

        XCTAssertEqual(document.markdown, """
        ## Before
        | A |
        | - |
        After
        """)
    }
}
