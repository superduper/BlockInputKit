extension BlockInputCompletionFileQuery {
    static func parsing(_ rawQuery: String) -> BlockInputCompletionFileQuery? {
        let reference: DirectoryReference
        let levelsUp: Int
        let prefixLength: Int
        if rawQuery.hasPrefix("...") {
            reference = .grandparent
            levelsUp = 2
            prefixLength = 3
        } else if rawQuery.hasPrefix("..") {
            reference = .parent
            levelsUp = 1
            prefixLength = 2
        } else if rawQuery.hasPrefix(".") {
            reference = .current
            levelsUp = 0
            prefixLength = 1
        } else {
            return nil
        }
        let remainderStart = rawQuery.index(rawQuery.startIndex, offsetBy: prefixLength)
        var remainder = String(rawQuery[remainderStart...])
        if remainder.hasPrefix("/") {
            remainder.removeFirst()
        }
        return BlockInputCompletionFileQuery(
            directoryReference: reference,
            levelsUp: levelsUp,
            remainder: remainder
        )
    }
}
