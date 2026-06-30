import Foundation

extension BlockInputTable {
    func insertingBodyRow(at rowIndex: Int) -> BlockInputTable? {
        guard rowIndex >= 0,
              rowIndex <= bodyRows.count else {
            return nil
        }
        var bodyText = bodyRows.map { $0.map(\.text) }
        bodyText.insert(Array(repeating: "", count: columnCount), at: rowIndex)
        return Self.normalized(header: header.map(\.text), bodyRows: bodyText, alignments: alignments)
    }

    func insertingColumn(at column: Int) -> BlockInputTable? {
        guard column >= 0,
              column <= columnCount else {
            return nil
        }
        var headerText = header.map(\.text)
        var bodyText = bodyRows.map { $0.map(\.text) }
        var updatedAlignments = alignments
        headerText.insert("", at: column)
        updatedAlignments.insert(.left, at: column)
        for rowIndex in bodyText.indices {
            bodyText[rowIndex].insert("", at: column)
        }
        return Self.normalized(header: headerText, bodyRows: bodyText, alignments: updatedAlignments)
    }
}
