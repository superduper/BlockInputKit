import Foundation

/// Shared row/line selection ladder for block-owned surfaces that promote only after every internal unit is selected.
///
/// Tables use display rows and multi-line list items use logical text lines. Keeping the anchor/focus math here
/// prevents those two keyboard-selection paths from drifting.
struct BlockInputLinearSelectionLadder: Equatable {
    var anchor: Int
    var focus: Int
    var bounds: ClosedRange<Int>

    var selectedBounds: ClosedRange<Int> {
        min(anchor, focus)...max(anchor, focus)
    }

    var isCollapsedAtAnchor: Bool {
        anchor == focus
    }

    var coversBounds: Bool {
        selectedBounds.lowerBound == bounds.lowerBound && selectedBounds.upperBound == bounds.upperBound
    }

    func focusAfterMoving(_ direction: BlockInputVerticalMovementDirection) -> Int? {
        let nextFocus = focus + direction.linearSelectionDelta
        return bounds.contains(nextFocus) ? nextFocus : nil
    }

    static func bounds(count: Int) -> ClosedRange<Int>? {
        count > 0 ? 0...(count - 1) : nil
    }

    static func edgeIndex(
        in bounds: ClosedRange<Int>,
        direction: BlockInputVerticalMovementDirection
    ) -> Int {
        // Entering a row/line-owned block from above selects the top unit; entering from below selects the bottom unit.
        // Keep this shared so table rows and nested list lines do not choose different first-selection edges.
        direction == .upward ? bounds.upperBound : bounds.lowerBound
    }

    static func promotedFocusIndex(
        in bounds: ClosedRange<Int>,
        direction: BlockInputVerticalMovementDirection
    ) -> Int {
        // After all internal units promote to a whole block, the active edge flips to the far side so the next opposite
        // Shift+Arrow demotes by removing exactly one unit instead of abandoning the block selection.
        direction == .upward ? bounds.lowerBound : bounds.upperBound
    }

    static func boundsAfterExpanding(
        _ selectedBounds: ClosedRange<Int>,
        direction: BlockInputVerticalMovementDirection,
        within bounds: ClosedRange<Int>
    ) -> ClosedRange<Int> {
        switch direction {
        case .upward:
            return max(bounds.lowerBound, selectedBounds.lowerBound - 1)...selectedBounds.upperBound
        case .downward:
            return selectedBounds.lowerBound...min(bounds.upperBound, selectedBounds.upperBound + 1)
        }
    }

    static func boundsAfterContracting(
        _ selectedBounds: ClosedRange<Int>,
        expansionDirection: BlockInputVerticalMovementDirection
    ) -> ClosedRange<Int>? {
        guard selectedBounds.lowerBound < selectedBounds.upperBound else {
            return nil
        }
        switch expansionDirection {
        case .upward:
            return (selectedBounds.lowerBound + 1)...selectedBounds.upperBound
        case .downward:
            return selectedBounds.lowerBound...(selectedBounds.upperBound - 1)
        }
    }

    static func boundsAfterDemotingWholeSelection(
        within bounds: ClosedRange<Int>,
        expansionDirection: BlockInputVerticalMovementDirection
    ) -> ClosedRange<Int>? {
        boundsAfterContracting(bounds, expansionDirection: expansionDirection)
    }

    static func focusAfterDemotingWholeSelection(
        within bounds: ClosedRange<Int>,
        expansionDirection: BlockInputVerticalMovementDirection
    ) -> Int? {
        boundsAfterDemotingWholeSelection(within: bounds, expansionDirection: expansionDirection).map {
            expansionDirection == .upward ? $0.lowerBound : $0.upperBound
        }
    }
}

private extension BlockInputVerticalMovementDirection {
    var linearSelectionDelta: Int {
        switch self {
        case .upward:
            return -1
        case .downward:
            return 1
        }
    }
}
