# SU.15: colored code in tool cards

A small cycle (`docs/sdd.md`): one doc, no spec. The owner, 2026-10-14:
the card showing code (a `read` of a Python file) doesn't colorize.

## Decisions

**D1. A tool card's result is colored by its file's language,** with the
highlighter that already colors answers' code blocks (the Markdown fork's
`CodeHighlighter`, over Highlightr), so both look alike in light and dark.

**D2. Markdown files show as colored raw text,** not rendered: the card
shows what the model read. The owner agreed, 2026-10-14.

**D3. The language comes from the path's extension;** an unknown one, or
no path, stays plain, as now.

## Facts this rests on

- **The preview is plain** monospaced `Text` (`ToolCardView.swift:26-30`).
- **`CodeHighlighter.current.highlight(key:content:language:)`** is public
  and returns `[NSRange: NSColor]`, with the Xcode theme's colors mapped
  to light/dark pairs and an LRU cache (`CodeHighlighter.swift`, the fork
  at `645c583`). Highlightr takes highlight.js language names.
- **`MarkdownText.swift` is the one file that imports the renderer** (its
  header), so the coloring helper lives there too.

## Tasks

### Task 1: the language, in Kit

**Tests first:** `CodeLanguage.forPath`: `.py` python, `.swift` swift,
`.md` markdown, `.toml` ini, `Makefile` makefile, `.txt` and no
extension nil, case-insensitive.

**Files:** `Sources/SwiftStarKit/CodeLanguage.swift`, its test.

### Task 2: the card

**Files:** `MarkdownText.swift` (`CodeColoring.attributed(_:language:)`:
the highlighter's ranges as SwiftUI colors on an `AttributedString`),
`ToolCardView.swift`, a preview per language (Python, Markdown, TOML).

**Steps:** render `ToolCardView`'s previews, light and dark.

### Task 3: close

- `ROADMAP.md`: SU.15's row.
- This plan gains `## Result`; `just lint-docs`, `just test`,
  `just integration`.
