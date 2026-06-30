import AppKit
import CoreGraphics
import Foundation

enum BlockInputVerticalMovementDirection: Equatable {
    case upward
    case downward
}

/// Logical Shift+Left/Right direction after AppKit key events are normalized.
enum BlockInputHorizontalMovementDirection: Equatable {
    case leftward
    case rightward
}

/// Logical Shift+Command+Left/Right line-boundary selection direction.
enum BlockInputLineBoundarySelectionDirection: Equatable {
    case beginning
    case end
}

/// Logical Option+Left/Right direction after AppKit key events and selectors are normalized.
enum BlockInputWordMovementDirection: Equatable {
    case leftward
    case rightward
}

enum BlockInputLinkBoundaryDeletionDirection: Equatable {
    case backward
    case forward
}

struct BlockInputTableCellTextChange {
    var text: String
    var position: BlockInputTable.CellPosition
    var selectedLocalRange: NSRange
    var selectionBefore: BlockInputSelection?
}

enum BlockInputTableBoundaryPlacement {
    case above
    case below
}

@MainActor
protocol BlockInputBlockItemDelegate: AnyObject {
    func blockItemDidBeginEditing(_ item: BlockInputBlockItem, blockID: BlockInputBlockID)
    func blockItemDidEndEditing(_ item: BlockInputBlockItem, blockID: BlockInputBlockID)
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didChangeText text: String,
        selectionBefore: BlockInputSelection?
    )
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didChangeTableCellText change: BlockInputTableCellTextChange
    )
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableFocus position: BlockInputTable.CellPosition
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableBodyRowAppendFrom position: BlockInputTable.CellPosition?
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableColumnAppendFrom position: BlockInputTable.CellPosition?
    ) -> Bool
    /// Requests the context-menu `Insert Row` mutation at a table cell; final-cell Tab uses this path.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableBodyRowInsertionAt position: BlockInputTable.CellPosition
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableBodyRowDeletionAt position: BlockInputTable.CellPosition
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTableColumnDeletionAt position: BlockInputTable.CellPosition
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestParagraphAdjacentToTable placement: BlockInputTableBoundaryPlacement
    ) -> Bool
    func blockItemDidRequestCopyActiveSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool
    func blockItemDidRequestCutActiveSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool
    func blockItemDidRequestPasteActiveSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool
    func blockItemDidRequestDeleteActiveSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool
    func blockItemDidRequestSelectTable(_ item: BlockInputBlockItem, blockID: BlockInputBlockID)
    func blockItem(_ item: BlockInputBlockItem, didChangeSelectionIn blockID: BlockInputBlockID, selectedRange: NSRange?)
    func blockItemDidRequestReturn(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool
    func blockItemDidRequestMergeWithPreviousBlock(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool
    func blockItemDidRequestDeleteEmptyBlock(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestLinkBoundaryDeletion direction: BlockInputLinkBoundaryDeletionDirection
    ) -> Bool
    func blockItemDidRequestUnwrapBlock(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool
    func blockItemDidRevealReorderHandle(_ item: BlockInputBlockItem)
    func blockItemDidRequestSelectAll(_ item: BlockInputBlockItem, blockID: BlockInputBlockID)
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestUndoShortcut shortcut: BlockInputUndoShortcut
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTextFormattingShortcut shortcut: BlockInputTextFormattingShortcut
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestKeyboardShortcut shortcut: BlockInputKeyboardShortcut,
        selectedRange: NSRange,
        focusSource: BlockInputKeyboardShortcutFocusSource,
        isRepeat: Bool,
        performDefault: @escaping @MainActor (BlockInputKeyboardShortcut) -> Bool
    ) -> BlockInputKeyboardShortcutDispatchResult
    /// Lets a mounted text view route completion key events through the editor-owned popup.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestCompletionKeyDown event: NSEvent
    ) -> Bool
    /// Lets a mounted text view route completion commands through the editor-owned popup.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestCompletionCommand selector: Selector
    ) -> Bool
    /// Lets a mounted text view offer supported URL paste to the editor before falling back to native AppKit paste.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestPasteURL urlString: String,
        selectedRange: NSRange
    ) -> Bool
    /// Lets a mounted text view route local file drops through editor-owned source mutation.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestInsertFileURLs fileURLs: [URL],
        atUTF16Offset utf16Offset: Int
    ) -> Bool
    /// Lets a mounted text view offer rich pasteboard content to registered paste handlers before native paste.
    /// `onDeclined` runs when a handler claimed the paste but declined async, so the caller can run native paste.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestPasteRichContentAtUTF16Offset utf16Offset: Int,
        onDeclined: @escaping () -> Void
    ) -> Bool
    /// Builds editor-owned insertion/link context-menu items from mounted row state.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestLinkContextMenuItemsFor event: NSEvent,
        selectedRange: NSRange
    ) -> [NSMenuItem]
    /// Routes link activation through the editor so command-click open and plain-click edit share one context lookup.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didClickLinkAt selectedRange: NSRange,
        clickedLinkRange: BlockInputInlineMarkdownRange?,
        event: NSEvent
    ) -> Bool
    /// Whether the editor's hover Edit affordance is enabled for inline links.
    func blockItemLinkHoverEditAffordanceEnabled(_ item: BlockInputBlockItem) -> Bool
    /// Asks the editor to show the hover Edit popover anchored to a hovered inline link.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didHoverLink sourceLinkRange: BlockInputInlineMarkdownRange,
        windowRects: [NSRect]
    )
    /// Asks the editor to schedule a graced dismissal of the hover Edit popover.
    func blockItemDidRequestDismissLinkHoverAffordance(_ item: BlockInputBlockItem)
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        textFormattingMenuItemStatesForSelectedRange selectedRange: NSRange
    ) -> [BlockInputTextFormattingMenuItemState]
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        textFormattingMenuItemStatesForContextEvent event: NSEvent
    ) -> [BlockInputTextFormattingMenuItemState]
    func blockItemDidRequestSelectHorizontalRule(_ item: BlockInputBlockItem, blockID: BlockInputBlockID)
    func blockItem(_ item: BlockInputBlockItem, blockID: BlockInputBlockID, didRequestImageCaretAt offset: Int)
    func blockItemDidRequestToggleChecklist(_ item: BlockInputBlockItem, blockID: BlockInputBlockID)
    func blockItem(_ item: BlockInputBlockItem, blockID: BlockInputBlockID, didResolveImageDimensions dimensions: BlockInputImageDimensions)
    func blockItem(_ item: BlockInputBlockItem, blockID: BlockInputBlockID, didResizeImageToWidth width: Int, height: Int)
    func blockItemDidBeginReordering(_ item: BlockInputBlockItem, blockID: BlockInputBlockID)
    func blockItemDidRequestIndent(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        selectedRange: NSRange
    )
    func blockItemDidRequestOutdent(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        selectedRange: NSRange
    )
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestVerticalMovement direction: BlockInputVerticalMovementDirection,
        preferredTextContainerX: CGFloat?
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didDragSelectBlocksWith event: NSEvent,
        selectedRange: NSRange?
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestExpandSelection direction: BlockInputVerticalMovementDirection,
        selectedRange: NSRange,
        preferredTextContainerX: CGFloat?
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestExpandActiveBlockSelection direction: BlockInputVerticalMovementDirection
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestHorizontalSelectionAdjustment direction: BlockInputHorizontalMovementDirection,
        selectedRange: NSRange
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestLineBoundarySelection direction: BlockInputLineBoundarySelectionDirection,
        selectedRange: NSRange
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestWordMovement direction: BlockInputWordMovementDirection,
        selectedRange: NSRange
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestWordSelectionAdjustment direction: BlockInputWordMovementDirection,
        previousSelectedRange: NSRange,
        selectedRange: NSRange
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestCollapseSelection direction: BlockInputVerticalMovementDirection
    ) -> Bool
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestDocumentBoundary direction: BlockInputVerticalMovementDirection
    ) -> Bool
    func blockItemDidRequestCancelSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool
    func blockItemDidRequestMouseDownCancelSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool
    /// Called before AppKit processes a key-down event in any mounted text view.
    /// Return `true` to consume the event; `false` to let AppKit handle it.
    func blockItemShouldInterceptKeyDown(_ item: BlockInputBlockItem, event: NSEvent) -> Bool
    /// Reports the resolved render dimensions of a rendered-content block (e.g. a Mermaid diagram) so
    /// the editor can re-measure the row. Unlike image dimensions, this does not mutate the document or
    /// register undo, and it fires even when the editor is not editable.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didResolveRenderedContentDimensions dimensions: BlockInputImageDimensions
    )
    /// Requests presenting the zoom modal for a rendered-content block.
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestExpandRenderedContent expansion: BlockInputRenderedContentExpansion
    )
    /// Reports that a rendered-content block failed to render, so the editor can drop any stale resolved
    /// dimensions and re-measure the row to a failure-state height.
    func blockItemDidFailToRenderContent(_ item: BlockInputBlockItem, blockID: BlockInputBlockID)
    /// Requests opening the floating diagram editor for a rendered-content block (the ✏️ button).
    func blockItem(_ item: BlockInputBlockItem, blockID: BlockInputBlockID, didRequestEditBlockContent contentIdentifier: String)
    /// Requests opening the diagram editor in AI mode and auto-running a fix (the "Fix with AI" button shown on
    /// a failed diagram).
    func blockItem(_ item: BlockInputBlockItem, blockID: BlockInputBlockID, didRequestFixBlockContent contentIdentifier: String)
}

extension BlockInputBlockItemDelegate {
    func blockItemShouldInterceptKeyDown(_ item: BlockInputBlockItem, event: NSEvent) -> Bool { false }
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didResolveRenderedContentDimensions dimensions: BlockInputImageDimensions
    ) {}
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestExpandRenderedContent expansion: BlockInputRenderedContentExpansion
    ) {}
    func blockItemDidFailToRenderContent(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) {}
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestEditBlockContent contentIdentifier: String
    ) {}
    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestFixBlockContent contentIdentifier: String
    ) {}
}
