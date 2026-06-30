import AppKit

extension BlockInputView {
    var progressiveLoadingRowHeight: CGFloat {
        56
    }

    func scheduleProgressivePreloadCheck(requiresMountedPreloadWindow: Bool = true) {
        guard !requiresMountedPreloadWindow || window != nil,
              pendingProgressivePreloadWorkItem == nil,
              documentStoreForNextProgressiveBatchRequest() != nil else {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            pendingProgressivePreloadWorkItem = nil
            if requiresMountedPreloadWindow {
                requestNextProgressiveBatchIfPreloadWindowReached()
            } else {
                requestNextProgressiveBatchIfNeeded()
            }
        }
        pendingProgressivePreloadWorkItem = workItem
        // Let AppKit drain the current scroll/layout burst before a potentially expensive store load starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: workItem)
    }

    /// Starts the next progressive batch when the loading row is visible or close enough to preload.
    func requestNextProgressiveBatchIfPreloadWindowReached() {
        guard window != nil,
              documentStoreForNextProgressiveBatchRequest() != nil,
              isProgressiveLoadingRowVisibleOrWithinPreloadWindow() else {
            return
        }
        requestNextProgressiveBatchIfNeeded()
    }

    func isProgressiveLoadingRowVisibleOrWithinPreloadWindow() -> Bool {
        guard showsProgressiveLoadingRow else {
            return false
        }
        let loadingIndexPath = IndexPath(item: blockCount, section: 0)
        if collectionView.item(at: loadingIndexPath) != nil {
            return true
        }
        guard window != nil,
              let loadingFrame = progressiveLoadingRowFrameFromContentSize() else {
            return false
        }
        return loadingFrame.intersects(progressiveLoadingPreloadRect)
    }

    private var progressiveLoadingPreloadRect: NSRect {
        let visibleRect = collectionView.visibleRect
        guard visibleRect.height > 0 else {
            return visibleRect
        }
        return NSRect(
            x: visibleRect.minX,
            y: visibleRect.minY,
            width: visibleRect.width,
            height: visibleRect.height * 2
        )
    }

    private func progressiveLoadingRowFrameFromContentSize() -> NSRect? {
        guard let layout = collectionView.collectionViewLayout,
              layout.collectionViewContentSize.height > 0 else {
            return nil
        }
        // Avoid asking the layout for offscreen item attributes here; for very large documents
        // that can force extra layout work on the scroll path. The loading row is always last.
        let sectionInset = (layout as? NSCollectionViewFlowLayout)?.sectionInset ?? NSEdgeInsetsZero
        let visibleRect = collectionView.visibleRect
        let loadingY = max(
            layout.collectionViewContentSize.height - sectionInset.bottom - progressiveLoadingRowHeight,
            0
        )
        return NSRect(
            x: visibleRect.minX,
            y: loadingY,
            width: visibleRect.width,
            height: progressiveLoadingRowHeight
        )
    }
}
