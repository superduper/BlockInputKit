import AppKit

extension BlockInputTableView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        updateAppendControlVisibility(for: convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredAppendTarget = nil
        appendHoverAnchor = nil
        updateAppendControlFrames()
        super.mouseExited(with: event)
    }

    func configureAppendButton(_ button: NSButton, action: Selector, label: String) {
        button.title = "+"
        button.bezelStyle = .circular
        button.isBordered = true
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.target = self
        button.action = action
        button.isHidden = true
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(label)
    }

    func updateAppendControlVisibility(for localPoint: NSPoint) {
        guard isEditable,
              !chromeView.frame.isEmpty,
              !documentView.frame.isEmpty else {
            hoveredAppendTarget = nil
            appendHoverAnchor = nil
            updateAppendControlFrames()
            return
        }
        if keepAppendControlVisibleForButtonHover(localPoint) {
            updateAppendControlFrames()
            return
        }
        let bottomY = chromeView.frame.maxY
        let rightX = rightTableEdgeXInBounds
        let isOverBottom = localPoint.x >= chromeView.frame.minX
            && localPoint.x <= chromeView.frame.maxX
            && abs(localPoint.y - bottomY) <= appendHoverTolerance
        let isOverRight = rightTableEdgeIsVisible
            && abs(localPoint.x - rightX) <= appendHoverTolerance
            && localPoint.y >= chromeView.frame.minY
            && localPoint.y <= bottomY
        hoveredAppendTarget = isOverRight ? .column : (isOverBottom ? .row : nil)
        appendHoverAnchor = appendControlAnchor(for: hoveredAppendTarget, localPoint: localPoint, bottomY: bottomY, rightX: rightX)
        updateAppendControlFrames()
    }

    func updateAppendControlFrames() {
        let buttonSize = NSSize(width: appendControlSize, height: appendControlSize)
        let bottomY = chromeView.frame.maxY
        let rowCenterX = appendHoverAnchor?.x ?? chromeView.frame.midX
        let columnCenterY = appendHoverAnchor?.y ?? chromeView.frame.minY + max(documentView.frame.height, 0) / 2
        appendRowButton.frame = NSRect(
            x: rowCenterX - buttonSize.width / 2,
            y: bottomY - buttonSize.height / 2,
            width: buttonSize.width,
            height: buttonSize.height
        )
        appendColumnButton.frame = NSRect(
            x: rightTableEdgeXInBounds - buttonSize.width / 2,
            y: columnCenterY - buttonSize.height / 2,
            width: buttonSize.width,
            height: buttonSize.height
        )
        appendRowButton.isHidden = !isEditable || hoveredAppendTarget != .row
        appendColumnButton.isHidden = !isEditable || hoveredAppendTarget != .column || !rightTableEdgeIsVisible
    }

    @objc func appendRowButtonClicked(_ sender: Any?) {
        guard isEditable else {
            return
        }
        delegate?.tableViewDidRequestAppendBodyRow(self, from: activeCellPosition)
    }

    @objc func appendColumnButtonClicked(_ sender: Any?) {
        guard isEditable else {
            return
        }
        delegate?.tableViewDidRequestAppendColumn(self, from: activeCellPosition)
    }

    var rightTableEdgeXInBounds: CGFloat {
        chromeView.frame.minX + documentView.frame.width - scrollView.contentView.bounds.origin.x
    }

    var rightTableEdgeIsVisible: Bool {
        rightTableEdgeXInBounds >= chromeView.frame.minX - 0.5
            && rightTableEdgeXInBounds <= chromeView.frame.maxX + 0.5
    }

    private func keepAppendControlVisibleForButtonHover(_ localPoint: NSPoint) -> Bool {
        switch hoveredAppendTarget {
        case .row:
            return appendRowButton.frame.insetBy(dx: -appendHoverTolerance, dy: -appendHoverTolerance).contains(localPoint)
        case .column:
            return appendColumnButton.frame.insetBy(dx: -appendHoverTolerance, dy: -appendHoverTolerance).contains(localPoint)
                && rightTableEdgeIsVisible
        case nil:
            return false
        }
    }

    private func appendControlAnchor(
        for target: AppendTarget?,
        localPoint: NSPoint,
        bottomY: CGFloat,
        rightX: CGFloat
    ) -> NSPoint? {
        switch target {
        case .row:
            return NSPoint(
                x: min(max(localPoint.x, chromeView.frame.minX), chromeView.frame.maxX),
                y: bottomY
            )
        case .column:
            return NSPoint(
                x: rightX,
                y: min(max(localPoint.y, chromeView.frame.minY), bottomY)
            )
        case nil:
            return nil
        }
    }
}
