import AppKit

extension BlockInputView {
    /// 1-based active index and total match count for the find bar; `current` is `0` when empty.
    public var findMatchCount: (current: Int, total: Int) {
        findController.matchCount
    }

    /// Initializes find state for an optional initial query, highlights matches, and
    /// selects/reveals the first match at or after the current caret. Does not present a
    /// visible bar; that is handled separately.
    public func beginFind(initialQuery: String = "") {
        updateFindQuery(initialQuery)
    }

    /// Recomputes matches for `query`, re-highlights visible items, and reveals the active
    /// match (first at or after the current caret, else the first match).
    ///
    /// This runs on every keystroke while the find bar is open, so it must NOT steal first
    /// responder from the find field — otherwise the next character would be typed into the
    /// document. The active match is scrolled into view and shown via the find highlight, but
    /// the document text view is not focused; navigation (`findNext`/`findPrevious`) does focus.
    public func updateFindQuery(_ query: String) {
        let activeMatch = recomputeFindMatches(query: query)
        updateFindScrim()
        if let activeMatch {
            selectAndReveal(textRange(for: activeMatch), preservingFirstResponder: true)
            updateFindActiveMatchOverlay(animated: true)
        }
    }

    /// Recomputes matches for `query`, updates the find controller (anchored to the caret), and
    /// re-paints highlights on visible items — WITHOUT moving the selection/caret or installing the
    /// scrim/active-match overlay. The Cmd+F find bar layers a reveal + scrim on top of this; the vim
    /// search path uses this alone so live typing highlights matches without disturbing the caret.
    /// Returns the resulting active match, if any.
    @discardableResult
    func recomputeFindMatches(query: String) -> BlockInputSearchMatch? {
        refreshDocumentFromStore()
        let matches = BlockInputSearch.matches(in: document, query: query)
        let activeMatch = findController.update(
            query: query,
            matches: matches,
            preferredStart: findPreferredStart()
        )
        applyFindHighlights()
        return activeMatch
    }

    /// Advances the active match with wrap-around, selecting/revealing it.
    /// Returns `false` when there are no matches.
    @discardableResult
    public func findNext() -> Bool {
        advanceActiveMatch(findController.moveToNext())
    }

    /// Moves to the previous match with wrap-around, selecting/revealing it.
    /// Returns `false` when there are no matches.
    @discardableResult
    public func findPrevious() -> Bool {
        advanceActiveMatch(findController.moveToPrevious())
    }

    /// Clears find state and removes match highlights.
    public func endFind() {
        findController.reset()
        clearFindHighlights()
        removeFindActiveMatchOverlay()
        removeFindScrim()
    }

    /// Recomputes matches and re-paints highlights after the document text changed (e.g. the user
    /// edited a matched block), WITHOUT moving the selection or focus — the user is editing, so the
    /// caret must stay put. A match that no longer matches loses its stale highlight; new matches
    /// gain one. No-op when find is not active.
    func refreshFindMatchesAfterDocumentEdit() {
        guard isFindActive else {
            return
        }
        let matches = BlockInputSearch.matches(in: document, query: findController.query)
        findController.update(query: findController.query, matches: matches, preferredStart: nil)
        applyFindHighlights()
        updateFindScrim()
        updateFindActiveMatchOverlay(animated: false)
    }

    /// Whether a find session is active (query set / matches tracked or the bar is open).
    private var isFindActive: Bool {
        findBarView != nil || !findController.query.isEmpty || findController.hasMatches
    }

    /// Selects a text range and scrolls/reveals it, mirroring `focus(blockID:utf16Offset:)`.
    ///
    /// When `preservingFirstResponder` is true the match is scrolled into view without moving
    /// first responder into the matched block — used while typing in the find bar so the query
    /// field keeps focus. When false the matched block is focused (used for find navigation).
    func selectAndReveal(_ textRange: BlockInputTextRange, preservingFirstResponder: Bool = false) {
        applySelection(.text(textRange), notify: true)
        if preservingFirstResponder {
            revealTextSelectionWithoutFocus(textRange)
            return
        }
        restoreVisibleSelection()
        if isEditorFirstResponder {
            publishFocusChange(true)
        }
    }

    /// Scrolls the block containing `textRange` into view and shows its selection chrome without
    /// making any block text view first responder, so the find field keeps keyboard focus.
    ///
    /// `visibleItem(for:)` scrolls the block into view. For table blocks that is all we do — the
    /// find highlight marks the cell — because seating a cell selection would focus the cell text
    /// view and steal focus from the find field. For ordinary text blocks `setSelectedRange`
    /// draws the selection range without making the text view first responder.
    private func revealTextSelectionWithoutFocus(_ textRange: BlockInputTextRange) {
        scrollFindMatchBlockIntoView(textRange.blockID)
        guard let item = visibleItem(for: textRange.blockID) else {
            return
        }
        if block(withID: textRange.blockID)?.kind != .table {
            item.setSelectedRange(textRange.range)
        }
        scrollActiveTextSelectionToVisibleIfNeeded()
    }

    /// Scrolls the document so the match's block is visible, even when it started off-screen in a
    /// long document. Uses the collection view's own item scroll so it works before the lazy
    /// content height is fully realized (when rect-based scrolling can be a no-op).
    private func scrollFindMatchBlockIntoView(_ blockID: BlockInputBlockID) {
        guard let index = index(of: blockID) else {
            return
        }
        let indexPath = IndexPath(item: index, section: 0)
        guard indexPath.item < collectionView.numberOfItems(inSection: 0) else {
            return
        }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
        collectionView.layoutSubtreeIfNeeded()
    }

    private func advanceActiveMatch(_ activeMatch: BlockInputSearchMatch?) -> Bool {
        guard let activeMatch else {
            return false
        }
        applyFindHighlights()
        updateFindScrim()
        updateFindActiveMatchOverlay(animated: true)
        // Navigation driven from the find bar (Return / Shift+Return / Next-Prev buttons) must keep
        // the query field focused so the user can keep cycling and typing. Cmd+G and vim n/N are
        // editor-focused (the field is not first responder), so they keep focusing the block.
        selectAndReveal(textRange(for: activeMatch), preservingFirstResponder: isFindBarFieldFirstResponder)
        refreshVimSearchLineCount()
        return true
    }

    /// Whether the find bar's query field (or its field editor) currently holds first responder.
    private var isFindBarFieldFirstResponder: Bool {
        guard let queryField = findBarView?.queryField,
              let responder = window?.firstResponder else {
            return false
        }
        if responder === queryField {
            return true
        }
        return (responder as? NSTextView)?.delegate === queryField
    }

    private func textRange(for match: BlockInputSearchMatch) -> BlockInputTextRange {
        BlockInputTextRange(blockID: match.blockID, range: match.range)
    }

    private func findPreferredStart() -> BlockInputFindPosition? {
        guard let blockID = activeSearchAnchorBlockID,
              let blockIndex = index(of: blockID) else {
            return nil
        }
        return BlockInputFindPosition(
            blockIndex: blockIndex,
            location: activeSearchAnchorLocation,
            resolveBlockIndex: { [weak self] in self?.index(of: $0) }
        )
    }

    private var activeSearchAnchorBlockID: BlockInputBlockID? {
        switch selection {
        case let .cursor(cursor):
            return cursor.blockID
        case let .text(range):
            return range.blockID
        default:
            return lastFocusedBlockID
        }
    }

    private var activeSearchAnchorLocation: Int {
        switch selection {
        case let .cursor(cursor):
            return cursor.utf16Offset
        case let .text(range):
            return range.range.location
        default:
            return 0
        }
    }
}
