import Foundation

/// A bounded marker-only update for numbered-list blocks.
public struct BlockInputNumberedListMarkerTransaction: Equatable, Sendable {
    /// Marker deltas applied to numbered list items in index ranges.
    public var adjustments: [BlockInputNumberedListMarkerAdjustment]
    /// Exact marker values for moved or inserted numbered list items.
    public var overrides: [BlockInputNumberedListMarkerOverride]

    /// Creates a numbered-list marker transaction.
    public init(
        adjustments: [BlockInputNumberedListMarkerAdjustment] = [],
        overrides: [BlockInputNumberedListMarkerOverride] = []
    ) {
        self.adjustments = adjustments
        self.overrides = overrides
    }

    var isEmpty: Bool {
        adjustments.isEmpty && overrides.isEmpty
    }

    var inverted: BlockInputNumberedListMarkerTransaction {
        BlockInputNumberedListMarkerTransaction(
            adjustments: adjustments.map { $0.inverted },
            overrides: overrides.map { $0.inverted }
        )
    }
}

/// Applies a relative marker shift to numbered list items in an index range.
public struct BlockInputNumberedListMarkerAdjustment: Equatable, Sendable {
    /// Inclusive start index after the structural edit has been applied.
    public var startIndex: Int
    /// Inclusive end index after the structural edit has been applied. `nil` means the available suffix.
    public var endIndex: Int?
    /// Optional list-run start index. When present, the adjustment stops at the first non-list or lower-indentation boundary.
    public var listRunStartIndex: Int?
    /// Only numbered list items at this indentation level are adjusted.
    public var indentationLevel: Int
    /// Relative marker shift.
    public var delta: Int

    /// Creates a marker adjustment.
    public init(
        startIndex: Int,
        endIndex: Int?,
        listRunStartIndex: Int? = nil,
        indentationLevel: Int,
        delta: Int
    ) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.listRunStartIndex = listRunStartIndex
        self.indentationLevel = indentationLevel
        self.delta = delta
    }

    var inverted: BlockInputNumberedListMarkerAdjustment {
        BlockInputNumberedListMarkerAdjustment(
            startIndex: startIndex,
            endIndex: endIndex,
            listRunStartIndex: listRunStartIndex,
            indentationLevel: indentationLevel,
            delta: -delta
        )
    }
}

/// Replaces one numbered list item's marker with an exact value.
public struct BlockInputNumberedListMarkerOverride: Equatable, Sendable {
    /// Block receiving the exact marker.
    public var blockID: BlockInputBlockID
    /// Exact marker value after the transaction is applied.
    public var start: Int
    /// Marker value before the transaction was applied, used for inversion.
    public var previousStart: Int

    /// Creates a marker override.
    public init(blockID: BlockInputBlockID, start: Int, previousStart: Int) {
        self.blockID = blockID
        self.start = start
        self.previousStart = previousStart
    }

    var inverted: BlockInputNumberedListMarkerOverride {
        BlockInputNumberedListMarkerOverride(blockID: blockID, start: previousStart, previousStart: start)
    }
}

/// Store capability for applying marker-only numbered-list changes without replacing every block.
///
/// Stores that keep marker transactions pending should expose effective markers from block reads and snapshots.
/// Later `replaceBlock(_:)` calls may pass those effective blocks back to the store, so implementations must avoid
/// applying the same pending marker delta to the replacement a second time.
public protocol BlockInputMarkerAdjustingStore: BlockInputDocumentStore {
    /// Applies numbered-list marker changes.
    func applyNumberedListMarkerTransaction(_ transaction: BlockInputNumberedListMarkerTransaction)
    /// Moves a block without eagerly normalizing numbered-list markers.
    func moveBlockWithoutNormalizing(withID id: BlockInputBlockID, to index: Int)
}

let markerAdjustmentCompactionLimit = 128

extension BlockInputNumberedListMarkerAdjustment {
    func resolvingListRunBounds(in blocks: [BlockInputBlock]) -> BlockInputNumberedListMarkerAdjustment? {
        guard let listRunStartIndex else {
            return self
        }
        guard blocks.indices.contains(listRunStartIndex),
              blocks[listRunStartIndex].kind.supportsIndentation else {
            return nil
        }

        var runEndIndex = listRunStartIndex
        while blocks.indices.contains(runEndIndex),
              blocks[runEndIndex].kind.supportsIndentation {
            if runEndIndex != listRunStartIndex,
               blocks[runEndIndex].indentationLevel(forLine: 0) < indentationLevel {
                break
            }
            runEndIndex += 1
        }
        let resolvedStartIndex = max(startIndex, listRunStartIndex)
        let resolvedEndIndex = min(endIndex ?? runEndIndex - 1, runEndIndex - 1)
        guard resolvedEndIndex >= resolvedStartIndex else {
            return nil
        }
        return BlockInputNumberedListMarkerAdjustment(
            startIndex: resolvedStartIndex,
            endIndex: resolvedEndIndex,
            indentationLevel: indentationLevel,
            delta: delta
        )
    }

    func contains(index: Int, block: BlockInputBlock) -> Bool {
        guard index >= startIndex,
              endIndex.map({ index <= $0 }) ?? true,
              block.indentationLevel(forLine: 0) == indentationLevel else {
            return false
        }
        guard case .numberedListItem = block.kind else {
            return false
        }
        return true
    }

    func isWithinListRunScope(at index: Int, in blocks: [BlockInputBlock]) -> Bool {
        guard let listRunStartIndex else {
            return true
        }
        guard listRunStartIndex <= index,
              blocks.indices.contains(listRunStartIndex),
              blocks.indices.contains(index) else {
            return false
        }
        for scopedIndex in listRunStartIndex...index {
            guard blocks[scopedIndex].kind.supportsIndentation else {
                return false
            }
            if scopedIndex != listRunStartIndex,
               blocks[scopedIndex].indentationLevel(forLine: 0) < indentationLevel {
                return false
            }
        }
        return true
    }

    func shiftedForInsertion(at index: Int, count: Int) -> BlockInputNumberedListMarkerAdjustment {
        BlockInputNumberedListMarkerAdjustment(
            startIndex: startIndex >= index ? startIndex + count : startIndex,
            endIndex: endIndex.map { $0 >= index ? $0 + count : $0 },
            listRunStartIndex: listRunStartIndex.map { $0 >= index ? $0 + count : $0 },
            indentationLevel: indentationLevel,
            delta: delta
        )
    }

    func shiftedForDeletion(at index: Int, count: Int) -> BlockInputNumberedListMarkerAdjustment? {
        let deletionEnd = index + count - 1
        let shiftedStart = startIndex.shiftedAfterDeletingRange(index...deletionEnd, count: count)
        let shiftedEnd = endIndex.map { end in
            if end > deletionEnd {
                return end - count
            }
            if end >= index {
                return index - 1
            }
            return end
        }
        if let shiftedEnd, shiftedEnd < shiftedStart {
            return nil
        }
        return BlockInputNumberedListMarkerAdjustment(
            startIndex: shiftedStart,
            endIndex: shiftedEnd,
            listRunStartIndex: listRunStartIndex.map { $0.shiftedAfterDeletingRange(index...deletionEnd, count: count) },
            indentationLevel: indentationLevel,
            delta: delta
        )
    }
}

extension Array where Element == BlockInputNumberedListMarkerTransaction {
    func resolvingListRunBounds(in blocks: [BlockInputBlock]) -> [BlockInputNumberedListMarkerTransaction] {
        map { transaction in
            BlockInputNumberedListMarkerTransaction(
                adjustments: transaction.adjustments.compactMap { $0.resolvingListRunBounds(in: blocks) },
                overrides: transaction.overrides
            )
        }.filter { !$0.isEmpty }
    }
}

private extension Int {
    func shiftedAfterDeletingRange(_ deletedRange: ClosedRange<Int>, count: Int) -> Int {
        if self > deletedRange.upperBound {
            return self - count
        }
        if self >= deletedRange.lowerBound {
            return deletedRange.lowerBound
        }
        return self
    }
}
