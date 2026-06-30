import AppKit

extension BlockInputView {
    /// Whether the find bar is currently shown.
    public var isFindBarPresented: Bool {
        findBarView != nil
    }

    /// Opens the find bar (or focuses an already-open one), begins find for `initialQuery`, and
    /// makes the bar's query field first responder. No-op when find is disabled.
    public func presentFindBar(initialQuery: String = "") {
        guard findEnabled else {
            return
        }
        if let bar = findBarView {
            bar.focusField(initialQuery: initialQuery.isEmpty ? nil : initialQuery)
            if !initialQuery.isEmpty {
                beginFind(initialQuery: initialQuery)
                bar.updateCount(current: findMatchCount.current, total: findMatchCount.total)
            }
            return
        }
        let bar = makeFindBar()
        installFindBar(bar)
        findBarView = bar
        installFindScrim()
        installFindActiveMatchOverlay()
        beginFind(initialQuery: initialQuery)
        bar.updateCount(current: findMatchCount.current, total: findMatchCount.total)
        bar.focusField(initialQuery: nil)
    }

    /// Dismisses the find bar, clears find state, and returns first responder to the editor.
    public func dismissFindBar() {
        guard let bar = findBarView else {
            return
        }
        let barWasFirstResponder = bar.containsCurrentResponder(in: window)
        bar.removeFromSuperview()
        findBarView = nil
        removeFindActiveMatchOverlay()
        removeFindScrim()
        endFind()
        if barWasFirstResponder {
            window?.makeFirstResponder(self)
        }
    }

    private func makeFindBar() -> BlockInputFindBarView {
        let bar = BlockInputFindBarView()
        bar.onQueryChange = { [weak self] query in
            guard let self else { return }
            self.updateFindQuery(query)
            self.findBarView?.updateCount(current: self.findMatchCount.current, total: self.findMatchCount.total)
        }
        bar.onCommit = { [weak self] in
            guard let self else { return }
            self.findNext()
            self.findBarView?.updateCount(current: self.findMatchCount.current, total: self.findMatchCount.total)
        }
        bar.onCommitPrevious = { [weak self] in
            guard let self else { return }
            self.findPrevious()
            self.findBarView?.updateCount(current: self.findMatchCount.current, total: self.findMatchCount.total)
        }
        bar.onFindNext = { [weak self] in
            guard let self else { return }
            self.findNext()
            self.findBarView?.updateCount(current: self.findMatchCount.current, total: self.findMatchCount.total)
        }
        bar.onFindPrevious = { [weak self] in
            guard let self else { return }
            self.findPrevious()
            self.findBarView?.updateCount(current: self.findMatchCount.current, total: self.findMatchCount.total)
        }
        bar.onToggleReplace = { [weak self, weak bar] in
            guard let self, let bar else { return }
            bar.heightConstraint?.constant = bar.desiredHeight
            self.layoutSubtreeIfNeeded()
        }
        bar.onReplace = { [weak self] replacement in
            guard let self else { return }
            self.replaceCurrentMatch(with: replacement)
            self.findBarView?.updateCount(current: self.findMatchCount.current, total: self.findMatchCount.total)
        }
        bar.onReplaceAll = { [weak self] replacement in
            guard let self else { return }
            self.replaceAllMatches(with: replacement)
            self.findBarView?.updateCount(current: self.findMatchCount.current, total: self.findMatchCount.total)
        }
        bar.onClose = { [weak self] in
            self?.dismissFindBar()
        }
        return bar
    }

    private func installFindBar(_ bar: BlockInputFindBarView) {
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar, positioned: .above, relativeTo: editorChromeView)
        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: bar.desiredHeight)
        bar.heightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            heightConstraint
        ])
    }
}

extension BlockInputView {
    /// Find bar view, when presented. Test-only accessor for the find bar surface.
    var findBarViewForTesting: BlockInputFindBarView? {
        findBarView
    }

    /// Current installed find bar height constraint constant. Test-only accessor.
    var findBarHeightConstantForTesting: CGFloat {
        findBarView?.heightConstraint?.constant ?? 0
    }
}

private extension BlockInputFindBarView {
    func containsCurrentResponder(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder as? NSView else {
            return false
        }
        return responder === self || responder.isDescendant(of: self)
    }
}
