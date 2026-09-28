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

**A front-end for one ds4-engine session** (P28, in progress; design in
[`docs/superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md`](docs/superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md)).
Before P28 the app carried a forked C engine as a submodule, host-run tools, a
subagent pool and two eval CLIs; P28 removes all of that, and the old text
survives in git. Edits the engine makes land in the session's
`candidate.diff`; SwiftStar shows the session directory and the
`ds4-dogfood apply <id>` command when a session closes, and applying stays a
terminal step. See [`ROADMAP.md`](ROADMAP.md) for current phase status.

- [`BRIEF.md`](BRIEF.md) — the design. Read this first.
- [`ROADMAP.md`](ROADMAP.md) — phases, backlog.
- [`docs/harvest/`](docs/harvest/index.md) — what the predecessor projects
  proved, kept as evidence rather than as source.
- [`docs/sdd.md`](docs/sdd.md) — how work happens here.

## Requirements

macOS 26 or later, Apple silicon, Swift 6. Install ds4-engine yourself
(`uv tool install` of its wheel) and have model weights on disk, as
ds4-engine's own docs describe. SwiftStar finds `ds4-dogfood` from its
Settings path, then `PATH`, then `~/.local/bin/ds4-dogfood`. The engine needs a
git repository as its source; SwiftStar passes the git root of the workspace
folder you choose.

## Predecessors

SwiftStar replaces **DS4 Control**, a menu-bar app that worked and is being
retired. Implementation is written fresh; facts that cost incidents to learn
cross with a citation and a new test. See `BRIEF.md`, "Clean-room policy."

## License

MIT. See [`LICENSE`](LICENSE).
