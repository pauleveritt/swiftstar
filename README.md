# SwiftStar

A macOS front-end for a local model running on Apple silicon.

SwiftStar holds one session of [ds4-engine](https://github.com/pauleveritt/ds4-engine)
open and gives it a window: a prompt, a transcript, tool cards, per-pause
metrics, stop, and quit.

It does no inference and runs no tools itself. It spawns
`ds4-dogfood tui --ndjson` as a child process and renders what that process
reports. ds4-engine owns the model, the memory plan, the tools, the candidate
worktree and the session capture.

## Status

**A working front-end for one ds4-engine session.** It has a prompt, a
transcript with tool cards, per-pause metrics, Stop and Quit, and toolbar
menus for the folder, the model and the context size. Edits the engine makes
land in the session's `candidate.diff`. When a session closes, SwiftStar shows
the session directory and the `ds4-dogfood apply <id>` command; applying stays
a terminal step. [`ROADMAP.md`](ROADMAP.md) has what's in flight. The cut-over
that made it this (P28, 2026-09-28) is in
[`docs/superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md`](docs/superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md).

- [`BRIEF.md`](BRIEF.md) — the design. Read this first.
- [`ROADMAP.md`](ROADMAP.md) — phases, backlog.
- [`docs/history.md`](docs/history.md) — where the pre-P28 record lives (git
  tags), and the phases P28–P32.
- [`docs/sdd.md`](docs/sdd.md) — how work happens here.

## Requirements

macOS 26 or later, Apple silicon, Swift 6.2. UI work uses Xcode 27 for its
previews and `RenderPreview` (see `CLAUDE.md`). Install ds4-engine
yourself (`uv tool install` of its wheel) and have model weights on disk, as
ds4-engine's own docs describe. SwiftStar finds `ds4-dogfood` from its
Settings path, then `PATH`, then `~/.local/bin/ds4-dogfood`. The engine needs a
git repository as its source; SwiftStar passes the git root of the workspace
folder you choose.

## Build and run

```
swift build
just test             # fast tier
just integration      # integration tier, against a fake engine
just app              # assemble .build/SwiftStar.app (then: open .build/SwiftStar.app)
```

If `ds4-dogfood` isn't on `PATH` or in `~/.local/bin`, set its full path in
Settings before launching.

## Predecessors

SwiftStar replaced **DS4 Control**, a menu-bar app that worked but outgrew
the menu bar. Implementation was written fresh; facts that cost incidents to
learn crossed with a citation and a new test. See `BRIEF.md`, "Background."

## License

MIT. See [`LICENSE`](LICENSE).
