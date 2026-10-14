# SU.14: the `@` file picker

A small cycle (`docs/sdd.md`): one doc, no spec. Typing `@` in the
composer offers the workspace's files, as ds4-engine's TUI does.

## Decisions

The owner made D1 to D3 on 2026-10-14; D4 to D6 follow from them and the
engine.

**D1. A pop-up above the field,** up to 16 files, while you type after
`@`. ↑/↓ move, Return or Tab inserts, Esc dismisses. Prompt history's
arrows are off while it's open.

**D2. The TUI's fuzzy path match, ported as it is:** tiers 3 (the file name
starts with it), 2 (the name holds it), 1 (the path holds it), 0 (a
subsequence), with runs, word starts and shorter paths scoring higher
within a tier. No content ranking.

**D3. The `mentions` event becomes a line under the prompt:** "Attached
Package.swift, README.md" in secondary text, and each missing name and its
reason in red. It replaces today's system notice and refusal rows.

**D4. The `@word` being typed is the text's last word.** The pop-up is
open while the text ends in `@` and non-space characters; inserting
replaces that word with `@path ` (a trailing space closes it). No cursor
tracking: a `TextField` gives no reliable caret line, and the last word is
where `@` is typed.

**D5. The app lists files itself,** as the TUI does (`relevance.py`):
`git ls-files -z` in the workspace's git root, then the engine's filters
(no dot or skip directories, no binary suffixes, no space or `@` in a
name, at most 2 MiB, at most 20,000 files). Loaded when a session starts
and when the workspace changes. The engine resolves `@path` against the
same root and attaches the file itself.

**D6. Built to be tried in the canvas.** The list is passed to
`ComposerView` through the environment; its "@ picker" preview passes a
fixed list of this repository's paths, so the canvas never runs git, and
the owner can type `@` in the live canvas.

## Facts this rests on

- **The engine expands `@path` in NDJSON prompts** (`tui_cli.py:1043-1052`,
  `mentions.py:44`, ds4-engine `5451cd7d`) and emits `mentions` with
  `attached` and `missing` (each missing entry is "name: reason").
- **No file list on the wire:** NDJSON input takes only `prompt`, `stop`
  and `quit` (`ndjson_process.py:85-109`); there's no `files` subcommand.
- **SwiftStar parses `mentions` today** into a notice or a refusal
  (`EngineWireParser.swift:127-134`).
- **`ProcessRunner.run`** runs a short child with a timeout
  (`ProcessRunner.swift:23`).

## Tasks

### Task 1: Kit

**Files:**
- Create: `Sources/SwiftStarKit/FileMentions.swift`
- Modify: `EngineEvent.swift`, `EngineWireParser.swift`,
  `EngineTranscript.swift` (a `mentions` event and row)
- Tests: `Tests/SwiftStarKitTests/FileMentionsTests.swift` (new), the
  parser and transcript tests

**Interfaces:**
- `FileMentions.activeQuery(in text: String) -> String?`: the characters
  after a final `@word`, or nil.
- `FileMentions.insert(_ path: String, into text: String) -> String`
- `FileMentions.match(_ query: String, in paths: [String], limit: Int = 16) -> [String]`
- `FileMentions.fuzzy(_ fragment: String, _ path: String) -> (tier: Int, score: Double)?`
- `FileMentions.wanted(_ rel: String, size: Int?) -> Bool`, `skipped(directory:)`
- `EngineEvent.mentions(attached: [String], missing: [String])`;
  `TranscriptRow.mentions(attached:missing:)`

**Tests first:** the tiers and ordering against the TUI's examples; the
active query (`"see @Ses"`, `"@"`, `"a@b"`, `"@x "`); insertion; the
filters; the parser's new event; the transcript's row.

### Task 2: the listing

**Files:** `Sources/SwiftStarEngine/WorkspaceFileLister.swift` (new),
`EngineController.swift` (`workspaceFiles`, loaded at start and on a
workspace change), an integration test over a temporary git repository.

### Task 3: the views

**Files:** `ComposerView.swift` (the pop-up, keys, the "@ picker"
preview), `TranscriptRowView.swift` (the mentions line, a preview),
`Components/FontSize.swift` or a new environment value for the file list.

**Steps:** render the previews; the owner tries `@` in the live canvas.

### Task 4: close

- `ROADMAP.md`: SU.14's row.
- This plan gains `## Result`.
- `just lint-docs`, `just test`, `just integration`; the owner's one live
  check in the app: a picked file is attached.
