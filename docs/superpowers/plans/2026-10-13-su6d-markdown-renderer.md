# SU.6d: the Markdown renderer

A small cycle (`docs/sdd.md`): one doc, no spec. Part of SU.6's punch list.

## Decisions

**D1. Keep the pinned MarkdownView fork; a native renderer is declined**
(owner, 2026-10-13). Nothing hurts today; the only pull was dependency weight
(seven packages). SwiftUI's `Text` renders inline Markdown only (Apple's
`Text` docs: no lists, block quotes, code blocks or tables), so any native
renderer is ours, and both native options make the transcript worse:

- **Native SwiftUI blocks** (`AttributedString` `.full` → views per
  `PresentationIntent`): no packages, but no syntax colour, and selection
  stops at each block, since `.textSelection` works per `Text`.
- **One AppKit text view** built from Foundation's parse: keeps selection
  across an answer, but no syntax colour, and the most work (TextKit lists
  and tables).

It reopens if the fork breaks on a toolchain bump, a crash traces to it, or
a patch re-base is due (ROADMAP Backlog, Declined).

**D2. The self-test also loads Litext's resource bundle.** Litext reads its
context-menu strings ("Copy", "Select All", "Open Link") through
`Bundle.module`, the lookup that crashed DS4's packaged app for Highlightr and
SwiftMath. The self-test touched only those two, so a missing Litext bundle
would have passed `make-app` and crashed on the transcript's first
right-click. MarkdownView's own bundle holds an unused strings file that no
code reads.

## Tasks

1. `MarkdownSelfTest.runIfRequested()`
   (`Sources/SwiftStarUI/Transcript/MarkdownText.swift`) reads
   `LocalizedText.copy`, which MarkdownView re-exports from Litext, so
   `Package.swift` doesn't change.
   **Proof:** with `Litext_Litext.bundle` moved out of both the `.app` and
   `.build/release` (the fallback path compiled into `Bundle.module`), the
   old self-test printed OK and the new one dies with "unable to find bundle
   named Litext_Litext" (exit 133). With the bundle back, it prints OK.

## Result

**Commit:** this one, on `main`. Suites: 91 fast and 39 integration, all
passing; the `Markdown` preview rendered and was checked.

**Diverged:** the planned `Package.swift` dependency on Litext wasn't needed.
SwiftPM refused a product from a package that isn't a direct dependency, and
`import MarkdownView` already re-exports Litext.
