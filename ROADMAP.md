# Roadmap

> **Planning surface, not the front door.** What's in flight, what's next,
> and the Backlog. Start with [`README.md`](README.md); the settled design is
> [`BRIEF.md`](BRIEF.md), how work runs is [`docs/sdd.md`](docs/sdd.md), and
> closed history is [`docs/history.md`](docs/history.md).

## Now

- **EN.1 is in:** two live GUI checks are owed by the owner, `/rewind 1` and a
  mid-session model-menu switch (see its row).
- **Next:** SU.5 (plan 5a code, then 5b tests), then SU.6 and SU.7.
- **Blocked on the engine:** showing the edited copy of a file (the candidate
  worktree), and more than one window.

## Phase EN: the engine contract

One cycle per ds4-engine landing that SwiftStar catches up to.

| # | Cycle | Direction | Status |
|---|---|---|---|
| EN.1 | Catch up to `5451cd7d` | Drop a saved model the engine no longer offers; show `tool_rejected` as a declined card; honour `relaunch` for `/model`, `/rewind` and `/resume`; dedupe narration and answer if they repeat; fix `just capture` and re-record on the 27B | done 2026-10-13 except two live GUI checks (owner): `/rewind 1` and a mid-session model switch. [spec](docs/superpowers/specs/2026-10-13-en1-engine-catch-up-design.md), [plan and Result](docs/superpowers/plans/2026-10-13-en1-engine-catch-up.md) |

## Phase SU: SwiftUI

| # | Cycle | Direction | Status |
|---|---|---|---|
| SU.1 | SwiftUI modernisation | `@Environment` controller, `.onSubmit` composer, `.defaultScrollAnchor` transcript, closing the last window quits | done 2026-10-03: [spec](docs/superpowers/specs/2026-10-03-su1-swiftui-modernisation-design.md), [plan](docs/superpowers/plans/2026-10-03-su1-swiftui-modernisation.md) |
| SU.2 | Testable view logic | Move view-adjacent logic into Kit, with tests | done 2026-10-03: [spec](docs/superpowers/specs/2026-10-03-su2-testable-view-logic-design.md), [plan](docs/superpowers/plans/2026-10-03-su2-testable-view-logic.md) |
| SU.3 | Preview adoption | A fixture-backed `#Preview` on every view | done 2026-10-04: views moved to the `SwiftStarUI` library so Xcode can preview them. [spec](docs/superpowers/specs/2026-10-03-su3-preview-adoption-design.md), [plan](docs/superpowers/plans/2026-10-03-su3-preview-adoption.md) |
| SU.4 | Xcode-first UI loop | Xcode 27 and its agent as the place UI work happens: feature folders, previewable parts, `RenderPreview` before a UI change is done | done 2026-10-04: [spec](docs/superpowers/specs/2026-10-04-su4-xcode-first-ui-loop-design.md), [plan](docs/superpowers/plans/2026-10-04-su4-xcode-first-ui-loop.md), [handoff](docs/superpowers/research/2026-10-04-su4-handoff-brief.md) |
| SU.5 | Cleanup and test consolidation | Remove dead code, fossils and the audit's bugs; move view logic into Kit; fold tests into tables with shared support | spec accepted 2026-10-13 and revised the same day: [spec](docs/superpowers/specs/2026-10-04-su5-cleanup-and-test-modernisation-design.md), [audit §2–§3](docs/superpowers/research/2026-10-13-engine-catch-up-and-repo-audit.md). Plan 5a (code), then 5b (tests); also EN.1's deferred minors (its plan's Result) |
| SU.6 | UI tweaks | A punch list of small UI fixes and engine information worth showing (below) | not brainstormed |
| SU.7 | Project focus, switching and resume | The project as the window's identity; its past sessions in the sidebar, resumable; quick, deliberate switching between projects | not brainstormed: [options](docs/superpowers/research/2026-10-04-project-focus-options.md). Resume works over `--ndjson` already ([audit §1](docs/superpowers/research/2026-10-13-engine-catch-up-and-repo-audit.md)); more than one window waits on the engine |

### SU.6 punch list

- **Markdown:** a native renderer, or keep the pinned `MarkdownView` fork. A
  native renderer drops 7 packages but needs a block renderer.
- **Metrics:**
  - per-pause deltas, with the cumulative rate labelled "session avg"
  - a prefill rate that leaves out prefix-cache tokens
- **Engine information worth showing:**
  - DFlash and start-up timings: `session.dflash`, `prefix_cache`,
    `candidate_ready`
  - the engine's stderr start notices
  - model sizes from `plan_gib` and `size_bytes`; drop the catalog fields
    the engine never sends
- **Copy:**
  - "Queued" only for rows the engine confirmed
  - the old "agent" wording ("Ask the agent…", the "Agent" title)
- **Native look:** Liquid Glass affordances; `NativeTooltip` checked against
  plain `.help`.
- **The 27B's two texts:** the narration is the full reply and `answer` is
  `finish`'s one-line summary (EN.1, D4). Show the narration as the answer
  body, with the summary under it.
- **Remembering:** the apply command kept across sessions; a first-launch
  workspace, and a saved workspace that no longer exists (seen 2026-10-13: it
  pointed at a deleted worktree, so every start was refused).

## Backlog

Deferred, each with the condition that reopens it.

### Front-end

- **An Apply button.** Applying stays a terminal step:
  `ds4-dogfood apply <id>`. *Reopens if copying that command becomes daily
  friction and the engine offers a machine-readable apply.*
- **An `@` file picker.** The engine's picker lives only in its Textual
  presenter, and the wire has no file list. *Reopens when typing `@path` by
  hand becomes the friction. It needs an app-side listing or the engine
  request below.*
- **Token streaming.** The engine's seam is the pause, never a per-token
  callback. *Reopens only if ds4-engine changes that.*
- **Packaging ds4-engine inside the `.app`.** Today the user installs it
  with `uv tool install`. *Reopens when someone other than the author needs
  to run the app without a terminal.*
- **A shell toggle.** Tool policy is the engine's. *Reopens if ds4-engine
  adds a spawn-time tool-policy flag worth a Settings control.*
- **The catalog loader's pid-reuse window.** There is a small window before
  SIGKILL in which the pid could be reused. *Reopens if seen live.*
- **SU.3's leftovers.** An Xcode Debug run with the memory widget toggling
  is still unverified. The missing fixture-controller `start()` test lands
  in SU.5a. *Reopens: the crash, if a Debug run shows it.*

### Engine requests

Things SwiftStar can't show or do until ds4-engine changes. Raise them
there.

- **The `session` event doesn't report the candidate worktree.** So Quick
  Look opens the checkout's copy, not the edited one.
- **`models --json` sends no `default_model_id`.** So "Engine default"
  can't name the model it means.
- **Prefix-cache hits count as prefilled tokens.** This inflates the
  per-pause prefill rate (`operator_telemetry.py:100-113`).
- **A `files --json` command,** for the `@` picker above.
- **Watch, not a request: the Satyrn rename.** `ds4-dogfood` and the
  `~/.local/state/ds4-engine` paths may be renamed. SwiftStar would need to
  change `EngineCommand.executableName`, and probing both names is the
  likely fix.

Closed 2026-10-13: both were already answered upstream before 2026-10-04,
found by the [audit §1](docs/superpowers/research/2026-10-13-engine-catch-up-and-repo-audit.md).
- **Rejected tool calls emit no event:** they do, as `tool_rejected`
  (TUI.36).
- **`/resume`, `/model` and `/rewind` re-exec in place:** under `--ndjson`
  they are refused with a `relaunch` argv instead (TUI.34).

### Process

- **SU.1's window-close-quits live check covered idle only, not mid-turn.**
  The `quit()` mid-turn path is unit-tested. *Reopens when the GPU is free
  for a live run.*

### Declined

- **A menu-bar extra** (2026-08-21). *Reopens only on a direct request.*
- **A docs site, P14** (2026-10-13). Markdown in the repository is the
  reader surface.

## History

Phase P (P0–P32), its steps and the Backlog it closed are in
[`docs/history.md`](docs/history.md).
