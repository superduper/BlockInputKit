## Test Organization

- Mirror source areas at the folder level when adding test files: `Core`, `AppKit`, `Markdown`, `Completion`, `Undo`, `SwiftUI`, and `Support`.
- Within `AppKit`, use the nearest topical folder for block item, mutation, performance, reordering, selection, and snapshot coverage.
- Put shared test helpers beside the tests that use them most; promote them only when multiple folders need the same helper.
- For keyboard behavior, cover the document model and the AppKit delegate or mounted-view path when both can diverge.
- For document-store behavior, assert the granular store operation used by the editor, not only the final document snapshot.
- For AppKit snapshot tests, keep light/dark and sizing matrices compact and deterministic; add baselines only for representative UI states.
