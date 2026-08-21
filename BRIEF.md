# Brief: SwiftStar

**Read this first. Do not re-brainstorm the project.** The design in this file
and in `ROADMAP.md` is the output of a design session held on 2026-08-21 and
adversarially reviewed by a second model. Brainstorm *within* a phase; do not
reopen the phase list or the architecture.

## What we are building

**SwiftStar** is a macOS desktop application for running a large language model
locally on Apple silicon. It launches and supervises a local inference engine,
downloads model weights, shows what the machine is doing while the model runs,
provides a chat and an agent, and — this is the part no comparable tool does —
tells you *why* your session got slow, from measurement rather than from
folklore.

It does **no inference**. All inference is delegated to `ds4-server` and
`ds4-agent`, child processes built from a fork of
[antirez/ds4](https://github.com/antirez/ds4) carried as a git submodule.

The app is a **regular windowed macOS application**: a dock icon, a real main
window with tabs, and a standard `Settings` scene on ⌘,. It is not a menu-bar
app, and it has no menu-bar presence at all.

## The relationship to DS4 Control

SwiftStar replaces **DS4 Control**, a menu-bar app in
`~/projects/ds4-control` which is being retired. DS4 Control works. This is not
a rescue.

The rewrite exists because four things changed at once, and each of them is
awkward to retrofit into what DS4 Control became:

1. **The app outgrew the menu bar.** Chat, agent mode, metrics, diagnostics and
   help are window-sized surfaces. DS4 Control is `LSUIElement`/`.accessory`,
   and `WindowChrome.swift` exists solely to flip activation policy so that an
   accessory app can show real windows. That whole class of problem disappears
   when the app is simply a regular app.
2. **Settings outgrew a sheet.** A first-class `Settings` scene with panes is
   the platform answer, and ⌘, should do what ⌘, does everywhere.
3. **The single target stopped being testable.** `DS4Control` mixes SwiftUI,
   IOKit, process spawning, and pure logic in one module, which is why its
   suite contains tests that assert on *source text* (`WindowChromeSourceTests`,
   `MemoryHarnessSourceTests`, `GUIHostOptionSourceTests`). Those tests exist
   because the logic they care about cannot be reached any other way.
4. **A measurement arrived that reframes the product.** See "The finding that
   reframes this app," below.

## Clean-room policy: gardened, not blind

**This is a clean slate that gets gardened.** The distinction is deliberate and
is the same one recorded in `satyrn-engine`'s own brief: clean-room means
reimplementing without looking, and doing that here would mean re-earning, by
incident, facts that already cost incidents to learn.

The line is drawn between **code** and **facts**:

- **Code does not cross.** No file, type, or function is copied from
  `ds4-control`. Implementation is written fresh.
- **Facts may cross, with a citation and a fresh test.** A constant, formula,
  wire detail, or empirically discovered key may be transplanted *only* if the
  phase that needs it records where it came from — a ds4 source location, a
  committed capture, or the harness run that measured it — and pins it with a
  test written here.
- **Tests do not cross either.** A transplanted test pins the old *shape* as
  much as the old behavior, and would quietly drag DS4 Control's API surface
  into a rewrite whose point is to change that surface. Carry the incident as a
  sentence in the phase — "resume must survive a restart mid-chunk; the old
  repo's `DownloadRaceTests` is why" — and let the fresh implementation write
  its own test.

**One exception, and it is not really an exception:** work done in the **ds4 C
engine itself** moves over directly, because it is the same codebase reached
through a submodule rather than a rewrite. It still goes through a roadmap
phase (P1) so that it arrives consolidated and documented rather than
accumulated.

The inventory of what is available to garden — and the citation for each fact —
is in `docs/harvest/`. That directory is **evidence, not source**.

## The finding that reframes this app

On 2026-08-21 a live-measured investigation against the real `ds4-agent` and
Laguna S 2.1 on this hardware found that **per-turn prefill throughput degrades
roughly 7x as a session's accumulated context grows**: ~300–360 tok/s at
`ctx_used` ≈ 3,400, down to ~41–46 tok/s at `ctx_used` ≈ 92,500 — 62% of a
150,000-token session. It is compute-bound, not overhead: the high-context
session averaged **98.0% GPU utilization** against 35.9% for the low-context
one, with CPU under 7% in both. It is **distinct from the prefix cache**, which
the same investigation independently confirmed stays healthy across sustained
growth *and* across a real compaction.

Source: `docs/harvest/telemetry-findings.md`, citing
`2026-08-21-agent-telemetry-findings.md` at `ds4-control` commit `b7cc10a`.

Three consequences bind this project:

1. **Context length is the dial with a real, measured, growing cost curve
   behind it.** Round-trip count and idle draw were both measured and both look
   fine. The metrics surface leads with `ctx_used` and prefill throughput, not
   only with memory and watts. **The degradation tracks *absolute* `ctx_used`,
   not a percentage of the context window** — a distinction earned the hard way
   in the predecessor's prototype, see below.
2. **The diagnostics surface has a concrete first job** — tell the user they
   are at 92K, that prefill is 44 tok/s, that this is ~7x off their own
   session's baseline, and that compaction will not fix it because the prefix
   cache is already healthy.
3. **Anything that keeps context small is a performance feature**, not a
   nicety: cheap fresh sessions, condensing tool results *before* they enter
   KV, and context-isolated subagents.

**Three limits travel with the finding and must not be dropped when it is
quoted.** Compaction was never observed at the everyday ctx 150,000 setting
across two real attempts — only at 32,768. The captures were taken on an idle
machine with no organic think-time, over sessions no longer than ~24.5 minutes.

And the third, which is a design constraint rather than a caveat: **the curve
was measured at one context size, and it tracks absolute tokens.** The
predecessor's first metrics prototype colored a context dial by
`ctx_used / ctx_size` with thresholds shaped from this data — then caught the
error itself: `ctx_size` varies from 256k to 1M by RAM and variant, plus any
user override, so the same percentage means a wildly different absolute token
count. Fraction-anchored thresholds fire too late on a large context and too
early on a small one. **Anchor on absolute `ctx_used`, and re-anchor against
fresh measurement before trusting any threshold far from where it was
measured.**

## Architecture, settled

**The engine seam is a spawned command plus a wire.** SwiftStar never links the
engine. It spawns `ds4-server` (SSE on `/v1/chat/completions`) and `ds4-agent`
(NDJSON on stdout) and supervises them as child processes.

This was reviewed against the opposing design — `SWIFTSTAR.md` in the ds4
repository argues at length for embedding the engine in-process — and the
spawned seam won on the evidence. The capabilities embedding was supposed to
unlock are mostly reachable across the wire with an additive C patch: multiple
cheap sessions (the subagent-pool plan is building exactly that behind the
process boundary), KV snapshot/restore (snapshots are eager serializations to
host RAM, so a wire command moves handles, not payloads), energy pacing (a
runtime control message), and grammar-constrained tool calls (the grammar state
machine is already in C). Embedding's irreducible advantages reduce to dynamic
per-token Swift-defined logit masking and zero-copy logits access, neither on
this app's critical path. Against that, embedding would put a Metal abort or a
wired-limit kill inside the GUI's own process, and would destroy the clean
per-pid memory attribution that made the telemetry investigation possible.

**The wire becomes bidirectional at P9, and that is scheduled, not hoped for.**
As of P2–P8 the wire is observation-only: the C child executes tools and inserts
results into context before the app sees anything. That is acceptable early and
unacceptable forever, because it forecloses tool-result condensation before KV
entry (the best available mitigation for the 7x tax), intra-turn tool
parallelism, per-tool consent, and both isolation items in the Backlog. P9
adds a tool-callback protocol. **A bidirectional wire needs a fake *app* side,
not just a fake engine side** — that cost belongs to P9 and must not be
discovered inside it.

**Targets.** Three, and the split is what makes the suite fast:

- **`SwiftStarKit`** — no SwiftUI, no IOKit, no `Process`. Wire parsers, the
  supervisor state machine as a pure transition function, feasibility math, the
  telemetry analyzer. Functions of their inputs, tested in milliseconds.
- **`SwiftStar`** — the app. Scenes, IOReport collectors, actual spawning,
  the download runner. Thin, because the decisions live in Kit.
- **`swiftstar-drive`** — an executable that composes production types and
  drives the real engine to produce captures. Committed. See below.

**The rule that keeps the split honest: if a test wants to assert on source
text, the thing it is testing is in the wrong target.**

**Surfaces.** One window, five tabs — Chat, Agent, Metrics, Diagnostics, Help —
plus a `Settings` scene with panes. Chat and Agent stay separate: they are
different wires (SSE vs NDJSON), different consent models, and different
products.

**Diagnostics computes deterministically; the model only phrases.** Swift
computes the findings from a capture; the model's only job is turning a
structured finding into a sentence. This follows the recorded result from
`local-ai-pi` that **facts work and rules of conduct do not** — supplying a
computed fact plays to what a small local model is good at, where "analyze this
telemetry and recommend improvements" asks for judgment it does not have and
produces fluent, plausible, unfalsifiable prose. It also makes the whole
surface testable offline against committed captures, with no model and no Mac.

## The fork

`pauleveritt/ds4`, forked from `antirez/ds4`, carried as a submodule at
`external/ds4`.

- **`main`** — pristine upstream mirror, never edited.
- **The patch set** — the app-required engine changes: `--json-events`,
  turn-interrupt, status marker, stale-interrupt latch, startup memory plan,
  and later `--subagent-pool` with worker ids.
- **One shipped integration branch** — the union base carrying every model line
  the app ships a `Variant` for, with the patch set applied. **The submodule
  pins a SHA on this branch and only this branch.** Per-model branches
  (`laguna-xs2.1`, `mellum-2.1-overnight`) are development branches the app never pins; a
  model line enters the shipped integration when, and only when, SwiftStar
  ships a `Variant` for it.

Three policies, inherited from the `paul/laguna` divergence policy because they
already work: rebase rather than merge, so the integration can be rebuilt onto
new upstream in minutes; a **fork ledger** giving every divergence a row saying
why it exists and what would retire it; and **`docs/upstream-proposals.md`**,
the outbound half, which exists so that "upstream-bound" does not quietly become
"carried forever."

**"Strictly additive" is a goal, not a description, and pretending otherwise is
a trap.** `--json-events` and `--subagent-pool` instrument existing decode
loops, interrupt paths, and emitters inside `ds4_agent.c` — a file that took
**50 commits across all branches in the 90 days to 2026-08-21** (42 on `main`
alone). Recompute with
`git log --oneline --all --since='90 days ago' -- ds4_agent.c | wc -l`. The ds4 divergence policy records an
engine-editing branch accumulating "seven textual conflicts and three semantic
collisions that git merges *silently*" in four days. A rebase can therefore
apply cleanly and be semantically wrong. **Golden-fixture recapture against the
real binary is mandatory on every submodule bump.** That rule is the only thing
standing between a clean rebase and a silently broken wire.

## Testing

Three tiers, and only one of them is allowed to be slow.

| Tier | What runs | Speed | CI |
|---|---|---|---|
| **Fast** (default `swift test`) | `SwiftStarKit` against fixtures. No model, no network, no subprocess. | seconds | yes |
| **Integration** (marked) | Real `Process`, real files, the fake engine binaries. | seconds to a minute | yes |
| **Live capture** (`swiftstar-drive`) | Real engine, real weights, real prompts. | minutes to ~25 min | never |

**The fast tier's constraint is enforced mechanically**, by a tripwire that
fails the build when a default-tier test spawns a process or opens a socket.
Without that, "the fast tier is fast" degrades silently over months and the cure
becomes a refactor.

**Fakes are generated from committed golden captures, never hand-authored, and
they validate argv strictly.** A hand-authored fake verifies your beliefs about
the wire rather than the wire: when a rebase changes the emitter, the fake and
the parser drift *together* while every test passes. Generating the fake from a
real capture makes that co-drift impossible.

**What the fake tier structurally cannot catch, stated so it is not
forgotten:** line fragmentation at pipe-buffer boundaries, backpressure from a
full pipe, stderr/stdout interleaving, child death mid-line and SIGPIPE,
instance-lock contention on double launch, realistic cold-load times (so
timeout logic goes untested exactly where it matters), and the real error zoo on
stderr. Two real bugs of precisely this character were found only against the
real binary: the wire carries no timestamps, and `swift test`'s relay of its
`xctest` subprocess's stdout buffers in large chunks when redirected, hiding
progress for minutes even with `fflush`. **An engine-side `--null-model` mode —
the real emitter, lock, and signal code running against fake weights — is the
honest fix and is Backlogged as upstream-bound.**

## Binding rules

1. **Verify, don't assert.** Carry the command that recomputes a number, not
   the number alone.
2. **Every new test must be shown to fail when the behavior it pins is
   broken** — break it, observe the failure, restore. Both predecessor projects
   shipped tests that asserted on source text or on "nothing returned nil" and
   caught nothing.
3. **No source-text assertions, ever.** If a test wants to grep source, move the
   logic to `SwiftStarKit`.
4. **A refusal test has a sibling success test.** Most of this code refuses
   things — infeasible launches, stale downloads, malformed events — and
   refusal is the default outcome of most bugs.
5. **Capture is separate from analysis.** A capture is written to disk before
   anything reads it, and the analyzer runs against the artifact. Every
   analysis defect must be re-diagnosable without re-running a model.
6. **The evidence floor.** No analyzer is done until it has accepted a
   known-good capture and rejected a known-broken one, each asserted by naming
   the fixture.
7. **The wire announces itself — binding from P5**, when the engine patch that
   emits it lands. A version/capability handshake is the first NDJSON line, and
   a mismatch refuses loudly. Before P5 the wire has no handshake, so a parser
   built at P2 must not refuse its absence. `DS4_DIR` lets the app be pointed
   at any engine build, and the parser's forward-compatible `.ignored` fallback
   means a skewed wire otherwise degrades *silently*.
8. **Gardened facts arrive with the phase that needs them**, never in bulk.
   There is no phase called "port Feasibility."

## The trap we are avoiding

DS4 Control is not a cautionary tale — but it drifted in one specific direction
worth naming, because the rewrite can drift the same way. It grew a single
target that could not be tested at its seams, and the suite adapted by testing
what it could reach: source text. Three such test files shipped. The lesson is
not "write better tests"; it is that **a test asserting on source text is a
report that a module boundary is missing**, and the correct response is to move
the logic, not to write the assertion.

The second trap is scale. Both predecessor projects record the same failure:
machinery outgrowing anyone's ability to hold it in mind. Consequences here:
one phase at a time; no machinery ahead of the contract it serves; tangents go
to the Backlog, never into the current phase.

## Practical environment

- Target **macOS 26+**, Swift 6 language mode, SwiftPM only — no Xcode project.
- swift-testing for new tests, not XCTest.
- Docs are Sphinx + MyST + Furo, built through `uv` (`just docs`,
  `just watch-docs`). Python exists in this repository for documentation and
  nothing else.
- The engine submodule lives at `external/ds4`; `DS4_DIR` points a dev build at
  it.
- A live capture needs the real weights on disk and takes minutes; it is never
  part of CI.

## Where to start

`ROADMAP.md`, phase **P1** — the fork, consolidated. Brainstorm P1's details
treating this brief and the phase list as settled. P1's own done-when includes
the **two** golden captures P2's fakes are generated from — an SSE capture from
`ds4-server` for chat and an NDJSON capture from `ds4-agent` for the agent wire
— so it is a real dependency rather than sequencing bureaucracy. They are
different wires and neither substitutes for the other.
