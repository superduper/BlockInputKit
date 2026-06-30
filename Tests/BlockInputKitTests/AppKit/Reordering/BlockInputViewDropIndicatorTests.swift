import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewDropIndicatorTests: XCTestCase {
    func testDropInsertionIndexUsesUpperHalfOfVisibleItem() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            BlockInputBlock(id: "second", text: "Second"),
            BlockInputBlock(id: "third", text: "Third")
        ])
        let attributes = try XCTUnwrap(mounted.view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 1, section: 0)
        ))

        let insertionIndex = mounted.view.dropInsertionIndex(
            forLocation: NSPoint(x: attributes.frame.midX, y: attributes.frame.minY + 1),
            fallbackIndex: 0
        )

        XCTAssertEqual(insertionIndex, 1)
    }

    func testDropInsertionIndexUsesLowerHalfOfVisibleItem() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            BlockInputBlock(id: "second", text: "Second"),
            BlockInputBlock(id: "third", text: "Third")
        ])
        let attributes = try XCTUnwrap(mounted.view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 1, section: 0)
        ))

        let insertionIndex = mounted.view.dropInsertionIndex(
            forLocation: NSPoint(x: attributes.frame.midX, y: attributes.frame.maxY - 1),
            fallbackIndex: 0
        )

        XCTAssertEqual(insertionIndex, 2)
    }

    func testValidateDropRejectsNoOpWithinDraggedItemLowerHalf() throws {
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: "third", text: "Third")
        ])
        let attributes = try XCTUnwrap(mounted.view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 1, section: 0)
        ))
        let collectionLocation = NSPoint(x: attributes.frame.midX, y: attributes.frame.maxY - 1)
        let windowLocation = mounted.view.collectionView.convert(collectionLocation, to: nil)
        let draggingInfo = BlockInputDraggingInfo(blockID: secondID, location: windowLocation)
        var indexPath = NSIndexPath(forItem: 0, inSection: 0)
        var operation = NSCollectionView.DropOperation.on

        let dragOperation = withUnsafeMutablePointer(to: &indexPath) { pointer in
            mounted.view.collectionView(
                mounted.view.collectionView,
                validateDrop: draggingInfo,
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(pointer),
                dropOperation: &operation
            )
        }

        XCTAssertTrue(dragOperation.isEmpty)
        XCTAssertEqual(indexPath.item, 0)
        XCTAssertEqual(operation, .on)
        XCTAssertTrue(mounted.view.dropIndicatorView.isHidden)
    }

    func testValidateDropRejectsNoOpBeforeAdjacentNextItem() throws {
        let firstChildID = BlockInputBlockID(rawValue: "first-child")
        let secondChildID = BlockInputBlockID(rawValue: "second-child")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "parent", kind: .numberedListItem(start: 1), text: "Parent"),
            BlockInputBlock(id: firstChildID, kind: .numberedListItem(start: 1), text: "First", indentationLevel: 1),
            BlockInputBlock(id: secondChildID, kind: .numberedListItem(start: 2), text: "Second", indentationLevel: 1),
            BlockInputBlock(id: "next", kind: .numberedListItem(start: 2), text: "Next")
        ])
        let secondAttributes = try XCTUnwrap(mounted.view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 2, section: 0)
        ))
        let collectionLocation = NSPoint(x: secondAttributes.frame.midX, y: secondAttributes.frame.minY + 1)
        let windowLocation = mounted.view.collectionView.convert(collectionLocation, to: nil)
        var indexPath = NSIndexPath(forItem: 0, inSection: 0)
        var operation = NSCollectionView.DropOperation.on

        let dragOperation = withUnsafeMutablePointer(to: &indexPath) { pointer in
            mounted.view.collectionView(
                mounted.view.collectionView,
                validateDrop: BlockInputDraggingInfo(blockID: firstChildID, location: windowLocation),
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(pointer),
                dropOperation: &operation
            )
        }

        XCTAssertTrue(dragOperation.isEmpty)
        XCTAssertEqual(indexPath.item, 0)
        XCTAssertEqual(operation, .on)
        XCTAssertTrue(mounted.view.dropIndicatorView.isHidden)
    }

    func testValidateDropKeepsUpwardInsertionIndicatorAtResolvedIndex() throws {
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let secondAttributes = try XCTUnwrap(mounted.view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 1, section: 0)
        ))
        let collectionLocation = NSPoint(x: secondAttributes.frame.midX, y: secondAttributes.frame.minY + 1)
        let windowLocation = mounted.view.collectionView.convert(collectionLocation, to: nil)
        var indexPath = NSIndexPath(forItem: 0, inSection: 0)
        var operation = NSCollectionView.DropOperation.on

        let dragOperation = withUnsafeMutablePointer(to: &indexPath) { pointer in
            mounted.view.collectionView(
                mounted.view.collectionView,
                validateDrop: BlockInputDraggingInfo(blockID: thirdID, location: windowLocation),
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(pointer),
                dropOperation: &operation
            )
        }

        XCTAssertTrue(dragOperation.contains(.move))
        XCTAssertEqual(indexPath.item, 1)
        XCTAssertEqual(operation, .before)
        XCTAssertEqual(
            mounted.view.dropIndicatorView.frame.minY,
            mounted.view.dropIndicatorFrame(forInsertionIndex: 1)?.minY
        )
    }

    func testValidateDropShowsIndicatorBelowAdjacentNestedNumberedItem() throws {
        let firstChildID = BlockInputBlockID(rawValue: "first-child")
        let secondChildID = BlockInputBlockID(rawValue: "second-child")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "parent", kind: .numberedListItem(start: 1), text: "Parent"),
            BlockInputBlock(id: firstChildID, kind: .numberedListItem(start: 1), text: "First", indentationLevel: 1),
            BlockInputBlock(id: secondChildID, kind: .numberedListItem(start: 2), text: "Second", indentationLevel: 1),
            BlockInputBlock(id: "next", kind: .numberedListItem(start: 2), text: "Next")
        ])
        let secondAttributes = try XCTUnwrap(mounted.view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 2, section: 0)
        ))
        let collectionLocation = NSPoint(x: secondAttributes.frame.midX, y: secondAttributes.frame.maxY - 1)
        let windowLocation = mounted.view.collectionView.convert(collectionLocation, to: nil)
        var indexPath = NSIndexPath(forItem: 0, inSection: 0)
        var operation = NSCollectionView.DropOperation.on

        let dragOperation = withUnsafeMutablePointer(to: &indexPath) { pointer in
            mounted.view.collectionView(
                mounted.view.collectionView,
                validateDrop: BlockInputDraggingInfo(blockID: firstChildID, location: windowLocation),
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(pointer),
                dropOperation: &operation
            )
        }

        XCTAssertTrue(dragOperation.contains(.move))
        XCTAssertEqual(indexPath.item, 3)
        XCTAssertEqual(operation, .before)
        XCTAssertEqual(
            mounted.view.dropIndicatorView.frame.minY,
            mounted.view.dropIndicatorFrame(forInsertionIndex: 3)?.minY
        )
        XCTAssertEqual(
            mounted.view.dropIndicatorView.frame.midY,
            secondAttributes.frame.maxY,
            accuracy: 1
        )
    }

    func testCollectionValidateFileDropBeforeFrontMatterRejectsWithoutIndicator() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "front", kind: .frontMatter, text: "title: Demo"),
            BlockInputBlock(id: "body", text: "Body")
        ])
        let frontAttributes = try XCTUnwrap(mounted.view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 0, section: 0)
        ))
        let collectionLocation = NSPoint(x: frontAttributes.frame.midX, y: frontAttributes.frame.minY + 1)
        let windowLocation = mounted.view.collectionView.convert(collectionLocation, to: nil)
        var indexPath = NSIndexPath(forItem: 0, inSection: 0)
        var operation = NSCollectionView.DropOperation.on

        let dragOperation = withUnsafeMutablePointer(to: &indexPath) { pointer in
            mounted.view.collectionView(
                mounted.view.collectionView,
                validateDrop: BlockInputDraggingInfo(fileURLs: [URL(fileURLWithPath: "/tmp/example.txt")], location: windowLocation),
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(pointer),
                dropOperation: &operation
            )
        }

        XCTAssertTrue(dragOperation.isEmpty)
        XCTAssertEqual(indexPath.item, 0)
        XCTAssertEqual(operation, .on)
        XCTAssertTrue(mounted.view.dropIndicatorView.isHidden)
    }

    func testAcceptDropUsesResolvedInsertionIndexInsteadOfStaleProposedIndex() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ])
        let secondAttributes = try XCTUnwrap(mounted.view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: 1, section: 0)
        ))
        let collectionLocation = NSPoint(x: secondAttributes.frame.midX, y: secondAttributes.frame.minY + 1)
        let windowLocation = mounted.view.collectionView.convert(collectionLocation, to: nil)

        let accepted = mounted.view.collectionView(
            mounted.view.collectionView,
            acceptDrop: BlockInputDraggingInfo(blockID: thirdID, location: windowLocation),
            indexPath: IndexPath(item: 0, section: 0),
            dropOperation: .before
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [firstID, thirdID, secondID])
    }

    func testAcceptDropRejectsNoOpBlockReorderWithoutFallingThroughToFileInsertion() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])))

        let accepted = view.collectionView(
            view.collectionView,
            acceptDrop: BlockInputDraggingInfo(
                blockID: firstID,
                fileURLs: [URL(fileURLWithPath: "/tmp/example.txt")]
            ),
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .before
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
    }

    func testDropIndicatorUsesConfiguredColor() {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "First")
            ]),
            dropIndicatorColor: .systemPink
        ))

        view.showDropIndicator(atInsertionIndex: 0)

        XCTAssertEqual(view.dropIndicatorColor, .systemPink)
        XCTAssertEqual(view.dropIndicatorView.layer?.backgroundColor, NSColor.systemPink.cgColor)
    }

    func testDropIndicatorIsHiddenFromAccessibility() {
        let view = BlockInputView()

        XCTAssertFalse(view.dropIndicatorView.isAccessibilityElement())
    }

    func testDropIndicatorColorUpdatesWhenReconfigured() {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(dropIndicatorColor: .systemBlue))

        view.configure(BlockInputConfiguration(dropIndicatorColor: .systemGreen))

        XCTAssertEqual(view.dropIndicatorColor, .systemGreen)
        XCTAssertEqual(view.dropIndicatorView.layer?.backgroundColor, NSColor.systemGreen.cgColor)
    }

    func testInvalidDropHidesInsertionIndicator() {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "First")
        ])))
        view.showDropIndicator(atInsertionIndex: 0)
        var indexPath = NSIndexPath(forItem: 0, inSection: 0)
        var operation = NSCollectionView.DropOperation.on

        _ = withUnsafeMutablePointer(to: &indexPath) { pointer in
            view.collectionView(
                view.collectionView,
                validateDrop: BlockInputDraggingInfo(blockID: nil),
                proposedIndexPath: AutoreleasingUnsafeMutablePointer(pointer),
                dropOperation: &operation
            )
        }

        XCTAssertTrue(view.dropIndicatorView.isHidden)
    }
}
