import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class TextFormattingContextMenuUtilityTests: XCTestCase {
    func testFormattingItemsPrependWithoutRedundantSeparators() throws {
        let menu = NSMenu()
        let formattingItem = NSMenuItem(title: "Bold", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy", action: nil, keyEquivalent: ""))

        menu.blockInputPrependingTextFormattingItems([formattingItem])

        XCTAssertEqual(menu.items.first, formattingItem)
        XCTAssertNotNil(menu.item(withTitle: "Copy"))
        XCTAssertFalse(menu.items.first?.isSeparatorItem == true)
        XCTAssertFalse(menu.items.last?.isSeparatorItem == true)
        XCTAssertFalse(menuContainsAdjacentSeparators(menu))
    }

    private func menuContainsAdjacentSeparators(_ menu: NSMenu) -> Bool {
        menu.items.indices.dropFirst().contains { index in
            menu.items[index].isSeparatorItem && menu.items[index - 1].isSeparatorItem
        }
    }
}
