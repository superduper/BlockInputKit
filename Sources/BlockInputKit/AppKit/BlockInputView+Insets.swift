import AppKit

extension BlockInputView {
    /// Visual vertical inset used above and below editor content.
    public internal(set) var editorVerticalInset: CGFloat {
        get {
            (collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.sectionInset.top
                ?? layout.sectionInset.top
        }
        set {
            updateEditorSectionInset(newValue)
        }
    }

    func updateEditorSectionInset(_ verticalInset: CGFloat) {
        let sectionInset = NSEdgeInsets(
            top: verticalInset,
            left: 0,
            bottom: verticalInset,
            right: 0
        )
        layout.sectionInset = sectionInset
        (collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.sectionInset = sectionInset
    }
}
