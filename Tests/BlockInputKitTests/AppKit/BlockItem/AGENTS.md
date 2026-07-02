## Block Item Tests

- Cover item reuse, formatting chrome, markers, horizontal-rule state, and height measurement behavior with mounted item tests when direct model assertions could miss visible AppKit state.
- Keep block-item helpers local to this folder unless other AppKit test scopes need them.
- Mount vertical-geometry assertions with `mountForLayoutTesting` (`BlockInputBlockItemLayoutTesting.swift`): detached item trees solve Auto Layout to their fitting size, not the frame a test sets. Use the shared `textUsedRect(in:)`/`firstTextLineRect(in:)` helpers for rendered-text rects.
