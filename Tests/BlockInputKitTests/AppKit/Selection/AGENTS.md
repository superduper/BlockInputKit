## Selection Tests

- Keep mounted tests for Shift+Arrow and mouse-drag selection loops, including collapsed caret or drag anchors at block boundaries, partial selections that touch only one block edge, expansion, contraction back to full text selection, re-expansion, and text-view fallback events such as Shift-style boundary selectors or extra arrow-key flags like `.numericPad`.
- Update `BlockInputMultiSelectionParityTests` whenever either Shift+Arrow or mouse-drag multi-selection behavior changes; it is the guardrail against visual or model drift between input paths.
- Update `BlockInputLinearSelectionLadderTests` whenever table-row or list-line promotion, demotion, or edge contraction semantics change, then add mounted tests for the affected surface.
- Cover native-selection suppression, multiline/code-block selection chrome, terminal-newline visual lines, and same-block text-view drag commit paths with mounted AppKit tests.
