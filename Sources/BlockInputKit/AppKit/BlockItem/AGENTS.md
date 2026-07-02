## Block Item Reuse

- Preserve collection-view reuse assumptions: every item configuration must fully reset text, chrome, selection, drag handles, horizontal-rule state, and callbacks that can survive reuse.
- Reset frontmatter divider visibility and validation warning text attributes during reuse; stale frontmatter chrome must not leak into raw Markdown or paragraph rows.
- Suppress item delegate callbacks during programmatic block-item configuration; visible-row reuse in large documents must not report caret movement or force store index rebuilds.

## Chrome And Metrics

- Keep list marker rendering in `BlockInputMarkerView`; it custom-draws per-line markers so mixed-indent list items do not share one text-field alignment edge.
- Keep code-block background and whole-block selection widths aligned; code surfaces hug content with the AppKit code-surface minimum instead of filling the full row.
- Keep item height measurement cached or otherwise bounded to visible/layout-requested rows.
- Pin permanently-installed hidden chrome (e.g. the rendered-content failure surface) to the row at below-required priority; required pins make every row shorter than the chrome's internal minimum unsatisfiable and force AppKit to break a random constraint.
- When shared row chrome metrics, default insets, or marker alignment change, record and verify the AppKit snapshot suite.
- Keep table rendered and offscreen measurement in parity: column widths, row heights, padding, borders, header styling, alignments, wrapping, and horizontal scroller reserve must match.
- Reset table cells, delegates, hover append controls, row-selection chrome, focus state, tracking areas, and horizontal scroll state during item reuse.
- Keep table hover controls, row-selection chrome, link hit testing, and caret/selection anchors aligned to the horizontally scrolled table document and clipped to the visible viewport.
- Draw host file-chip accessories (`inlineChipAccessoryProvider` → `BlockInputChipAccessory`) into `.kern`-reserved gaps on the chip's hidden `[` (leading) and/or `]` (trailing) — never a `U+FFFC` attachment. Core reserves `reservedWidth`/`trailingReservedWidth` and calls the accessory's `draw`/`drawTrailing` closures (it knows nothing it paints), keeps those glyphs in `BlockInputDelimiterGlyphs`, optionally null-glyphs the label extension (`hidesLabelExtension`, via the shared source-coordinate `chipHiddenExtensionRange`), and extends `chipVisualCharacterRange` both directions so chip background/selection/hover chrome cover the accessories. Height measurement (`applyChipHeightAttributes`) must mirror the same chip font, baseline offset, accessory kerns, adjacent-whitespace kern, and hidden-extension so wrapping matches render. Mirrors the trailing open-icon technique.
