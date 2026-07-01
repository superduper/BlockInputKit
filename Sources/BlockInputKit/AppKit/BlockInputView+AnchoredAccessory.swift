import AppKit

/// A host-owned floating accessory pinned to a `(blockID, range)` region of the document. The editor keeps
/// it positioned as the document scrolls and as blocks grow/shrink, clips it to the editor, and hides it when
/// its anchor region scrolls off-screen — so a plugin does not have to wire up its own scroll/frame observers.
///
/// Obtain one from ``BlockInputView/addAnchoredAccessory(_:blockID:range:placement:alignment:gap:)`` and use its
/// ``id`` to update or remove it. The host view manages its own hit-testing (accessories such as buttons must
/// receive clicks), so the editor adds it as-is and never overrides its `hitTest`.
public struct BlockInputAnchoredAccessory {
    /// Vertical placement of the accessory relative to the anchored range's rect.
    public enum Placement {
        /// Position the accessory above the range's rect (in reading order).
        case above
        /// Position the accessory below the range's rect (in reading order).
        case below
    }

    /// Horizontal alignment of the accessory relative to the anchored range's rect.
    public enum HorizontalAlignment {
        /// Align the accessory's leading edge to the rect's leading edge.
        case leading
        /// Center the accessory horizontally on the rect.
        case center
        /// Align the accessory's trailing edge to the rect's trailing edge.
        case trailing
    }

    /// Stable identifier for this accessory, used to update or remove it.
    public let id: UUID
}

/// An accessory view that wants to know the side it actually landed on (after any clip-driven flip), so it
/// can orient a pointer/arrow. Conform your host accessory view to reposition its callout arrow.
@MainActor
public protocol BlockInputAccessoryPlacementAware: NSView {
    func anchoredPlacementDidResolve(_ placement: BlockInputAnchoredAccessory.Placement)
}

/// Backing store for registered anchored accessories, keyed by their handle id.
typealias BlockInputAnchoredAccessoryMap = [UUID: BlockInputAnchoredAccessoryEntry]

/// Stored tracking state for one registered accessory.
///
/// An accessory anchors to EITHER a `(blockID, range)` (single-block) or a SPAN of whole blocks
/// (`spanBlockIDs`); the latter positions against the union of the blocks' full-text rects, so a
/// multi-block region reads as one rectangle instead of one-per-block.
struct BlockInputAnchoredAccessoryEntry {
    weak var view: NSView?
    var blockID: BlockInputBlockID
    var range: NSRange
    var spanBlockIDs: [BlockInputBlockID]   // non-empty ⇒ anchor to the union of these blocks' full-text rects
    var placement: BlockInputAnchoredAccessory.Placement
    var alignment: BlockInputAnchoredAccessory.HorizontalAlignment
    var gap: CGFloat
    var flipsWhenClipped: Bool              // flip to the opposite side when the preferred side lacks room
}

public extension BlockInputView {
    /// Pins `view` to a `(blockID, range)` region and keeps it positioned as the document scrolls and as the
    /// anchored block grows/shrinks. The accessory is added as a subview, positioned relative to
    /// ``rectForRange(_:in:)``, clipped to the editor, and hidden when its region is not visible.
    ///
    /// - Parameters:
    ///   - view: The host-owned accessory view. It is added as-is; the editor never overrides its hit-testing.
    ///   - blockID: The block whose text the accessory is anchored to.
    ///   - range: UTF-16 range within the block's text to anchor against.
    ///   - placement: Whether the accessory sits above or below the range's rect. Defaults to `.below`.
    ///   - alignment: Horizontal alignment relative to the range's rect. Defaults to `.trailing`.
    ///   - gap: Vertical spacing between the range's rect and the accessory. Defaults to `6`.
    /// - Returns: A handle carrying the accessory's `id`, for later ``updateAnchoredAccessoryRange(_:blockID:range:)``
    ///   or ``removeAnchoredAccessory(_:)`` calls.
    @discardableResult
    func addAnchoredAccessory(
        _ view: NSView,
        blockID: BlockInputBlockID,
        range: NSRange,
        placement: BlockInputAnchoredAccessory.Placement = .below,
        alignment: BlockInputAnchoredAccessory.HorizontalAlignment = .trailing,
        gap: CGFloat = 6,
        flipsWhenClipped: Bool = false
    ) -> BlockInputAnchoredAccessory {
        // Clip accessories to the editor bounds once the first one is registered so they can't draw over
        // adjacent chrome (find bar, toolbars) as they track scrolling.
        if anchoredAccessoryEntries.isEmpty {
            clipsToBounds = true
        }
        let id = UUID()
        if view.superview !== self {
            view.removeFromSuperview()
            addSubview(view, positioned: .above, relativeTo: nil)
        }
        anchoredAccessoryEntries[id] = BlockInputAnchoredAccessoryEntry(
            view: view,
            blockID: blockID,
            range: range,
            spanBlockIDs: [],
            placement: placement,
            alignment: alignment,
            gap: gap,
            flipsWhenClipped: flipsWhenClipped
        )
        startObservingBlockGrowthForAnchoredAccessoriesIfNeeded()
        repositionAnchoredAccessories()
        return BlockInputAnchoredAccessory(id: id)
    }

    /// Pins `view` to the region SPANNING several whole blocks, positioning it against the union of the
    /// blocks' full-text rects (so a multi-block region is treated as one rectangle). Same scroll/growth
    /// tracking, clipping, and off-screen hiding as the single-block variant.
    ///
    /// - Parameter blockIDs: The blocks the accessory spans, in document order. An empty array is a no-op
    ///   returning a handle that never positions anything.
    @discardableResult
    func addAnchoredAccessory(
        _ view: NSView,
        spanningBlocks blockIDs: [BlockInputBlockID],
        placement: BlockInputAnchoredAccessory.Placement = .below,
        alignment: BlockInputAnchoredAccessory.HorizontalAlignment = .trailing,
        gap: CGFloat = 6,
        flipsWhenClipped: Bool = false
    ) -> BlockInputAnchoredAccessory {
        if anchoredAccessoryEntries.isEmpty {
            clipsToBounds = true
        }
        let id = UUID()
        if view.superview !== self {
            view.removeFromSuperview()
            addSubview(view, positioned: .above, relativeTo: nil)
        }
        anchoredAccessoryEntries[id] = BlockInputAnchoredAccessoryEntry(
            view: view,
            blockID: blockIDs.first ?? BlockInputBlockID(rawValue: ""),
            range: NSRange(location: 0, length: 0),
            spanBlockIDs: blockIDs,
            placement: placement,
            alignment: alignment,
            gap: gap,
            flipsWhenClipped: flipsWhenClipped
        )
        startObservingBlockGrowthForAnchoredAccessoriesIfNeeded()
        repositionAnchoredAccessories()
        return BlockInputAnchoredAccessory(id: id)
    }

    /// Re-anchors an existing accessory to a new block/range (e.g. when a diff region grows or moves) and
    /// repositions it immediately. No-op if `id` is not a registered accessory.
    func updateAnchoredAccessoryRange(_ id: UUID, blockID: BlockInputBlockID, range: NSRange) {
        guard var entry = anchoredAccessoryEntries[id] else { return }
        entry.blockID = blockID
        entry.range = range
        entry.spanBlockIDs = []
        anchoredAccessoryEntries[id] = entry
        repositionAnchoredAccessories()
    }

    /// Re-anchors an existing accessory to a new block span and repositions it. No-op if `id` is unknown.
    func updateAnchoredAccessorySpan(_ id: UUID, spanningBlocks blockIDs: [BlockInputBlockID]) {
        guard var entry = anchoredAccessoryEntries[id] else { return }
        entry.spanBlockIDs = blockIDs
        entry.blockID = blockIDs.first ?? entry.blockID
        anchoredAccessoryEntries[id] = entry
        repositionAnchoredAccessories()
    }

    /// Removes an accessory: detaches its subview and stops tracking it. No-op if `id` is unknown.
    func removeAnchoredAccessory(_ id: UUID) {
        guard let entry = anchoredAccessoryEntries.removeValue(forKey: id) else { return }
        entry.view?.removeFromSuperview()
        stopObservingBlockGrowthForAnchoredAccessoriesIfIdle()
    }

    /// Removes all registered accessories and stops tracking.
    func removeAllAnchoredAccessories() {
        for entry in anchoredAccessoryEntries.values {
            entry.view?.removeFromSuperview()
        }
        anchoredAccessoryEntries.removeAll()
        stopObservingBlockGrowthForAnchoredAccessoriesIfIdle()
    }
}

extension BlockInputView {
    /// Repositions every registered accessory against live block geometry. Called on register/update, on
    /// scroll/resize (via ``handleDocumentScrollContentBoundsChange()``), and on block growth (via the
    /// document-view frame observer). Entries whose view was released are pruned.
    func repositionAnchoredAccessories() {
        guard !anchoredAccessoryEntries.isEmpty else { return }
        let visibleArea = anchoredAccessoryVisibleArea()
        var releasedIDs: [UUID] = []
        for (id, entry) in anchoredAccessoryEntries {
            guard let view = entry.view else {
                releasedIDs.append(id)
                continue
            }
            positionAnchoredAccessory(view, entry: entry, visibleArea: visibleArea)
        }
        for id in releasedIDs {
            anchoredAccessoryEntries.removeValue(forKey: id)
        }
        if !releasedIDs.isEmpty {
            stopObservingBlockGrowthForAnchoredAccessoriesIfIdle()
        }
    }

    private func positionAnchoredAccessory(
        _ view: NSView,
        entry: BlockInputAnchoredAccessoryEntry,
        visibleArea: NSRect
    ) {
        // Hide when the anchor region is not measurable (block not visible) or has scrolled out of the editor's
        // visible area — leaving it visible would strand it at a stale position.
        guard let rect = anchorRect(for: entry), rect.intersects(visibleArea) else {
            view.isHidden = true
            return
        }
        view.isHidden = false

        let size = view.fittingSize
        // Horizontal placement relative to the rect, then clamped inside the editor with an 8pt margin so the
        // accessory can't run off the side.
        var originX: CGFloat
        switch entry.alignment {
        case .leading:
            originX = rect.minX
        case .center:
            originX = rect.midX - size.width / 2
        case .trailing:
            originX = rect.maxX - size.width
        }
        let margin: CGFloat = 8
        let minX = bounds.minX + margin
        let maxX = bounds.maxX - margin - size.width
        if maxX >= minX {
            originX = min(max(originX, minX), maxX)
        } else {
            originX = minX
        }

        // Resolve the vertical side, flipping to the opposite side if the preferred one has no room in the
        // visible area (e.g. selection near the bottom edge and the accessory would be placed below it).
        let resolved = resolvedPlacement(for: entry, rect: rect, size: size, visibleArea: visibleArea)

        // Vertical placement respects the view's flip so "below" means below-in-reading-order in either space.
        // Deliberately NOT clamped to the visible rect: pinning to the region (and relying on clipping/hiding)
        // keeps the accessory locked to its anchor instead of drifting while scrolling.
        let below = resolved == .below
        let originY: CGFloat
        if isFlipped {
            originY = below ? rect.maxY + entry.gap : rect.minY - entry.gap - size.height
        } else {
            originY = below ? rect.minY - entry.gap - size.height : rect.maxY + entry.gap
        }

        view.frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        // Tell a pointer-drawing accessory which side it actually landed on, so it can orient its arrow.
        (view as? BlockInputAccessoryPlacementAware)?.anchoredPlacementDidResolve(resolved)
    }

    /// The side the accessory should actually use: its preferred side, unless that side lacks room in the
    /// visible area AND the opposite side has room (`flipsWhenClipped`).
    private func resolvedPlacement(
        for entry: BlockInputAnchoredAccessoryEntry,
        rect: NSRect,
        size: NSSize,
        visibleArea: NSRect
    ) -> BlockInputAnchoredAccessory.Placement {
        guard entry.flipsWhenClipped else { return entry.placement }
        // "Room below" in reading order = space between the region's reading-bottom and the visible bottom.
        let need = size.height + entry.gap
        let roomBelow: CGFloat = isFlipped ? visibleArea.maxY - rect.maxY : rect.minY - visibleArea.minY
        let roomAbove: CGFloat = isFlipped ? rect.minY - visibleArea.minY : visibleArea.maxY - rect.maxY
        switch entry.placement {
        case .below:
            return (roomBelow < need && roomAbove >= need) ? .above : .below
        case .above:
            return (roomAbove < need && roomBelow >= need) ? .below : .above
        }
    }

    /// The on-screen rect an accessory anchors to: a single block's range, or the UNION of the full-text
    /// rects of every block in a span (so a multi-block region is one rectangle). Returns nil if none of
    /// the anchor blocks are currently measurable.
    private func anchorRect(for entry: BlockInputAnchoredAccessoryEntry) -> NSRect? {
        guard !entry.spanBlockIDs.isEmpty else {
            return rectForRange(entry.range, in: entry.blockID)
        }
        var union: NSRect?
        for id in entry.spanBlockIDs {
            let length = block(withID: id).map { ($0.text as NSString).length } ?? 0
            let range = NSRange(location: 0, length: max(1, length))
            guard let rect = rectForRange(range, in: id) else { continue }
            union = union.map { $0.union(rect) } ?? rect
        }
        return union
    }

    /// The editor's visible area in its own coordinate space, used to decide when to hide off-screen accessories.
    private func anchoredAccessoryVisibleArea() -> NSRect {
        convert(scrollView.contentView.visibleRect, from: scrollView.contentView)
    }

    // MARK: Block-growth tracking
    //
    // The scroll hook (`onContentBoundsDidChange`) fires on the clip view's bounds change, which reflects scroll
    // offset only — not the document view resizing when a block grows in place. So a separate signal is needed for
    // block growth. The document view (`collectionView`) resizes whenever the flow layout invalidates for a taller
    // block, so observing its `frameDidChangeNotification` is the cleanest existing signal that fires on growth
    // (and shrink). The observer is only installed while ≥1 accessory is registered and torn down when the last is
    // removed, so it costs nothing in the common case. It mirrors the scroll hook in intent.

    func startObservingBlockGrowthForAnchoredAccessoriesIfNeeded() {
        guard anchoredAccessoryFrameObserver == nil, !anchoredAccessoryEntries.isEmpty else { return }
        collectionView.postsFrameChangedNotifications = true
        anchoredAccessoryFrameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: collectionView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repositionAnchoredAccessories()
            }
        }
    }

    func stopObservingBlockGrowthForAnchoredAccessoriesIfIdle() {
        guard anchoredAccessoryEntries.isEmpty, let observer = anchoredAccessoryFrameObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        anchoredAccessoryFrameObserver = nil
    }
}

extension BlockInputView {
    /// Registered anchored accessories, for testing.
    var anchoredAccessoryCountForTesting: Int {
        anchoredAccessoryEntries.count
    }
}
