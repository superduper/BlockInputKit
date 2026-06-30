import AppKit

extension BlockInputView {
    /// Shared popup-presentation core reused by both the inline `[[` finder and the modal Target note finder.
    ///
    /// Renders the SAME `BlockInputCompletionPopupView` into `layout.container`, installs an event-capture shield, and
    /// wires select/highlight callbacks. The two finders differ only in their layout, popup/capture instances, and
    /// accept callback; everything visual and event-routing here stays identical.
    func presentCompletionPopup(
        _ popup: BlockInputCompletionPopupView,
        captureView: BlockInputCompletionEventCaptureView,
        layout popupLayout: BlockInputCompletionPopupOverlay,
        state: BlockInputCompletionPopupState,
        onSelect: @escaping (BlockInputCompletionSuggestion) -> Void,
        onHighlight: @escaping (Int) -> Void
    ) {
        blockInputWithoutCompletionPopupAnimations {
            let popupContainer = popupLayout.container
            let previousFrame = popup.frame
            popup.appearance = effectiveAppearance

            if popup.superview !== popupContainer {
                popup.removeFromSuperview()
                popupContainer.addSubview(popup, positioned: .above, relativeTo: nil)
            }
            popup.frame = popupLayout.frame
            popup.configure(
                state: state,
                style: completionPopupConfiguration.style,
                onSelect: onSelect,
                onHighlight: onHighlight
            )
            if previousFrame != popup.frame {
                popup.suppressHoverUntilPointerMoves()
            }

            captureView.configure(popup: popup)
            captureView.appearance = effectiveAppearance
            captureView.autoresizingMask = [.width, .height]
            captureView.frame = popupContainer.bounds
            if captureView.superview !== popupContainer ||
                popupContainer.subviews.last !== captureView {
                captureView.removeFromSuperview()
                popupContainer.addSubview(captureView, positioned: .above, relativeTo: nil)
            }

            popup.needsLayout = true
            popup.layoutSubtreeIfNeeded()
            popup.displayIfNeeded()
        }
    }
}
