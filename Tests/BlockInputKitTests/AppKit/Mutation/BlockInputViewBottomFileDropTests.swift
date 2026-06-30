import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewBottomFileDropTests: XCTestCase {
    func testAsyncDropHookAppendsTransformedReferencesInBottomBlankSpace() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "First")
            ]),
            fileDropHandler: { context in
                XCTAssertEqual(context.placement, .documentEnd)
                return .insert([
                    BlockInputFileDropReference(kind: .fileLink, source: "assets/README.md", label: "Readme"),
                    BlockInputFileDropReference(kind: .image, source: "assets/Photo.png", label: "Photo")
                ])
            }
        ))
        let draggingInfo = try bottomBlankSpaceDraggingInfo(
            in: mounted.view,
            fileURLs: [
                URL(fileURLWithPath: "/tmp/README.md"),
                URL(fileURLWithPath: "/tmp/Photo.png")
            ]
        )

        XCTAssertTrue(mounted.view.collectionView(
            mounted.view.collectionView,
            acceptDrop: draggingInfo,
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .before
        ))
        await drainFileDropTasks(in: mounted.view)

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [
            "First",
            "[Readme](<assets/README.md>)",
            ""
        ])
        XCTAssertEqual(mounted.view.document.blocks[2].kind, .image(BlockInputImage(source: "assets/Photo.png", altText: "Photo")))
    }

    func testDroppingImageInBottomBlankSpaceAppendsImageBlock() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            BlockInputBlock(id: "second", text: "Second")
        ])
        let draggingInfo = try bottomBlankSpaceDraggingInfo(
            in: mounted.view,
            fileURLs: [URL(fileURLWithPath: "/tmp/Photo.png")]
        )
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

        XCTAssertTrue(dragOperation.contains(.copy))
        XCTAssertEqual(indexPath.item, 2)
        XCTAssertEqual(operation, .before)
        XCTAssertFalse(mounted.view.dropIndicatorView.isHidden)
        XCTAssertTrue(mounted.view.collectionView(
            mounted.view.collectionView,
            acceptDrop: draggingInfo,
            indexPath: IndexPath(item: 2, section: 0),
            dropOperation: .before
        ))
        XCTAssertEqual(mounted.view.document.blocks.map(\.kind), [.paragraph, .paragraph, .image(BlockInputImage(
            source: URL(fileURLWithPath: "/tmp/Photo.png").absoluteString,
            altText: "Photo"
        ))])
        XCTAssertEqual(mounted.view.selection, .blocks([mounted.view.document.blocks[2].id]))
    }

    func testDroppingNonImageFileInBottomBlankSpaceAppendsFileLinkBlock() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "first", text: "First")
        ])
        let draggingInfo = try bottomBlankSpaceDraggingInfo(
            in: mounted.view,
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")]
        )

        XCTAssertTrue(mounted.view.collectionView(
            mounted.view.collectionView,
            acceptDrop: draggingInfo,
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .before
        ))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [
            "First",
            "[README.md](<file:///tmp/README.md>)"
        ])
        XCTAssertEqual(
            mounted.view.selection,
            .cursor(BlockInputCursor(blockID: mounted.view.document.blocks[1].id, utf16Offset: 0))
        )
    }

    func testStoreBackedBottomBlankSpaceFileDropPublishesGranularInsertion() throws {
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "First")
        ]))
        var mutations: [BlockInputDocumentChange] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { mutations.append($0) }
        ))
        let draggingInfo = try bottomBlankSpaceDraggingInfo(
            in: mounted.view,
            fileURLs: [URL(fileURLWithPath: "/tmp/README.md")]
        )
        store.resetCounts()

        XCTAssertTrue(mounted.view.collectionView(
            mounted.view.collectionView,
            acceptDrop: draggingInfo,
            indexPath: IndexPath(item: 1, section: 0),
            dropOperation: .before
        ))

        let inserted = try XCTUnwrap(store.insertedBlockBatches.first)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(inserted.index, 1)
        XCTAssertEqual(inserted.blocks.map(\.text), ["[README.md](<file:///tmp/README.md>)"])
        XCTAssertEqual(mutations, [.insertBlocks(inserted.blocks, index: 1)])
    }

    private func bottomBlankSpaceDraggingInfo(in view: BlockInputView, fileURLs: [URL]) throws -> BlockInputDraggingInfo {
        view.collectionView.layoutSubtreeIfNeeded()
        let lastIndex = view.document.blocks.count - 1
        let attributes = try XCTUnwrap(view.collectionView.layoutAttributesForItem(
            at: IndexPath(item: lastIndex, section: 0)
        ))
        let collectionLocation = NSPoint(x: attributes.frame.midX, y: attributes.frame.maxY + 24)
        let visibleLocation = NSPoint(
            x: collectionLocation.x,
            y: min(collectionLocation.y, view.collectionView.visibleRect.maxY - 1)
        )
        return BlockInputDraggingInfo(
            fileURLs: fileURLs,
            location: view.collectionView.convert(visibleLocation, to: nil)
        )
    }

    private func drainFileDropTasks(in view: BlockInputView) async {
        while !view.fileDropTasks.isEmpty {
            await Task.yield()
        }
        await Task.yield()
    }
}
