import AppKit

public extension BlockInputView {
    /// Drops the native caret into the first cell of a table block, so native table editing takes
    /// over. Returns `true` when the table was found and a cell was focused.
    ///
    /// Embedders such as the vim plugin use this as an "escape hatch": from a whole-block table
    /// selection, enter the table for native editing instead of running custom key handling.
    /// Focusing the first cell directly (rather than via a text offset) avoids the table's leading
    /// pipe, which maps to no cell.
    @discardableResult
    func focusFirstTableCell(in blockID: BlockInputBlockID) -> Bool {
        refreshDocumentFromStore()
        guard block(withID: blockID)?.kind == .table,
              let item = visibleItem(for: blockID) else {
            return false
        }
        return blockItem(item, blockID: blockID, didRequestTableFocus: .init(row: .header, column: 0))
    }

    /// Re-selects a table as a whole-block selection and hands first responder back to the editor.
    ///
    /// This is the inverse of ``focusFirstTableCell(in:)``: it returns from native cell editing to
    /// block focus so an embedder (e.g. the vim plugin) can resume its own key handling. Returns
    /// `true` when the block exists and is a table.
    @discardableResult
    func selectTableAsBlock(_ blockID: BlockInputBlockID) -> Bool {
        refreshDocumentFromStore()
        guard block(withID: blockID)?.kind == .table,
              let item = visibleItem(for: blockID) else {
            return false
        }
        blockItemDidRequestSelectTable(item, blockID: blockID)
        return true
    }
}
