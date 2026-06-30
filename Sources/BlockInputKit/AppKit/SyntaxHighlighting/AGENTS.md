## Syntax Highlighting

- Keep the lite highlighter dependency-free and regex-based; do not add external parser or highlighter packages here.
- Keep inline Markdown parsing dependency-free, row-local, and based on UTF-16 `NSRange` values so AppKit formatting, typing attributes, and tests share one scanner.
- Keep highlighting bounded for large visible documents; avoid document-wide work from row height measurement paths.
- Preserve original language hints for Markdown export and clipboard behavior; normalize aliases only for highlighter lookup.
- Keep parsing helpers shared and side-effect free so AppKit rendering, Return shortcuts, and Markdown paths can use the same rules.
- Expose snippet highlighting to downstream targets only through the public `BlockInputCodeHighlighting` facade; keep `BlockInputSyntaxHighlighter` and its color scheme internal.
