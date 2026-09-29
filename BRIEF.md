# Brief: SwiftStar

**Read this first. Do not re-brainstorm the project.** The design in this file
and in `ROADMAP.md` is settled. Brainstorm *within* a phase; do not reopen the
phase list or the architecture.

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
`ds4-dogfood tui --ndjson --source <project root> --commit HEAD` as a child
process and renders the events that process writes. ds4-engine owns the model
and its memory plan, the tools, the candidate worktree, the session capture and
the evals. SwiftStar owns the window.

The app is a **regular windowed macOS application**: a dock icon, a real main
window, and a standard `Settings` scene on ⌘,. It is not a menu-bar app, and it
has no menu-bar presence at all. There is one surface, the Agent.

## The relationship to DS4 Control

SwiftStar replaces **DS4 Control**, a menu-bar app in
`~/projects/ds4-control` which is being retired. DS4 Control works. This is not
a rescue. The rewrite exists because the app outgrew the menu bar, settings
outgrew a sheet, the single target stopped being testable at its seams (its
suite contains tests that assert on *source text*), and a measurement arrived
that reframed the product (below).

## Clean-room policy: gardened, not blind

**This is a clean slate that gets gardened.** Clean-room means reimplementing
without looking, and doing that here would mean re-earning, by incident, facts
that already cost incidents to learn. The line is drawn between **code** and
**facts**:

- **Code does not cross.** No file, type, or function is copied from
  `ds4-control`. Implementation is written fresh.
- **Facts may cross, with a citation and a fresh test.** A constant, formula,
  wire detail, or empirically discovered key may be transplanted *only* if the
  phase that needs it records where it came from — a ds4-engine source
  location, a committed fixture, or the run that measured it — and pins it with
  a test written here.
- **Tests do not cross either.** A transplanted test pins the old *shape* as
  much as the old behavior. Carry the incident as a sentence in the phase and
  let the fresh implementation write its own test.

The inventory of what is available to garden — and the citation for each fact —
is in `docs/harvest/`. That directory is **evidence, not source**, and it
describes the pre-P28 engine as it was.

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
   Metal reads.
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
   EngineSession  ──stdin──▶ {"kind":"prompt"|"stop"|"quit"}, 0x03
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
  Apply button, session picker or model chooser; each would be a later, separate
  phase.
- **The engine is installed by the user**, not bundled. SwiftStar resolves
  `ds4-dogfood` from the Settings path, then `PATH`, then
  `~/.local/bin/ds4-dogfood`. Model, context size and capture directory are left
  to ds4-engine's defaults. The engine needs a git repository; SwiftStar passes
  the git root of the workspace folder the user picked.
- **Process exit is mapped, not shown raw.** 0 orderly and clean; 1 ended
  without a clean answer (with the stderr tail) or failed; 2 the engine refused
  to start; 130 interrupted. The full mapping is in the spec's revisions.

**Targets.** Three, and the split is what makes the suite fast:

- **`SwiftStarKit`** — no SwiftUI, no IOKit, no `Process`. `EngineWireParser`,
  `EngineEvent`, `EngineTranscript`, `EngineMetricsReducer`, `EngineCommand`
  (executable resolution and argv). Functions of their inputs, tested in
  milliseconds.
- **`SwiftStarAppKit`** — `Process` and pipes but no SwiftUI: `EngineSession`.
  Testable in the integration tier.
- **`SwiftStar`** — the app. Scenes, `EngineController`, the views. Thin,
  because the decisions live in Kit.

**The rule that keeps the split honest: if a test wants to assert on source
text, the thing it is testing is in the wrong target.**

## The engine

**ds4-engine is a sibling project, not part of this repository.** It lives at
`github.com/pauleveritt/ds4-engine`. This repository holds no ds4 C code, no
submodule, and no `ds4-agent` wire dialect. The pre-P28 fork
(`pauleveritt/ds4`, carried as `external/ds4`) and its patch set were retired by
P28; the roadmap's Backlog names what was closed and where the ideas re-home.

What SwiftStar depends on is the protocol, and the protocol is versioned by the
`ready` handshake. Engine-side work — answer quality, tools, memory admission,
evals, new telemetry — is ds4-engine's, and a SwiftStar need for it is filed
there, not patched here.

## Testing

Three tiers, and only one of them is allowed to be slow.

| Tier | What runs | Speed | CI |
|---|---|---|---|
| **Fast** (default `swift test`) | `SwiftStarKit` against fixtures. No model, no network, no subprocess. | seconds | yes |
| **Integration** (marked) | Real `Process`, real files, a fake `ds4-dogfood` replaying a fixture. | seconds | yes |
| **Live capture** (`just capture SCENARIO`) | The real `ds4-dogfood tui --ndjson`, real weights, a fixed prompt. | minutes | never |

**The fast tier's constraint is enforced mechanically**, by a tripwire
(`FastTierGuard`) that fails the build when a default-tier test spawns a process
or opens a socket.

**Fixtures are recorded from the real engine, never hand-authored.**
`fixtures/engine/*.ndjson` is raw stdout of `ds4-dogfood tui --ndjson`, recorded
by `just capture`, with a `provenance.md` naming the ds4-engine commit, model,
context and machine. The fake `ds4-dogfood` (`fixtures/engine/fake-ds4-dogfood`)
replays a fixture and honours `prompt`, `stop`, `quit`, `0x03` and stdin EOF. A
hand-authored fake verifies your beliefs about the wire rather than the wire.
**Every ds4-engine protocol change owes a recapture.**

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
- Docs are Sphinx + MyST + Furo, built through `uv` (`just docs`,
  `just watch-docs`). Python in this repository is the docs build, plus the
  fixture recorder and the fake `ds4-dogfood` under `Tools/` and `fixtures/` (unlinted; the host
  ruff configuration went with P28).
- `ds4-dogfood` comes from ds4-engine, installed with `uv tool install`. A live
  capture needs it on the machine and real weights on disk; it is never part of
  CI.

## Where to start

`ROADMAP.md`, `## Now`, for what is in flight. The cut-over that produced this
design is in the P28 spec and plans; read them before changing the engine seam.
