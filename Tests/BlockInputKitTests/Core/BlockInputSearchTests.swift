import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputSearchTests: XCTestCase {
    // MARK: - Empty query

    func testEmptyQueryProducesNoMatches() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "p", kind: .paragraph, text: "The quick brown fox")
        ])
        XCTAssertTrue(BlockInputSearch.matches(in: document, query: "").isEmpty)
    }

    func testWhitespaceOnlyQueryProducesNoMatches() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "p", kind: .paragraph, text: "The quick brown fox")
        ])
        XCTAssertTrue(BlockInputSearch.matches(in: document, query: "   \n\t").isEmpty)
    }

    // MARK: - Single match

    func testSingleMatchReturnsBlockIDAndRange() {
        let block = BlockInputBlock(id: "p", kind: .paragraph, text: "The quick brown fox")
        let document = BlockInputDocument(blocks: [block])

        let matches = BlockInputSearch.matches(in: document, query: "quick")
        XCTAssertEqual(matches.count, 1)
        let match = try? XCTUnwrap(matches.first)
        XCTAssertEqual(match?.blockID, "p")
        let substring = (block.text as NSString).substring(with: matches[0].range)
        XCTAssertEqual(substring, "quick")
    }

    // MARK: - Document order across blocks

    func testMatchesReturnedInDocumentOrder() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "a", kind: .paragraph, text: "alpha needle"),
            BlockInputBlock(id: "b", kind: .heading(level: 1), text: "needle beta"),
            BlockInputBlock(id: "c", kind: .paragraph, text: "gamma needle needle")
        ])

        let matches = BlockInputSearch.matches(in: document, query: "needle")
        XCTAssertEqual(matches.map(\.blockID), ["a", "b", "c", "c"])
        // Within block c, ascending location.
        let cMatches = matches.filter { $0.blockID == "c" }
        XCTAssertEqual(cMatches.count, 2)
        XCTAssertLessThan(cMatches[0].range.location, cMatches[1].range.location)
    }

    // MARK: - Case insensitivity

    func testCaseInsensitiveMatch() {
        let block = BlockInputBlock(id: "p", kind: .paragraph, text: "The cat sat")
        let document = BlockInputDocument(blocks: [block])

        let matches = BlockInputSearch.matches(in: document, query: "the")
        XCTAssertEqual(matches.count, 1)
        let substring = (block.text as NSString).substring(with: matches[0].range)
        XCTAssertEqual(substring, "The")
    }

    // MARK: - Multiple occurrences, non-overlapping

    func testMultipleNonOverlappingOccurrencesInOneBlock() {
        let block = BlockInputBlock(id: "p", kind: .paragraph, text: "aaaa")
        let document = BlockInputDocument(blocks: [block])

        let matches = BlockInputSearch.matches(in: document, query: "aa")
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].range, NSRange(location: 0, length: 2))
        XCTAssertEqual(matches[1].range, NSRange(location: 2, length: 2))
    }

    // MARK: - Searchable kinds vs skipped kinds

    func testSearchableBlockKindsAreSearched() {
        let blocks: [BlockInputBlock] = [
            BlockInputBlock(id: "heading", kind: .heading(level: 2), text: "needle heading"),
            BlockInputBlock(id: "bullet", kind: .bulletedListItem, text: "list needle"),
            BlockInputBlock(id: "quote", kind: .quote, text: "quote needle"),
            BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let needle = 1"),
            BlockInputBlock(id: "front", kind: .frontMatter, text: "title: needle")
        ]
        let document = BlockInputDocument(blocks: blocks)

        let matches = BlockInputSearch.matches(in: document, query: "needle")
        XCTAssertEqual(Set(matches.map(\.blockID)), ["heading", "bullet", "quote", "code", "front"])
        XCTAssertEqual(matches.count, 5)
    }

    func testImageAndHorizontalRuleProduceNoMatches() {
        let image = BlockInputImage(source: "needle.png", altText: "needle alt")
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(id: "img", kind: .image(image), text: "needle"),
            BlockInputBlock(id: "hr", kind: .horizontalRule, text: "needle")
        ])

        XCTAssertTrue(BlockInputSearch.matches(in: document, query: "needle").isEmpty)
    }

    // MARK: - Tables

    func testTableMatchMapsBackToExpectedCell() throws {
        let table = BlockInputTable.normalized(
            header: ["Name", "Role"],
            bodyRows: [["Ada", "needle engineer"], ["Bob", "designer"]],
            alignments: [.left, .left]
        )
        let block = BlockInputBlock(id: "table", kind: .table, text: table.markdown)
        let document = BlockInputDocument(blocks: [block])

        let matches = BlockInputSearch.matches(in: document, query: "needle")
        XCTAssertEqual(matches.count, 1)
        let match = try XCTUnwrap(matches.first)
        XCTAssertEqual(match.blockID, "table")

        // The source range maps back to the body(0), column 1 cell.
        let reconstructed = try XCTUnwrap(BlockInputTable(markdown: block.text))
        let position = try XCTUnwrap(reconstructed.cellPosition(containingSourceRange: match.range))
        XCTAssertEqual(position, BlockInputTable.CellPosition(row: .body(0), column: 1))

        // The source substring round-trips to the query (no escaping involved here).
        let sourceSubstring = (block.text as NSString).substring(with: match.range)
        XCTAssertEqual(sourceSubstring.lowercased(), "needle")
    }

    func testTableSearchesCellTextNotStructuralPipes() {
        // Query "|" should not match the table's structural pipe characters as cell content.
        let table = BlockInputTable.normalized(
            header: ["A", "B"],
            bodyRows: [["x", "y"]],
            alignments: [.left, .left]
        )
        let block = BlockInputBlock(id: "table", kind: .table, text: table.markdown)
        let document = BlockInputDocument(blocks: [block])

        XCTAssertTrue(BlockInputSearch.matches(in: document, query: "|").isEmpty)
    }

    func testTableWordMatchCountEqualsCellsContainingIt() {
        let table = BlockInputTable.normalized(
            header: ["needle", "Role"],
            bodyRows: [["needle", "x"], ["y", "needle"]],
            alignments: [.left, .left]
        )
        let block = BlockInputBlock(id: "table", kind: .table, text: table.markdown)
        let document = BlockInputDocument(blocks: [block])

        let matches = BlockInputSearch.matches(in: document, query: "needle")
        // Three cells contain "needle": header[0], body(0)[0], body(1)[1].
        XCTAssertEqual(matches.count, 3)
        XCTAssertTrue(matches.allSatisfy { $0.blockID == "table" })
    }

    func testTableMatchesAreInHeaderThenBodyOrder() throws {
        let table = BlockInputTable.normalized(
            header: ["zz", "Role"],
            bodyRows: [["zz", "x"]],
            alignments: [.left, .left]
        )
        let block = BlockInputBlock(id: "table", kind: .table, text: table.markdown)
        let document = BlockInputDocument(blocks: [block])

        let matches = BlockInputSearch.matches(in: document, query: "zz")
        XCTAssertEqual(matches.count, 2)
        // Header cell appears before the body cell (ascending source location).
        XCTAssertLessThan(matches[0].range.location, matches[1].range.location)

        let reconstructed = try XCTUnwrap(BlockInputTable(markdown: block.text))
        let first = try XCTUnwrap(reconstructed.cellPosition(containingSourceRange: matches[0].range))
        let second = try XCTUnwrap(reconstructed.cellPosition(containingSourceRange: matches[1].range))
        XCTAssertEqual(first, BlockInputTable.CellPosition(row: .header, column: 0))
        XCTAssertEqual(second, BlockInputTable.CellPosition(row: .body(0), column: 0))
    }

    // MARK: - Links: match the visible title, never the URL or syntax

    func testSearchMatchesLinkTitleNotURL() {
        let text = "See [Google](https://google.com) now"
        let doc = BlockInputDocument(blocks: [BlockInputBlock(id: "a", kind: .paragraph, text: text)])
        let matches = BlockInputSearch.matches(in: doc, query: "google")
        XCTAssertEqual(matches.count, 1, "only the visible title should match, not the URL")
        XCTAssertEqual((text as NSString).substring(with: matches[0].range), "Google")
    }

    func testSearchDoesNotMatchLinkSyntaxOrDestination() {
        let text = "[home](https://example.com/home)"
        let doc = BlockInputDocument(blocks: [BlockInputBlock(id: "a", kind: .paragraph, text: text)])
        // "home" appears in the title and in the URL path; only the title must match.
        let matches = BlockInputSearch.matches(in: doc, query: "home")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual((text as NSString).substring(with: matches[0].range), "home")
        // The destination host should never match.
        XCTAssertTrue(BlockInputSearch.matches(in: doc, query: "example.com").isEmpty)
    }

    func testSearchMatchesImageAltNotSource() {
        let text = "![a cat photo](https://imgs.example.com/cat.png)"
        let doc = BlockInputDocument(blocks: [BlockInputBlock(id: "a", kind: .paragraph, text: text)])
        XCTAssertEqual(BlockInputSearch.matches(in: doc, query: "cat").count, 1, "alt text matches; src does not")
        XCTAssertTrue(BlockInputSearch.matches(in: doc, query: "imgs").isEmpty)
    }

    func testSearchStillMatchesPlainTextAroundLinks() {
        let text = "before [link](http://x) after"
        let doc = BlockInputDocument(blocks: [BlockInputBlock(id: "a", kind: .paragraph, text: text)])
        XCTAssertEqual(BlockInputSearch.matches(in: doc, query: "before").count, 1)
        XCTAssertEqual(BlockInputSearch.matches(in: doc, query: "after").count, 1)
    }
}
