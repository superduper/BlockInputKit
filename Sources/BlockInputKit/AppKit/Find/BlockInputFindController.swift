import Foundation

/// Holds find state for the editor: the active query, the ordered match list, and
/// which match is currently active. Pure navigation logic with no AppKit dependency,
/// so it is unit-testable on its own and drives selection/scroll from `BlockInputView`.
struct BlockInputFindController {
    /// Current search query.
    private(set) var query: String = ""
    /// Matches for `query` in document order.
    private(set) var matches: [BlockInputSearchMatch] = []
    /// Index of the active match within `matches`, or `nil` when there are none.
    private(set) var activeMatchIndex: Int?

    /// Whether any match is currently available.
    var hasMatches: Bool { !matches.isEmpty }

    /// Active match, or `nil` when there are none.
    var activeMatch: BlockInputSearchMatch? {
        guard let activeMatchIndex, matches.indices.contains(activeMatchIndex) else {
            return nil
        }
        return matches[activeMatchIndex]
    }

    /// 1-based current index and total count for the find bar. `current` is `0` when empty.
    var matchCount: (current: Int, total: Int) {
        guard let activeMatchIndex, !matches.isEmpty else {
            return (0, matches.count)
        }
        return (activeMatchIndex + 1, matches.count)
    }

    /// Replaces the query and match list, then anchors the active match to the first
    /// match at or after `preferredStart` (block index, then source location), or to the
    /// first match when none qualifies. Returns the resulting active match, if any.
    @discardableResult
    mutating func update(
        query: String,
        matches: [BlockInputSearchMatch],
        preferredStart: BlockInputFindPosition?
    ) -> BlockInputSearchMatch? {
        self.query = query
        self.matches = matches
        guard !matches.isEmpty else {
            activeMatchIndex = nil
            return nil
        }
        activeMatchIndex = firstMatchIndex(atOrAfter: preferredStart) ?? 0
        return activeMatch
    }

    /// Advances the active match by one with wrap-around. Returns the new active match,
    /// or `nil` when there are no matches.
    @discardableResult
    mutating func moveToNext() -> BlockInputSearchMatch? {
        move(by: 1)
    }

    /// Moves the active match back by one with wrap-around. Returns the new active match,
    /// or `nil` when there are no matches.
    @discardableResult
    mutating func moveToPrevious() -> BlockInputSearchMatch? {
        move(by: -1)
    }

    /// Clears all find state.
    mutating func reset() {
        query = ""
        matches = []
        activeMatchIndex = nil
    }

    private mutating func move(by delta: Int) -> BlockInputSearchMatch? {
        guard !matches.isEmpty else {
            activeMatchIndex = nil
            return nil
        }
        let current = activeMatchIndex ?? 0
        let count = matches.count
        activeMatchIndex = ((current + delta) % count + count) % count
        return activeMatch
    }

    private func firstMatchIndex(atOrAfter start: BlockInputFindPosition?) -> Int? {
        guard let start else {
            return nil
        }
        return matches.firstIndex { match in
            guard let matchBlockIndex = start.resolveBlockIndex(match.blockID) else {
                return false
            }
            if matchBlockIndex != start.blockIndex {
                return matchBlockIndex > start.blockIndex
            }
            return match.range.location >= start.location
        }
    }
}

/// Caret-derived anchor used to pick the first match at or after the current selection.
struct BlockInputFindPosition {
    /// Document index of the anchoring block.
    let blockIndex: Int
    /// UTF-16 source location within the anchoring block.
    let location: Int
    /// Resolves a match's block to a document index for ordering comparisons.
    let resolveBlockIndex: (BlockInputBlockID) -> Int?
}
