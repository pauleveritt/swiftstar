# Roadmap

> **Planning surface, not the front door.** Where the current phase, the concept
> budget, deferred candidates, and the backlog live. Not where a new reader
> should start — see [`README.md`](README.md) for what this is, and
> [`BRIEF.md`](BRIEF.md) for the settled design.

*Phases group feature cycles. One direction at a time. Tangents go to the
Backlog, not into the current phase.*

## Now

**Phase P0 — Scaffolding. Complete (2026-08-21).** The repository, the docs
toolchain, the Superpowers structure, `BRIEF.md`, this file, and the harvest
briefs in [`docs/harvest/`](docs/harvest/index.md). No Swift yet, deliberately:
P1's output is what P2's fake engine is generated from.

**Phase P1 — The fork, consolidated. Complete (2026-08-22).** `pauleveritt/ds4` exists as a
fork of `antirez/ds4`; the app-required patch set (`--json-events`,
turn-interrupt, status marker, stale-interrupt latch, startup memory plan) is
absorbed from `notatestuser/ds4` and from the local `paul/laguna` work into one
shipped integration branch; a documented command builds `ds4-server` and
`ds4-agent` from the submodule; the fork ledger and `docs/upstream-proposals.md`
are in place; and **two golden captures are taken from the real binaries** — an
SSE capture from `ds4-server` and an NDJSON capture from `ds4-agent`.

This is the phase where the "copy the engine work directly" exception is spent.
It is deliberately first because nothing else can be built against an engine
that does not build, and deliberately *not* combined with the walking skeleton:
its merge conflicts are real and its done-when does not require an app.

**Done when:** one command builds both binaries from a pinned SHA on the shipped
integration branch; the ledger has a row per divergence naming what would retire
it; **both** golden captures are committed — SSE from `ds4-server` for chat,
NDJSON plus its timestamp sidecar from `ds4-agent` — and the
recapture-on-submodule-bump rule is written down where a future rebase will
find it.

**How P1 captures, given that no Swift exists yet.** `swiftstar-drive` arrives at
P5, so P1's bootstrap captures are taken by driving the real binaries directly
with a throwaway line-stamping script. The verbatim-raw rule still applies: the
wire is stored byte-for-byte, and receive times go in a sidecar. The script is
throwaway by design — P5 replaces it, and from P5 onward `swiftstar-drive` is
the only sanctioned source of a fixture.

## Concept budget

*Every term below is a cost against the reader's ability to hold the design in
mind. Checked at the end of each phase; a term earns its place by naming
something the design actually needs, not by being convenient shorthand.*

Seed terms, to be defined in this repository's own words when the phase that
needs each one lands: **patch set**, **shipped integration**, **variant**,
**feasibility**, **handoff packet**, **candidate ref**. Defined so far (P2):

- **seam** — the spawned-child-plus-wire boundary between the app and the engine.
- **wire** — the byte stream on that seam (P2: SSE from `ds4-server`).
- **capture** — a byte-for-byte recording of a wire, stored with a timestamp sidecar.
- **fixture** — a committed capture used by tests.

## Phases

| # | Phase | Direction (one sentence) | Status |
|---|---|---|---|
| P0 | Scaffolding | Repository, docs toolchain, brief, roadmap, harvest briefs | **complete** |
| P1 | The fork, consolidated | One command builds `ds4-server` and `ds4-agent` from a pinned SHA on the shipped integration branch, with a ledger and a golden capture | complete (2026-08-22) |
| P2 | It launches and answers | A regular macOS app with a real icon, a window, and a `Settings` scene starts the server and streams one chat turn — with the fast tier, the tripwire, and fake engines generated from P1's captures | complete (2026-08-22) |
| P3 | It can get its weights | Chunked parallel download with bitmap resume across restarts, and a launch that refuses infeasibly with an explanation a person can act on | planned |
| P4 | It shows what the machine is doing | Metrics tab: memory, GPU, CPU, power — led by **absolute** `ctx_used` and prefill throughput, on fixed-width, jitter-proof readouts | planned |
| P5 | Capture is a program, not a lost file | `swiftstar-drive` committed, the capture format fixed, fixtures committed, the wire given a version handshake and timestamps | planned |
| P6 | Diagnostics that can't lie | A deterministic analyzer over captures, with the model only phrasing the findings | planned |
| P7 | Agent mode | Spawn `ds4-agent`, NDJSON transcript, tool cards, workspace grant, shell toggle, interruptible turns | planned |
| P8 | Skills | The Superpowers bootstrap through `-sys`, prefilled once into `sysprompt.kv`, with progressive disclosure | planned |
| P9 | The tool-callback wire | SwiftStar answers tool calls over the same pipe — including a fake app side — and condenses tool results before they enter KV | planned |
| P10 | Isolation | Worktree-isolated dispatch: a handoff packet in, a candidate ref or a receipt out | planned |
| P11 | Subagent pool | Context-isolated subagents sharing one locked engine, ending at the plan's own measurement gate | planned |
| P12 | More models | Laguna XS 2.1 and/or Mellum 2.1 as first-class variants — **neither line has a shipping artifact yet**; see the dependency below | planned |
| P13 | A docs site | Sphinx content and Pages publishing, once there is a reader who isn't the author | planned |

Full done-when criteria live in each phase's own plan under
`docs/superpowers/plans/`, not restated here, to avoid drift between two copies.
That directory is empty today; each plan is written as its phase begins.

### Dependencies worth knowing before planning

- **P9 gates P10.** Worktree isolation and the handoff packet need the host to
  own tool execution. On an observation-only wire the app can only watch the C
  child write files.
- **P9 is the schedule risk.** It is a protocol design, and everything from P10
  on depends on it. A bidirectional wire also needs a fake *app* side; that cost
  belongs to P9 and must not be discovered inside it.
- **P11 and P12 constrain each other.** Sessions with `graph.ssd_streaming`
  set are excluded from the engine's batch path regardless of family, so Laguna
  XS support and subagent isolation cannot both be assumed. Whichever ships
  second inherits the constraint.
- **P12 inherits an unbuilt artifact, not a finished engine.** Both model lines
  are validated against development quants that fit only the development
  machine: Mellum's evidence is all for a ~12 GiB Q8 build, and the mixed
  Q4_K/Q8 artifact the app would actually ship has never been produced, has no
  imatrix run, and needs a new oracle chain because none of the pinned fixtures
  apply to it. Laguna XS is engineering-complete but still owes a real
  constrained-hardware acceptance run. **P12's cost is dominated by producing
  and gating a shipping quant, not by adding a `Variant`** — and a phase that
  budgets for the latter will discover the former. See
  `docs/harvest/engine-lines.md`.
- **P8 degrades rather than blocks.** Superpowers skills carry fallback wording
  for a harness without subagent dispatch, so P8 does not wait on P11 — but it
  must never fabricate a dispatch call.
- **Every submodule bump owes a recapture.** Not a phase; a standing rule. See
  `BRIEF.md`, "The fork."
- **P4 has prior art with results already banked.** The predecessor prototyped
  these dials and learned five things worth more than the widgets — the
  absolute-vs-fraction anchor, fixed-width readouts, rate ratcheting as a wire
  fact, stroked-shape hit-testing, and separate thresholds for memory and
  context. Read
  [`docs/harvest/telemetry-findings.md`](docs/harvest/telemetry-findings.md)
  before planning P4; every one of those behaviors was proven testable as a pure
  function, which is what `SwiftStarKit` is for.

## Backlog

Deferred, each with the condition that reopens it.

- **Workspace isolation** — a dispatched attempt runs in a disposable detached
  git worktree; the outcome is a reviewable candidate ref or a receipt naming
  the refusal; nothing merges and the caller's tree is never touched. *Promoted
  to P10; listed here because its reopen condition (P9 landing) is the thing to
  watch.* Source: `satyrn-engine` phase E3.
- **The handoff packet** — a typed contract carrying task text, the exact
  writable files, the validation command the parent will actually run, and a
  per-file baseline of SHA-256 plus line-ending and mode read from the worktree
  rather than guessed; the worker gets `read`/`write`/`edit` and no `bash`,
  under turn and tool-call budgets, with every mutation revision-checked. *Also
  P10.* Source: `local-ai-pi`, `harness/typed_contract.py` and
  `docs/engine/deliver-candidate.md`. **The lesson travels with it:** a
  contract-blind pre-edit guard duplicating the engine's own check was built and
  then removed, because it refused contract-authorized renames the engine would
  admit. A guard with less information than the authoritative layer is not
  defense in depth.
- **Specialized tool subagents** — reasoning-light, one-command agents (ruff, pyrefly, pytest, sphinx, roadmap admin) that each own a single tool's lifecycle: run it in a non-human JSON mode where one exists, digest the output into something the caller can act on without bloat, and apply the fix when the run says what it is (e.g., a broken test). Budgeted to fit an 8k context on AFM3; because Swift runs the evocation, repeated invocations make the limit a budget rather than a wall. The open question is dispatch — how the orchestrating model+agent decides which specialized agent to call. *Reopens when P11 lands and the pool design can hold a one-command worker; this is a candidate shape for P11's workers, not a phase of its own.* Source: P11 "Subagent pool".
- **The dispatch decision** — what the handoff packet maker must know to route a task, on three axes. **(1) Parallelism:** dependency edges declared by the plan author are authoritative; the maker may additionally *prove* independence from disjoint writable-file sets plus disjoint validation commands, and must refuse when it cannot — file-disjointness is necessary, not sufficient (an API change and its consumer share no file). **(2) Thinking requirement:** a task is delegable to a reasoning-light worker only when acceptance is a machine-checkable predicate, the tool surface is bounded (`read`/`write`/`edit`, no `bash`), and the writable-file set is exact — and thinking is a stage, not a property: "fix the broken test" needs diagnosis (thinking) before the apply is mechanical. **(3) Executor:** whether the packet goes to a full-context worker or to a specialized Swift subagent running one command in its JSON mode (ruff, pyrefly, pytest, sphinx, roadmap admin), with AFM3's 8k as the budget for the latter and repeat evocations for anything longer. The lesson travels with it: the maker enforces declared intent and computes conservative proofs; it never re-derives semantics with less information than the plan author — the same lesson as the removed contract-blind pre-edit guard. *This is P10's routing design; axis 3 is what the "Specialized tool subagents" entry feeds. Reopens when P10 is planned.* Source: P10 "Isolation", the "Specialized tool subagents" backlog entry.
- **An engine-side `--null-model` mode** — the real emitter, instance lock,
  signal handling, and stdout code running against fake weights, so the
  integration tier exercises the actual code instead of our beliefs about it.
  Upstream-bound. *Reopens when the fake tier misses a bug the real binary
  would have caught.*
- **Heterogeneous compute routing** across ANE and GPU, deterministic rules
  first. *Reopens when a role exists whose latency tolerance and energy cost are
  both measured.*
- **Grammar-constrained tool calls.** An `ds4_agent.c` patch, not an
  embedding-only capability. *Reopens when a malformed tool call is observed
  costing a real turn.*
- **Energy-aware pacing** — pace-to-read decoding and watts-aware scheduling via
  a runtime control message. *Reopens when idle or sustained power shows a cost
  worth paying for; the current measurement says idle draw is under 1W.*
- **An embedding spike.** *Reopens only if dynamic Swift-defined per-token logit
  masking becomes critical-path. Nothing else in `SWIFTSTAR.md` requires
  in-process access.*
- **"Swift body, Python brain"** — agent policy in a hot-reloadable uv-managed
  peer process. *Reopens if agent policy starts changing faster than the app
  can ship.* Source: `SWIFTSTAR.md`.
- **A menu-bar extra.** Explicitly declined 2026-08-21. *Reopens only on a
  direct request; the at-a-glance glance is the one thing it was good for.*

## Prior work

Completed phases move here when the roadmap outgrows the front page.

- **P0 — Scaffolding (2026-08-21).** Repository, `.gitignore`, license, docs
  toolchain (uv + Sphinx + MyST + Furo, `just docs` / `just watch-docs`), the
  `docs/superpowers/` structure, `BRIEF.md`, this file, and the harvest briefs.
  The design session that produced them, including the rejected alternatives and
  the adversarial review that corrected two of them, is recorded in
  [`docs/superpowers/specs/2026-08-21-swiftstar-design.md`](docs/superpowers/specs/2026-08-21-swiftstar-design.md).

- **P2 — It launches and answers (2026-08-22).** `SwiftStarKit` (pure: SSE
  parser, server argv builder, supervisor state machine, chat transcript
  reducer, fake-engine source generator) and `SwiftStar` (the SwiftUI app:
  five-tab window, working Chat tab, Settings scene on ⌘,) plus the fast tier
  (tripwire-guarded `swift test`) and the integration tier
  (`SWIFTSTAR_INTEGRATION=1 swift test`) with a fake `ds4-server` compiled from
  P1's `golden.sse`. The app auto-starts the real engine and streams SSE; two
  live-tier bugs the fake tier could not catch (the argv contract — `Process`
  prepends argv[0] — and the metal-source/CWD gotcha) were found and fixed.
  Spec: [`docs/superpowers/specs/2026-08-22-p2-it-launches-and-answers-design.md`](docs/superpowers/specs/2026-08-22-p2-it-launches-and-answers-design.md).

## Workflow

This repository runs on spec-driven development — see [`docs/sdd.md`](docs/sdd.md).
Each phase gets a committed design spec, then an implementation plan, then code.
The default test suite needs no model, no network, and no subprocess; process
behavior lives in a marked integration tier; and anything needing real weights
lives in a live tier that never runs in CI.
