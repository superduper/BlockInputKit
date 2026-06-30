import AppKit

extension BlockInputView {
    /// Whether find/search is enabled on this editor (Cmd+F, vim `/`, programmatic find).
    /// Embedders such as the vim layer read this to avoid entering search when find is off.
    public var isFindEnabled: Bool {
        findEnabled
    }

    /// Whether the vim search line is currently shown.
    public var isVimSearchLinePresented: Bool {
        vimSearchLineView != nil
    }

    /// Opens the bottom-leading vim search line showing `/` and resets any prior find state.
    /// Highlight-only — no find bar, no scrim, no zoom overlay. No-op when find is disabled.
    public func beginVimSearch() {
        guard findEnabled else {
            return
        }
        endFind()
        let line = installVimSearchLine()
        line.text = VimSearchLine.prefix
    }

    /// Recomputes matches for `query` and re-paints highlights live (incsearch) WITHOUT moving the
    /// caret or installing the scrim/active-match overlay, then updates the line to `/<query>`.
    public func updateVimSearch(_ query: String) {
        guard isVimSearchLinePresented else {
            return
        }
        recomputeFindMatches(query: query)
        vimSearchLineView?.text = VimSearchLine.prefix + query
    }

    /// Jumps the document selection/caret to the active match and reveals it (vim returns to normal
    /// mode with the caret on the match), then shows `<query>  current/total` in the line.
    /// Committing an empty query (bare `/` then Return) just cancels, hiding the line.
    public func commitVimSearch() {
        guard let line = vimSearchLineView else {
            return
        }
        guard !findController.query.isEmpty else {
            cancelVimSearch()
            return
        }
        if let activeMatch = findController.activeMatch {
            selectAndReveal(textRange(forVimMatch: activeMatch))
        }
        line.text = vimSearchLineCountText()
    }

    /// Clears matches/highlights and hides the line. Used by Esc while typing.
    public func cancelVimSearch() {
        endFind()
        removeVimSearchLine()
    }

    /// Clears matches/highlights and hides the line. Used by normal-mode Esc (vim `:noh`).
    public func clearVimSearchHighlight() {
        cancelVimSearch()
    }

    /// Refreshes the line's `current/total` count after `findNext()`/`findPrevious()`, but only when
    /// the vim line is showing — the Cmd+F bar path must stay undisturbed.
    func refreshVimSearchLineCount() {
        guard let line = vimSearchLineView else {
            return
        }
        line.text = vimSearchLineCountText()
    }

    private func textRange(forVimMatch match: BlockInputSearchMatch) -> BlockInputTextRange {
        BlockInputTextRange(blockID: match.blockID, range: match.range)
    }

    /// `<query>  current/total`, or `<query>  no matches` when there are none.
    private func vimSearchLineCountText() -> String {
        let query = findController.query
        let count = findMatchCount
        guard count.total > 0 else {
            return "\(query)  no matches"
        }
        return "\(query)  \(count.current)/\(count.total)"
    }

    @discardableResult
    private func installVimSearchLine() -> BlockInputVimSearchLineView {
        if let existing = vimSearchLineView {
            return existing
        }
        let line = BlockInputVimSearchLineView()
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line, positioned: .above, relativeTo: editorChromeView)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: VimSearchLine.inset),
            line.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -VimSearchLine.inset),
            line.heightAnchor.constraint(equalToConstant: VimSearchLine.height)
        ])
        vimSearchLineView = line
        return line
    }

    private func removeVimSearchLine() {
        vimSearchLineView?.removeFromSuperview()
        vimSearchLineView = nil
    }
}

extension BlockInputView {
    /// Vim search line view, when presented. Test-only accessor.
    var vimSearchLineForTesting: BlockInputVimSearchLineView? {
        vimSearchLineView
    }
}

/// Layout/text constants for the vim search line.
private enum VimSearchLine {
    static let prefix = "/"
    static let inset: CGFloat = 8
    static let height: CGFloat = 20
}
