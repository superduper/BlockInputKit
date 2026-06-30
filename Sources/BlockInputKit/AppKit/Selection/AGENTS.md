## Keyboard Selection

- Preserve Shift+Arrow multi-block selection state: keyboard-created block selections use a saved anchor/direction so opposite-direction Shift+Arrow contracts before expanding, and `NSTextView` Shift+Arrow fallbacks must still route through the editor when block selection or a contraction anchor is active.
- Treat Shift+Arrow multi-block selections like one Markdown document: keep partial text endpoints when selection starts or ends inside a block, and exclude the caret block when expanding upward from offset 0 or downward from the block end.
- Treat Shift+Left/Right as one Markdown document too: keep a horizontal selection anchor so opposite horizontal movement contracts first, move from a fully selected block into the first or last character of the adjacent text block, and preserve the adjusted active-edge X for subsequent Shift+Up/Down.
- Preserve Shift+Cmd+Left/Right multi-block line-boundary behavior: move the active edge, not the document-order edge implied by the arrow direction, and keep the resulting active edge as the continuation point for later Shift+Left/Right/Up/Down.
- Keep terminal-newline visual lines in selection and vertical movement helpers; AppKit folds the newline into the previous glyph line, but the editor should still treat the trailing blank line as an in-block line.
- Keep partial multi-selection expansion anchored to the caret X position across blocks. The newly crossed block starts as a partial endpoint and becomes a whole middle block only when selection continues past it.
- Keep row-like keyboard selection ladders shared through `BlockInputLinearSelectionLadder`; table rows and multi-line list item lines must not reimplement promotion, demotion, or edge contraction rules separately.
- Plain Up/Down during multi-selection should cancel to the active edge where selection last extended, not blindly to the document-order start or end.

## Mouse Selection

- Preserve mouse-drag multi-selection parity with Shift+Arrow selection: text-view drags should carry a logical drag range or mouse-down anchor into `BlockInputView`, while the native `NSTextView` range stays collapsed so AppKit gray selection paint cannot overlay custom chrome.
- Commit same-block text-view drags from both `mouseUp(with:)` and the local drag monitor's `.leftMouseUp`; AppKit may deliver the release only through the monitor, and selection must persist after that path.
- Leave modified clicks and multi-clicks on native `NSTextView` mouse tracking; only plain single-click drags should enter custom block-selection tracking.

## Selection Chrome

- Keep partial selection chrome line-fragmented for multiline blocks, especially code blocks; mouse drag and Shift+Arrow paths should both render selected code lines as separate segments instead of one block-sized rectangle.
- Collapse stale native `NSTextView` selections whenever editor-level multi-selection chrome owns the visible selection; inactive gray AppKit selection should not layer over custom blue partial or whole-block chrome.
- Do not disable `NSTextView.isSelectable` to hide native selection paint; keep caret/text-command mechanics alive and suppress gray selection with collapsed ranges plus clear selected-text backgrounds.

## Cancellation And Debugging

- Route new multi-selection cancellation triggers through `BlockInputView+SelectionCancellation`; keyboard cancellation should restore a caret, while mouse-down and reorder-start cancellation should clear chrome without stealing the follow-up event.
- Keep `BlockInputSelectionDebug` opt-in; demo or test hooks may observe it, but they must not enable selection debug output by default.
