import AppKit
import SnapshotTesting
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewReadOnlySnapshotTests: XCTestCase {
    func testDisabledDocumentSnapshot() {
        let snapshotCase = DisabledDocumentSnapshotCase.dark
        assertSnapshot(
            of: makeDisabledDocumentSnapshotView(for: snapshotCase),
            as: appKitSnapshotImage(),
            named: snapshotCase.name
        )
    }

    private func makeDisabledDocumentSnapshotView(for snapshotCase: DisabledDocumentSnapshotCase) -> NSView {
        let view = BlockInputView(frame: NSRect(origin: .zero, size: snapshotCase.size))
        view.appearance = NSAppearance(named: snapshotCase.appearance)
        view.configure(BlockInputConfiguration(
            document: .snapshotDisabledDocument,
            allowsBlockReordering: false,
            isEditable: false,
            disabledCursor: .operationNotAllowed
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return view
    }
}

private struct DisabledDocumentSnapshotCase {
    var name: String
    var appearance: NSAppearance.Name
    var size: CGSize

    static let dark = Self(name: "disabled-document-dark", appearance: .darkAqua, size: CGSize(width: 680, height: 420))
}

private extension BlockInputDocument {
    static let snapshotDisabledDocument = BlockInputDocument(blocks: [
        BlockInputBlock(id: "frontmatter", kind: .frontMatter, text: "title: Disabled draft\nstatus: archived"),
        BlockInputBlock(id: "paragraph", text: "Read-only paragraph with [Docs](https://example.com/docs) and `inline code`."),
        BlockInputBlock(id: "table", kind: .table, text: """
        | Field | Value |
        | --- | --- |
        | Mode | Disabled |
        | Cursor | Not allowed |
        """),
        BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let editor = BlockInputView()\neditor.isEditable = false"),
        BlockInputBlock(id: "task", kind: .checklistItem(isChecked: true), text: "Completed task stays selectable")
    ])
}
