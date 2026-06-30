import XCTest
@testable import BlockInputKit

final class BlockInputHeadingAnchorResolverTests: XCTestCase {
    private func heading(_ id: String, _ text: String, level: Int = 1) -> BlockInputBlock {
        BlockInputBlock(id: BlockInputBlockID(rawValue: id), kind: .heading(level: level), text: text)
    }
    private func para(_ id: String, _ text: String) -> BlockInputBlock {
        BlockInputBlock(id: BlockInputBlockID(rawValue: id), text: text)
    }

    func testResolvesHeadingBySlug() {
        let resolver = BlockInputHeadingAnchorResolver(blocks: [heading("h1", "Foo Bar"), para("p", "body")])
        XCTAssertEqual(resolver.resolve("foo-bar"), BlockInputBlockID(rawValue: "h1"))
    }
    func testIgnoresNonHeadings() {
        let resolver = BlockInputHeadingAnchorResolver(blocks: [para("p", "Foo Bar")])
        XCTAssertNil(resolver.resolve("foo-bar"))
    }
    func testDuplicateHeadingsGetSuffixesInOrder() {
        let resolver = BlockInputHeadingAnchorResolver(blocks: [heading("a", "Setup"), heading("b", "Setup"), heading("c", "Setup")])
        XCTAssertEqual(resolver.resolve("setup"), BlockInputBlockID(rawValue: "a"))
        XCTAssertEqual(resolver.resolve("setup-1"), BlockInputBlockID(rawValue: "b"))
        XCTAssertEqual(resolver.resolve("setup-2"), BlockInputBlockID(rawValue: "c"))
    }
    func testUnknownSlugIsNil() {
        let resolver = BlockInputHeadingAnchorResolver(blocks: [heading("h1", "Foo")])
        XCTAssertNil(resolver.resolve("bar"))
    }
}
