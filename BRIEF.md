# Brief: SwiftStar

**Read this first. Do not re-brainstorm the project.** The design in this file
is settled. Brainstorm *within* a cycle; do not reopen the architecture. New
work opens a named phase in `ROADMAP.md` (`docs/sdd.md`).

**Reopened once, 2026-09-28** (directed by the owner): P28 cut SwiftStar over
from its forked C engine to ds4-engine and rewrote this brief to match; the
earlier text survives in git. The design is in
[`docs/superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md`](docs/superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md),
and its "Revisions after the design review" section supersedes that spec's body.

## What we are building

**SwiftStar** is a macOS desktop application that is a front-end for one held
[ds4-engine](https://github.com/pauleveritt/ds4-engine) session: a prompt, a
transcript, tool cards, per-pause metrics, stop, and quit.

It does **no inference and runs no tools**. It spawns
`ds4-dogfood tui --ndjson --source <project root> --commit HEAD`, adding
`--model-id` and `--context-size` when the user picks them, as a child process
and renders the events that process writes. ds4-engine owns the model
and its memory plan, the tools, the candidate worktree, the session capture and
the evals. SwiftStar owns the window.

The app is a **regular windowed macOS application**: a dock icon, a real main
window, and a standard `Settings` scene on ⌘,. It is not a menu-bar app, and it
has no menu-bar presence at all. There is one surface: the session window.

## Background

SwiftStar replaced **DS4 Control**, a menu-bar app (`~/projects/ds4-control`)
that worked but outgrew the menu bar, and whose single target could only be
tested through assertions on source text. It was written clean-room but
*gardened*: no code or tests crossed, while facts that cost incidents to learn
did, each with a citation and a fresh test here. That rule still holds for any
fact taken from ds4-engine: cite the source location, fixture or run, and pin
it with a test. The pre-P28 harvest inventory is at the `docs-before-slim` tag
([`docs/history.md`](docs/history.md)).

## The finding that reframes this app

On 2026-08-21 a live-measured investigation against the real `ds4-agent` (the
pre-P28 forked engine) and Laguna S 2.1 on this hardware found that **per-turn
prefill throughput degrades roughly 7x as a session's accumulated context
grows**: ~300–360 tok/s at `ctx_used` ≈ 3,400, down to ~41–46 tok/s at
`ctx_used` ≈ 92,500 — 62% of a 150,000-token session. It is compute-bound, not
overhead (98.0% GPU utilization against 35.9% for the low-context session), and
it is **distinct from the prefix cache**, which stayed healthy across sustained
growth and across a real compaction.

Source: `docs/harvest/telemetry-findings.md`, citing
`2026-08-21-agent-telemetry-findings.md` at `ds4-control` commit `b7cc10a`.

What binds this project now:

1. **Context length is the dial with a real, measured, growing cost curve
   behind it.** The metrics surface leads with context used and prefill
   throughput. **The degradation tracks *absolute* `ctx_used`, not a percentage
   of the context window** — `ctx_size` varies by model, RAM and override, so
   the same percentage means a wildly different token count. Anchor any
   threshold on absolute `ctx_used`, and re-anchor against fresh measurement
   before trusting one far from where it was measured.
   The context *display* (ring, colors) is the fraction of the window the
   engine reports; *findings* and quoted thresholds stay absolute `ctx_used`
   tokens.
2. **Metrics are per pause, not live.** ds4-engine's `--ndjson` protocol
   reports no throughput during generation. Each pause emits a `checkpoint`
   snapshot (`prefill_tokens`, `sync_ms`, `eval_count`, `eval_ms`), each
   `answer` carries `context_used` and `context_size`, and `memory` carries GPU
   allocated and budget bytes. SwiftStar computes prefill and generation tok/s
   from those and from nothing else: no process sampling, no IOReport, no
   Metal reads. **The snapshot's timings are session-cumulative** (confirmed
   against ds4-engine's own `json_events.py`, which deltas them for its own
   terminal display), so SwiftStar's rate is a running session average, not
   the most recent pause's instantaneous rate; the status bar and inspector
   label it "avg" accordingly. (Per-pause deltas are SU.6, not yet brainstormed.)
3. **Three limits travel with the finding when it is quoted.** Compaction was
   never observed at the everyday ctx 150,000 setting across two real attempts
   — only at 32,768. The captures were taken on an idle machine with no organic
   think-time, over sessions no longer than ~24.5 minutes. And the curve was
   measured at one context size.

The pre-P28 phases that acted on this finding (a diagnostics analyzer, a
subagent pool, digested tools) were removed with their engine; whether
ds4-engine's own context handling supersedes them is ds4-engine's question.

## Architecture, settled

**The engine seam is a spawned command plus a wire.** SwiftStar never links the
engine. It spawns `ds4-dogfood tui --ndjson` and supervises it as one child
process for the life of a session.

```text
SwiftStar.app ──spawn──▶ ds4-dogfood tui --ndjson --source <root> --commit HEAD
   EngineSession  ──stdin──▶ {"kind":"prompt"|"stop"|"quit"}
   EngineSession  ◀─stdout── ready / input / event / error / close / …
   EngineWireParser (pure) ─▶ EngineEvent ─▶ EngineTranscript, EngineMetricsReducer
```

- **The wire is `--ndjson`, not `--json-events`.** `--json-events` is a
  compatibility shim that imitates `ds4-agent`, reports tools as a path only,
  and could be dropped upstream. `--ndjson` is ds4-engine's own protocol
  (its `docs/tui.md`) and carries the richer telemetry.
- **The wire announces itself.** The first stdout line must be
  `{"kind":"ready","protocol":1}`; anything else ends the session with a
  protocol error naming what was seen. An exit before any stdout line is a start
  refusal, not a protocol error. Unknown event kinds are ignored, so upstream
  can add telemetry without breaking the app.
- **A turn is busy from prompt to `input`.** Tools run between native calls, so
  `native_start`/`native_end` only drive a "generating" sub-state. Stop is
  enabled only while busy, because the engine answers an idle `stop` with an
  error.
- **Edits are not applied by the app.** The engine runs its tools in its own
  candidate worktree and records edits in the session's `candidate.diff`. When a
  session closes SwiftStar shows the session directory and the
  `ds4-dogfood apply <id>` command; applying stays a terminal step. There is no
  Apply button. Earlier conversations are the sidebar's list, from
  `ds4-dogfood sessions --json`; Resume relaunches with `--resume <id>`
  (SU.7). Model and context size are toolbar menus (P29.10): the model list
  comes from `ds4-dogfood models --json`. A model chosen mid-session is sent
  as `/model <id>`, and the engine's relaunch starts a new conversation with
  the files kept (EN.1); idle, a choice is saved for the next start. A
  context size restarts the session. (Refreshed 2026-10-14, SU.17.)
- **The engine is installed by the user**, not bundled. SwiftStar resolves
  `ds4-dogfood` from the Settings path, then `PATH`, then
  `~/.local/bin/ds4-dogfood`. Model and context size default to the engine's
  until the user picks one; the capture directory is always the engine's. The
  engine needs a git repository; SwiftStar passes the git root of the
  workspace folder the user picked.
- **Process exit is mapped, not shown raw.** 0 orderly and clean; 1 ended
  without a clean answer (with the stderr tail) or failed; 2 the engine refused
  to start; 130 interrupted. The full mapping is in the spec's revisions.

**Targets.** Five, and the split is what makes the suite fast:

- **`SwiftStarKit`** — no SwiftUI, no IOKit, no `Process`. The wire
  (`EngineWireParser`, `EngineEvent`), session state (`EngineSessionModel`,
  `EngineTranscript`, `EngineMetricsReducer`), the argv and exit mapping
  (`EngineCommand`, `EngineExit`), the model catalog and toolbar menus
  (`EngineModelCatalog`), and formatting and small helpers (`MetricsFormatting`,
  `ProjectRoot`, …). Functions of their inputs, tested in milliseconds.
- **`SwiftStarEngine`** — `Process` and pipes but no SwiftUI: `EngineSession`,
  `ProcessRunner` and what runs on it (the model, session-list and report
  loaders, the `@` picker's `WorkspaceFileLister`). Testable in the
  integration tier.
- **`SwiftStarUI`** — library: `EngineController`, the views, preview fixtures.
  A library and a product so Xcode can preview it: executable targets of a bare
  package can't be previewed, and Xcode makes schemes only per product.
- **`SwiftStar`** — the app: `@main`, `AppDelegate`, the icon resource. Thin,
  because the decisions live in Kit.
- **`SwiftStarGallery`** — the real window and menus over the preview
  fixtures, with no engine (SU.12): for what the canvas can't vouch for.

**The rule that keeps the split honest: if a test wants to assert on source
text, the thing it is testing is in the wrong target.**

**SwiftMath is accepted, inert weight, not a dependency choice.** It arrives
transitively via the pinned `MarkdownView` fork (`Package.resolved`), not as a
direct `Package.swift` dependency. `MarkdownPreprocess.deLaTeXed` strips all
LaTeX delimiters and maps common commands to plain text/Unicode before
`MarkdownText.swift` hands text to the renderer, so by the time anything
reaches `MarkdownView`'s math path there is no LaTeX left for SwiftMath to
detect — by design (owner decision, 2026-10-04), not an oversight to fix.

## The engine

**ds4-engine is a sibling project, not part of this repository.** It lives at
`github.com/pauleveritt/ds4-engine`. This repository holds no ds4 C code, no
submodule, and no `ds4-agent` wire dialect. The pre-P28 fork
(`pauleveritt/ds4`, carried as `external/ds4`) and its patch set were retired by
P28; `docs/history.md` says where that record lives.

What SwiftStar depends on is the protocol, and the protocol is versioned by the
`ready` handshake. Engine-side work — answer quality, tools, memory admission,
evals, new telemetry — is ds4-engine's, and a SwiftStar need for it is filed
there, not patched here.

## Testing

Three tiers, and only one of them is allowed to be slow.

| Tier | What runs | Speed |
|---|---|---|
| **Fast** (`just test`) | `SwiftStarKit` against fixtures. No model, no network, no subprocess. | seconds |
| **Integration** (`just integration`) | Real `Process`, real files, a fake `ds4-dogfood` replaying a fixture. | seconds |
| **Live capture** (`just capture SCENARIO`) | The real `ds4-dogfood tui --ndjson`, real weights, a fixed prompt. | minutes |

There is no CI; every tier is run by hand.

**The fast tier's constraint is enforced mechanically**, by a grep in
`just test` that refuses `Process(`, `URLSession`, sockets and `posix_spawn` in
`Tests/SwiftStarKitTests`.

**Wire fixtures are recorded from the real engine.** `fixtures/engine/*.ndjson`
is raw stdout of `ds4-dogfood tui --ndjson`, recorded by `just capture`, with a
`provenance.md` naming the ds4-engine commit, model, context and machine. The
exceptions are named there: two refusal fixtures (`bad-handshake`,
`garbage-after-ready`) and `models.json` are hand-written, and some event
payloads in tests are written from engine source until a recapture covers
them. The fake `ds4-dogfood` (`fixtures/engine/fake-ds4-dogfood`) replays a
fixture and honours `prompt`, `stop`, `quit` and stdin EOF. A hand-authored
fake verifies your beliefs about the wire rather than the wire.
**Every ds4-engine change that reaches the wire owes a recapture**, including
payload changes the relay forwards untouched.

**What the fake tier structurally cannot catch, stated so it is not
forgotten:** line fragmentation at pipe-buffer boundaries, backpressure from a
full pipe, stderr/stdout interleaving, child death mid-line and SIGPIPE,
realistic cold-load times, and the real error zoo on stderr. Only the live tier
sees those.

## Binding rules

1. **Verify, don't assert.** Carry the command that recomputes a number, not
   the number alone.
2. **Every new test must be shown to fail when the behavior it pins is
   broken** — break it, observe the failure, restore.
3. **No source-text assertions, ever.** If a test wants to grep source, move
   the logic to `SwiftStarKit`.
4. **A refusal test has a sibling success test.** The parser refuses a bad
   handshake, a malformed line and an unexpected exit; each needs its accepted
   twin.
5. **Fixtures are the evidence floor.** A parser or reducer is done when it has
   accepted a recorded known-good fixture and rejected a known-broken one, each
   asserted by naming the fixture.
6. **The wire announces itself.** `ready` with `protocol == 1` is the first
   line; a mismatch refuses loudly rather than degrading.
7. **Gardened facts arrive with the phase that needs them**, never in bulk.

## The trap we are avoiding

DS4 Control grew a single target that could not be tested at its seams, and the
suite adapted by testing what it could reach: source text. **A test asserting on
source text is a report that a module boundary is missing**, and the correct
response is to move the logic, not to write the assertion.

The second trap is scale, and this project has now lived it. Both predecessor
projects, and then SwiftStar itself through P27, grew machinery — a host tool
layer, a pool, dispatch, repair loops, an eval CLI — that outran anyone's
ability to hold it in mind and duplicated what the engine went on to do itself.
P28 is the correction. Consequences: one phase at a time; no machinery ahead of
the contract it serves; nothing here that duplicates a job ds4-engine does;
tangents go to the Backlog, never into the current phase.

## Practical environment

- Target **macOS 26+**, Swift 6 language mode, SwiftPM only — no Xcode project.
- swift-testing for new tests, not XCTest.
- Docs are plain Markdown read in the repository; there is no docs site (P14
  declined 2026-10-13). Python here is stdlib-only and unlinted: the fixture
  recorder (`Tools/`), the fake `ds4-dogfood` (`fixtures/engine/`), and the
  small inline fakes in `EngineControllerTests.swift`.
- `ds4-dogfood` comes from ds4-engine, installed with `uv tool install`. A live
  capture needs it on the machine and real weights on disk. There is no CI;
  `just test` and `just integration` are run by hand.

## Where to start

`ROADMAP.md`, `## Now`, for what is in flight. The cut-over that produced this
design is in the P28 spec and plans; read them before changing the engine seam.
