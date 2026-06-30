## Syntax Highlighting Tests

- Cover parser behavior separately from AppKit rendering so later UI changes do not obscure range regressions.
- Keep fixture coverage broad but compact; one representative snippet per supported language is enough for the lite highlighter.
- Include large-input guards when changing highlighter rules or regex behavior.
