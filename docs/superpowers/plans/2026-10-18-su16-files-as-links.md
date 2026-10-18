# SU.16 plan: files as links

[Spec](../specs/2026-10-18-su16-files-as-links-design.md), accepted by the
owner on 2026-10-18 with its defaults: a bare name links when unique (D2),
and prose paths don't link (D4). The branch is `su16-file-links`. No GPU.

## Decisions

The spec's D1–D9.

## Tasks

1. **Kit: `FileLink`** (D1, D2, D8), in `Sources/SwiftStarKit/FileLink.swift`.
   - `struct FileLink: Equatable, Sendable { path, url, isEngineCopy }`
   - `struct FileLinkResolver: Sendable`, built from `source`, `worktree`,
     `known` and `exists`. Its `func resolve(_ text: String) -> FileLink?`
     resolves a path.
   - `FileLink.destination(_ path:)` and `FileLink.path(fromDestination:)`
     convert between a path and its `swiftstar-file:` link destination.

   Tests in `FileLinkTests`, over a resolver whose disk is a set:
   - `normalizes`: `./a.swift`, `a.swift:12:3`, and an absolute path under
     the source or the worktree
   - `bareNameLinksWhenUnique`: a duplicate name doesn't link
   - `worktreeCopyWins`: and the checkout's copy opens when the worktree is
     missing
   - `newFileInWorktreeLinks`
   - `outsideTheRootsDoesNotLink`
   - `destinationRoundTrips`: including a path with spaces
2. **Kit: Markdown links** (D7).
   `MarkdownPreprocess.fileLinks(_:resolve:)` rewrites whole inline code
   spans. It leaves alone fences, indented code, prose, and spans already
   in a link.

   Tests in `MarkdownPreprocessTests`:
   - `spanBecomesALink`
   - `codeBlockAndProseStayPlain`
   - `spanInsideALinkStays`
   - `tableCellSpanLinks`
   - `spacedPathIsEncoded`
3. **Engine and controller: the worktree** (D3, D9).
   - `ReceiptReader.worktree(sessionDirectory:) -> URL?`, in
     `Sources/SwiftStarEngine`, reads `receipt.json`'s `worktree_path`.
   - `EngineController` re-reads it at each pause. It clears it on start and
     exit, and keeps `fileLinks: FileLinkResolver?` with a cache that clears
     when its inputs change.

   Tests:
   - `ReceiptReaderTests`: the worktree from both fixture receipts, nil
     when the directory is missing, nil without a receipt
4. **UI** (D4–D7).
   - `TranscriptView` hosts one `.quickLookPreview`. It hands rows a
     `FileLinkAction`, through the environment, that resolves and opens.
   - `ToolCardView` loses its own binding. Its header uses link styling.
   - `MentionsLine` gets one link per attached name.
   - `MarkdownText(_:links:)` sets `linkHandler` before
     `setMarkdownManually`. It opens `swiftstar-file:` links through Quick
     Look and web links in the browser.
   - Answers and narration opt in.

   Checks:
   - Previews rendered, with `source` set to this repository.
   - The gallery: a click on a header, an attachment and an answer's span
     opens Quick Look. The click is posted with a CGEvent, and the panel is
     checked with System Events.
5. **Docs.** ROADMAP, CHANGELOG and both tiers.

## Result
