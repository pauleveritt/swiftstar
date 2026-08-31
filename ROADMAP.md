# Roadmap

> **Planning surface, not the front door.** Where the current phase, deferred
> candidates, and the backlog live. Not where a new reader should start — see
> [`README.md`](README.md) for what this is, and [`BRIEF.md`](BRIEF.md) for
> the settled design.

*Phases group feature cycles. One direction at a time. Tangents go to the
Backlog, not into the current phase.*

## Now

A pointer, not a narrative — the detail lives in each phase's own row and its
linked docs. Update this list when what's in flight changes; do not grow it
into a second history of the phase table.

- **In flight:** P24.4, the instrument-reconciliation cleanup cycle — see the
  P24 row.
- **Parked:** Mellum, inactive until 2026-09-05 (Backlog, "Agent architecture
  and process"); P25 cycles 5–6 (live acceptance, SSD streaming), deferred by
  decision — see the P25 row.
- **Unblocked:** the orchestrate-loop generalization arm 4 can resume after
  P24.4's instrument decisions — see the Backlog's "Evaluation and
  measurement" group.
- **Deferred to last:** P18 (`mellum-fixture` benchmark) — see the P18 row.

## Phases

| # | Phase | Direction (one sentence) | Status |
|---|---|---|---|
| P0 | Scaffolding | Repository, docs toolchain, brief, roadmap, harvest briefs | **complete** |
| P1 | The fork, consolidated | One command builds `ds4-server` and `ds4-agent` from a pinned SHA on the shipped integration branch, with a ledger and a golden capture | complete (2026-08-22) |
| P2 | It launches and answers | A regular macOS app with a real icon, a window, and a `Settings` scene starts the server and streams one chat turn — with the fast tier, the tripwire, and fake engines generated from P1's captures | complete (2026-08-22) |
| P3 | It can get its weights | Chunked parallel download with bitmap resume across restarts, and a launch that refuses infeasibly with an explanation a person can act on | complete (2026-08-22) |
| P4 | It shows what the machine is doing | Metrics tab: memory, GPU, CPU, power — led by **absolute** `ctx_used` and prefill throughput, on fixed-width, jitter-proof readouts | complete (2026-08-22) |
| P5 | Capture is a program, not a lost file | `swiftstar-drive` committed, the capture format fixed, fixtures committed, the wire given a version handshake and timestamps | complete (2026-08-22) |
| P6 | Diagnostics that can't lie | A deterministic analyzer over captures, with the model only phrasing the findings | complete (2026-08-22) |
| P7 | Agent mode | Spawn `ds4-agent`, NDJSON transcript and capture-grade turn/tool outcomes, tool cards, workspace grant, shell toggle, interruptible turns | complete (2026-08-22) |
| P8 | Skills | The Superpowers bootstrap through `-sys`, prefilled once into `sysprompt.kv`, with progressive disclosure | complete (2026-08-22) |
| P9 | The tool-callback wire | SwiftStar answers tool calls over the same pipe — including a fake app side — and condenses tool results before they enter KV | complete (2026-08-22) |
| P10 | Isolation | Worktree-isolated dispatch: a handoff packet in, a candidate ref or a receipt out | complete (2026-08-22) |
| P11 | Subagent pool | Context-isolated subagents sharing one locked engine, ending at the plan's own measurement gate | complete (2026-08-23) |
| P12 | Reliable agency | One model, three roles, host-owned structure: a typed packet per phase, bounded tools, real validation, and recovery — measured by writes and a passing acceptance suite, not tool calls | **complete (2026-08-25)** — all three roles evidenced live at least once (decompose closed the same day via P12.5); every number is small-n, none a reliability figure. P12.8's live phase-boundary confirmation and P12.0/P12.7 remain open, non-blocking items |
| P13 | More models | Laguna XS 2.1 and/or Mellum 2.1 as first-class variants — **neither line has a shipping artifact yet**; deferred behind P12 so there is a harness that can actually evaluate a variant | complete (2026-08-25) — verdict: blocked on Mellum's tool-call **initiation** gate. **The broader "competence, not the harness" reading was overturned:** P15 found the action mode harness-addressable, and [P17](docs/superpowers/research/2026-08-26-p17-repair-limit-verdict.md) found the multi-file repair failure was *predominantly a harness defect* (a directive asserting "exactly one file is wrong" on every cell) — with it removed, repair depth stops predicting failure and Mellum edits 15/17. The residual limit is authoring from an implied contract (1/6), not repair depth. Corrected 2026-08-27. **Corrected again 2026-08-29:** the "repair depth stops predicting failure" reading is overturned by the overnight campaign's Block B analysis — see [`2026-08-29-block-b-negative-result-analysis.md`](docs/superpowers/research/2026-08-29-block-b-negative-result-analysis.md) and P26 |
| P14 | A docs site | Sphinx content and Pages publishing, once there is a reader who isn't the author | planned |
| P15 | Host-controlled action mode | The model drafts as text (`#path` + fenced blocks), the host harvests, writes, and verifies — isolating "should I act" from content competence for Mellum-class models; exit is a verdict, not a product | complete (2026-08-25) — verdict: **harness-addressable**; repair 4/4 at 13/13, build 3/9 at 13/13 with 0 tool calls |
| P16 | Repair harness validity | Fix the four defects (round-discard, collection gate, packet budget, withheld phase brief) blocking any real measurement of Mellum's repair competence, driven by a validity-gated `/goal` loop | **demoted, not resumed** — superseded by P17's cheaper fixture-tier answer; `/goal` v1-v3 closed without meeting their goals, see [`goal-ledger.md`](docs/superpowers/research/goal-ledger.md) and [`goal-ledger-v3.md`](docs/superpowers/research/goal-ledger-v3.md) |
| P17 | Repair-limit fixture experiment | Pre-registered fixture-tier experiment answering whether Mellum's multi-file repair failure is a budget, framing, or depth limit; then a follow-on attempt to optimise the repair loop itself | **complete (2026-08-26)** — verdict: predominantly a harness defect (a false "exactly one file" directive), not the model; Mellum 15/17 on editing tasks; the follow-on optimisation attempt (`/goal` v5) retired without a resolvable result — see [`2026-08-26-p17-repair-limit-verdict.md`](docs/superpowers/research/2026-08-26-p17-repair-limit-verdict.md) and [`goal-ledger-v5.md`](docs/superpowers/research/superseded/goal-ledger-v5.md). **Corrected 2026-08-29:** the 15/17 rate does not replicate on new data — see [`2026-08-29-block-b-negative-result-analysis.md`](docs/superpowers/research/2026-08-29-block-b-negative-result-analysis.md) and P26 |
| P18 | `mellum-fixture` benchmark | A small, one-shot fixture benchmark for Mellum: one attempt, a flat 13-requirement oracle, frozen pre-registered manifest, no repair rounds, no self-modifying loop — separate from `swiftstar-agenttest` | **deferred to last (2026-08-27 decision)** — the benchmark runs after the model ladder and the remaining phases ship, validating the final state. **Job changed 2026-08-29:** P18 was scoped to *validate the final state* — implicitly to confirm a settled number. After the Block B overturn it is now the **arbiter of a contested one** (88% -> 68%, with a harness prompt fix landed mid-stream whose effect is unmeasured at real n). It also inherits an obligation nobody had written down: answering the depth question cleanly needs a **`depth-3-easy` fixture** (three files, three easy defects), because the existing `depth-3` uniquely contains the timezone trap, so the 95/63/44 profile is defect identity rather than file count — and no n fixes that. Mellum is INACTIVE until 2026-09-05, so this does not start before then. Design: [`2026-08-27-p18-mellum-fixture-design.md`](docs/superpowers/specs/2026-08-27-p18-mellum-fixture-design.md) |
| P19 | One surface | The Agent is the app: Chat retired (the `ds4-server`/SSE path, `EngineController`, the tab), the ported Agent UI (composer, workspace picker, status bar + rings, message rendering, tool cards), Settings (shell toggle, font-size slider), per-turn summary on bubbles | **landed 2026-08-26** — Chat retirement `f546671`; UI port `ebfc046`; Settings `5d7c1de`; turn summary `8b9710b`; stop-button fix `478d871`. See the [`agent-surface-port verification record`](docs/superpowers/research/2026-08-26-agent-surface-port-verification-record.md) and the [`old-ui element inventory`](docs/2026-08-26-old-ui-element-inventory.md). Reopened and **complete 2026-08-27**: **P19.0** (consulted answer styling, stable-row-ID decision) and **P19.1** (the app shell) — a Tahoe-forward `NavigationSplitView` shell with a real customizable toolbar, collapsible sidebar, Settings moves (pool size, session capture, smart/dumb default, workspace default), one toolbar model choice with the engine lifecycle hidden, a component/region design vocabulary, and the Swift 6 concurrency gates. See the [`P19.1 design`](docs/superpowers/specs/2026-08-27-p19-1-app-shell-design.md) |
| P20 | Delegation in one engine | Subagents without a second process: the app's agent spawns with `--subagent-pool N`; `/chat` (manual → pool-routed → answer surfaced); smart/dumb handoff-packet lever + dumb-mode dispatch refusal; restart-safe pool state | **Closed 2026-08-27** — live validation PASS (1 dispatch + 13/13, 695s, seed-dependent). [Closure verdict](docs/superpowers/research/2026-08-27-p20-closure-verdict.md); spec [2026-08-27-p20-orchestrate-loop-design.md](docs/superpowers/specs/2026-08-27-p20-orchestrate-loop-design.md).<br>**(1) `/orchestrate` coordination loop** (model-driven, one-shot-first per P17's no-repair-loop verdict) — `OrchestrateDirective.swift`, `orchestrate(task:writableFiles:)` replacing `orchestrateStub()`; needed engine divergence #12 (the `dispatch` schema).<br>**(2) Dispatch-preference bootstrap rule** — prefer dispatch once acceptance is machine-checkable; never for watched interactive sessions. [1809 findings](docs/superpowers/research/2026-08-27-1809-prefill-tail-findings.md).<br>**(3) Descoped:** small-ctx workers → P23; two-phase `/spike` → Backlog behind P24.<br>Commits: `00b5d80` `52257b8` `95ac5c3` `2011203` `53b7ee5` `3e07b54` `9efd050`. |
| P21 | Measurable sessions | Telemetry you can act on: live session capture (wire + trace + stderr per spawn under `captures/live/`), the telemetry analyses (heavy-session compaction, spike shell-on findings) | **landed 2026-08-26** — capture `96fcc49`/`4e7cb3a`. See the [`heavy-session findings`](docs/superpowers/research/2026-08-26-heavy-session-telemetry-findings.md) and the [`spike shell-on findings`](docs/superpowers/research/2026-08-26-spike-shell-on-findings.md). Forward: the **DumbImplementer eval** (design around Σsuffix — Σprompt double-counts, so Σcached/Σprompt is not a cache-hit rate), and **expose the wire's `power` field** (already emitted; the parser drops it) as the first step toward the power question. The kind assertions and the DialLogic re-anchor landed 2026-08-27 — the fixture already carries kinds (no recapture needed), and the anchors are re-anchored to the app's 50k (25k/37.5k; critical now reachable). Which P19–P21 ideas have live evidence: the [`2026-08-26 evidence report`](docs/superpowers/research/2026-08-26-evidence-report.md) |
| P22 | More models: Laguna XS + model switching | Laguna XS 2.1 as a first-class, choosable preset at parity with Laguna S — merge the unmerged `p13-laguna-xs-variant` branch (9 commits; its spec `2026-08-26-p13-laguna-xs-variant-design.md` lives on that branch), the completed live acceptance run, XS golden recapture — plus **model switching** (woven in): an "Apply this model" action that stops and re-spawns the agent with the new model, feasibility-/VariantGate-admitted *before* the stop (never kill a working session to switch to an infeasible model), transcript preserved, provenance per-spawn reflects the new model, pool re-spawns with it, switch refused mid-generation. XS is also the natural line for P20's small-ctx workers | **Closed.**<br>**(1) Laguna XS 2.1** — parity with Laguna S, merged 2026-08-27; live acceptance PASS, golden recapture. [Verdict](docs/superpowers/research/2026-08-27-p22-laguna-xs-acceptance-verdict.md), [recapture](docs/superpowers/research/2026-08-28-p22-xs-golden-recapture-verdict.md).<br>**(2) Model switching** ("Apply this model") — admission before stop; live-validated S→XS, an accidental XS→DeepSeek switch proved P25 Cycle 4b's admission denominator. [Verdict](docs/superpowers/research/2026-08-28-p22-model-switching-verdict.md) ([live](docs/superpowers/research/2026-08-28-p22-model-switching-live-validation.md)).<br>**(3) SSD streaming, Laguna line** — S resident at 20.53 GiB (~32.5 GiB saved); DFlash × SSD refused. [Verdict](docs/superpowers/research/2026-08-28-p22-ssd-across-the-line-verdict.md) ([live](docs/superpowers/research/2026-08-28-p22-ssd-across-the-line-live-validation.md)).<br>16 GB acceptance skipped by decision 2026-08-27, unconfirmed. |
| P23 | Wire-level control | Per-turn think on the agent wire (`reasoning_effort`-style) **plus per-worker context for pool workers** (the small-ctx/RLM lever, descoped from P20 2026-08-27 and merged here). The think leg buys correctness and responsiveness — it bounds the observed think-to-the-wall failure and delivers the "fast reply"; its wall-clock ceiling is ~9.3%, so it is **not** a throughput lever. The per-worker-context leg carries the measured speed (4.2x prefill ceiling; ~6.15 GB → ~1.5 GB scratch per worker). One engine patch, **fork-ledger row #14** (P22's SSD widening took #13), one golden recapture. Spec: [`2026-08-28-p23-wire-level-control-design.md`](docs/superpowers/specs/2026-08-28-p23-wire-level-control-design.md) | **Implemented and closed 2026-08-28.** Spec: [design](docs/superpowers/specs/2026-08-28-p23-wire-level-control-design.md); full record: [wire-control research](docs/superpowers/research/2026-08-28-p23-wire-control-research.md).<br>**(1) Per-turn think** — `/quick`, `think_override` cap, `TurnThinkPolicy`; `TurnOutcome.sampler` records the effort actually used.<br>**(2) Per-worker context** — clamped to `[4096, parent]`, `sysprompt-<ctx>.kv`; fork-ledger row #14; golden recapture (also fixed a real ctx-swap data race and a stale `planned_bytes` drift, both traced in the research doc).<br>**Descoped:** warm-prefix routing (D11, stays Backlog); the "toolless" half of `/quick` (busts the KV prefix). **Deferred:** spec test 9 (think-to-the-wall regression) — no local model reproduces visible thinking; see the [repro attempt](docs/superpowers/research/2026-08-28-p23-think-to-the-wall-repro-attempt.md). |
| P24 | Digested first-class tools | P9's deferred condensation-direction attack on prefill-tail cost (measured: one file re-read 31× = 37% of Σsuffix). Deterministic host-owned tools, in cycles: P24.1 windowed reads, P24.2 read-guard retirement, P24.3 run+digest tools, then P24.4 instrument reconciliation. `scout`, policy gating, and model-asks-human remain later ladder work. [Direction and re-scoping](docs/superpowers/research/2026-08-30-p24-direction-and-rescoping.md). | **(1) P24.1** — closed 2026-08-30; 799 tests; repeat rate 1.45→1.00. [Design](docs/superpowers/specs/2026-08-30-p24-1-window-honoring-reads-design.md), [measurement](docs/superpowers/research/2026-08-30-p24-1-window-honoring-after-measurement.md).<br>**(2) P24.2** — guard retired and `.pool` `readCache` removed; re-baselined. [Design](docs/superpowers/specs/2026-08-30-p24-2-read-guard-redecision-design.md).<br>**(3) P24.3 run+digest family** — landed on `main` 2026-08-30: host-owned `test`/`lint`, bounded `bash`, resolver, executor wiring, engine schemas, and tests. Golden recapture and paired-bill measurement remain outstanding.<br>**(4) P24.4** — next: reconcile the refusal-streak corrective and `toolCallBudget` timing between `swiftstar-agenttest` and the app. |

Full done-when criteria live in each phase's own plan under
`docs/superpowers/plans/`, not restated here, to avoid drift between two copies.
Each plan is written as its phase begins. P12's plan is written:
[`2026-08-24-p12-reliable-agency.md`](docs/superpowers/plans/2026-08-24-p12-reliable-agency.md).
P13's design and benchmark record:
[`2026-08-25-p13-mellum-variant-design.md`](docs/superpowers/specs/2026-08-25-p13-mellum-variant-design.md),
[`2026-08-25-p13-mellum-benchmark-record.md`](docs/superpowers/research/2026-08-25-p13-mellum-benchmark-record.md).
P15's plan is written:
[`2026-08-25-host-controlled-action-mode.md`](docs/superpowers/plans/2026-08-25-host-controlled-action-mode.md).

### Dependencies worth knowing before planning

- **P9 gates P10.** Worktree isolation and the handoff packet need the host to
  own tool execution. On an observation-only wire the app can only watch the C
  child write files.
- **P9 is the schedule risk.** It is a protocol design, and everything from P10
  on depends on it. A bidirectional wire also needs a fake *app* side; that cost
  belongs to P9 and must not be discovered inside it.
- **P9 owns the validation cadence, and it has costs to price up front.** Once
  the host executes tools, lint/type/test can run host-side and their findings
  ride back on the triggering tool result rather than costing a tool round of
  their own. Worth roughly one round each — a structural win, *not* the large
  condensation win it is easy to bundle it with. Three costs belong in P9's
  budget rather than being discovered inside it: silence-means-clean needs a
  system-prompt contract a small model may not honor (measurable — count
  model-initiated linter calls in a capture); silent auto-fix breaks `edit`'s
  exact-match on files in the model's active window; and asynchronous findings
  need tree-state provenance to stay actionable. The same window is also where
  **condensation** — P9's own direction — can dispatch to AFM: the ANE is the
  one compute unit that does not contend with Laguna's serialized GPU path, and
  the model is blocked on the tool anyway. Two-stage, matching the diagnostics
  rule already in `BRIEF.md`: CPU clusters deterministically, ANE only phrases. P9 shipped the wire and the deterministic condensation; the cadence's tool half and the ladder now land in **P24** (see the phase row), the ANE half in the ANE watcher tier Backlog entry.
  [`docs/superpowers/research/2026-08-22-p9-host-side-validation.md`](docs/superpowers/research/2026-08-22-p9-host-side-validation.md)
- **Outcome telemetry precedes P10.** The Mellum agent evaluation showed that
  visible prose is not evidence of action: a model can claim files were written
  and tests passed while executing neither. P7's capture-grade turn outcome must
  therefore identify the model/build/sampler and task, token and context use,
  stop reason (EOS, limit, interrupt, timeout, or context-full), and each tool
  lifecycle transition (emitted, parsed, rejected, or executed). P9 adds the
  host-authoritative facts: actual mutations and their paths, command exit
  status/output digest, and whether validation ran. A P10 handoff packet then
  supplies the exact writable-file and validation contract; it must consume
  these facts rather than infer success from the transcript.
- **P11's pool is serialized on Laguna — by family, not by configuration.**
  An earlier version of this bullet framed the batch-path exclusion as an
  ssd_streaming (P11↔P12) interaction. Corrected 2026-08-22 after source
  verification: `ds4_sessions_eval_batch_metal_supported()` excludes
  `DS4_MODEL_FAMILY_LAGUNA` unconditionally, and the fallback is a sequential
  eval loop, so the pool's workers run one at a time on any Laguna variant,
  ssd_streaming or not. The isolation hypothesis survives intact — **its
  mechanism is the context tax, which works sequentially: integrating the
  measured prefill curve, one 131k-token context costs ~2,100s to prefill
  while eight 16k contexts prefilled one after another cost ~500s — up to
  ~4.2x with zero concurrency, an upper bound in the perfectly-decomposable
  limit.** This is the RLM pattern (recursive sub-queries over slices, root
  context kept small; see the Backlog entry), and it is the finding P11 is
  built on. P11's measurement gate must not expect a parallel-throughput win,
  and its memory math must budget ~6.1 GB of per-session GPU scratch that the
  engine's own `planned_bytes` omits. Constraints, arithmetic, and recompute
  commands:
  [`docs/superpowers/research/2026-08-22-p11-engine-constraints-and-corrections.md`](docs/superpowers/research/2026-08-22-p11-engine-constraints-and-corrections.md).
- **P3's feasibility gate inherits an engine under-report.** The gate is
  arithmetic on the engine's `planned_bytes` — the right design — but on
  Laguna that number omits the ~6.1 GB session scratch `laguna_graph_alloc`
  actually reserves (the estimator computes single-row scratch; the committed
  `golden.ndjson` `ready` events carry the under-report verbatim:
  `scratch_bytes: 784752`). A launch clearing the gate by less than ~6.1 GB
  will be admitted and then exceed the plan. Fix direction is upstream (the
  estimator's Laguna branch multiplies by `prefill_cap` rows) via
  `docs/upstream-proposals.md`; until then the correction term is a documented
  constant, not a re-derived mirror. Same research note as above.
- **P5 should capture the agent's `--trace` channel; P6 needs it.**
  Compaction's rebuild statistics (`old`, `new`, `tail_start`, `tail`) are
  deliberately suppressed on the `--json-events` wire but already emitted via
  `agent_trace()` — no new engine patch required. If P5 fixes the capture
  format without a trace sidecar, P6 re-opens the format to answer "would
  compaction help" (the diagnostics surface's first job) from recorded fact.
- **P13 inherits an unbuilt artifact, not a finished engine.** *(Was P12 before
  the 2026-08-24 reframe; the variant work moved to P13.)* Both model lines
  are validated against development quants that fit only the development
  machine: Mellum's evidence is all for a ~12 GiB Q8 build, and the mixed
  Q4_K/Q8 artifact the app would actually ship has never been produced, has no
  imatrix run, and needs a new oracle chain because none of the pinned fixtures
  apply to it. Laguna XS is engineering-complete but still owes a real
  constrained-hardware acceptance run. **P13's cost is dominated by producing
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
- **P4's telemetry data lives on the agent wire, not the chat wire.** The
  metrics tab's lead numbers — absolute `ctx_used` and prefill throughput — are
  the `ds4-agent --json-events` `status`/`ready` events, already shipped in the
  fork and already captured in `fixtures/agent/golden.ndjson` (1053 `status`
  and 7 `ready` events, plus `text`/`think`/`tool`). The chat wire
  (`ds4-server` SSE) carries none of it. P4 therefore ships **fixture-driven**:
  the parser and widgets are built and tested against `golden.ndjson` in the
  fast tier — no engine, no model, no subprocess — while the live engine stays
  `ds4-server` for chat. The live wiring — the app's engine process emitting
  real `status`/`ready` — was to land with P7's `ds4-agent` migration, which is
  where the agent's safety surface (workspace grant, shell toggle) is designed
  and where two ~48 GiB model loads stop being a constraint. **Corrected
  2026-08-22 (P7 close):** the live metrics wiring did *not* land with P7 — the
  P7 phase row never included it, and P7's plate carried the consent patch, the
  D12 outcome wire, two fixtures, and a new Agent tab; Metrics/Diagnostics stay
  fixture-driven until a later phase (the spec's D9 records the deviation).
  **P4 must not spawn `ds4-agent` live** ahead of that migration. See
  [`docs/superpowers/research/2026-08-22-p4-sequencing-findings.md`](docs/superpowers/research/2026-08-22-p4-sequencing-findings.md).

## Backlog

Deferred, each with the condition that reopens it. Grouped for scanning; a
group's order is not a priority order.

### Retired / landed

- **~~Chat as a separate surface~~ — RETIRED 2026-08-26 by product decision.**
  One surface: the Agent. Retire the Chat tab, the `ds4-server`/SSE wire, and
  `EngineController`; the app owns one `ds4-agent` process, one model load.
  Chat's use case survives as a toolless agent turn with per-turn think
  control. *Reopens as: its own phase — remove the Chat surface and fold a
  no-think "quick reply" mode into the Agent, with `reasoning_effort`-style
  per-turn control on the agent wire (additive engine patch, fork-ledger
  row).*

- **~~Phase-level recovery~~ — LANDED as P12.8 (2026-08-25); live confirmation
  arrived 2026-08-26, and it is bad news, not good.** The wiring shipped
  (`commitForRepair`, `adoptRepairedPhase`, `PhaseRepair`, build-loop
  integration; deterministic tier green). The overnight Mellum matrix fired
  phase-level repair in 38 of 38 cells, but "phase N: repaired → continues to
  acceptance" still has not been observed: the retry-on-receipt fix below
  (`953d05a`) did not make repair cumulative, so 17 of those 38 cells
  exhausted the two-round budget with `head` discarded each round and never
  reached acceptance. **Cumulative rounds landed in P16 (`db7c914`)** —
  `RepairLoop` now commits a `.validationFailed` round and advances `head`
  (`RepairLoop.swift:288`), pinned by
  `RepairLoopTests.validationFailedRoundWorkSurvivesIntoNextRound`. The
  "phase N: repaired -> continues to acceptance" observation is still owed. See
  [`2026-08-26-overnight-80-cell-verdict.md`](docs/superpowers/research/2026-08-26-overnight-80-cell-verdict.md).
  No verdict record written. *Reopens as: land recommendation 1 from that
  findings doc (cumulative rounds) and re-attempt.*

- **~~`RepairLoop` exits on every receipt, including `validationFailed`~~ —
  FIXED (2026-08-25, `953d05a`).** `.validationFailed` now refreshes `lastGrade`
  from the real `ValidationResult` and retries within the existing
  `maxCandidateRounds` budget (no new parameter); every other receipt keeps the
  immediate-exit behavior. Fable-reviewed, approved, two non-blocking notes
  filed below. Shared machinery — applies to all three `RepairLoop` callers
  (P12.4, P12.8, P15), not just the P12.8 case that surfaced it. **Half-fixed,
  corrected 2026-08-26:** the retry itself works, but the round is not
  cumulative — see the escalated "Retry-round evidence coherence" entry
  (Agent architecture and process), no longer a hypothetical.

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

### Agent architecture and process

- **Mellum is INACTIVE until 2026-09-05 (2026-08-29 decision).** No Mellum
  measurement, tuning, or fixture work for one week — the line is parked, not
  cancelled. Why: 2026-08-29 overturned P17's 15/17 (real editing rate ~68%
  pooled; the flat-depth-profile claim is dead — see
  [`2026-08-29-block-b-negative-result-analysis.md`](docs/superpowers/research/2026-08-29-block-b-negative-result-analysis.md)),
  which leaves Mellum's competence **contested rather than settled** — and a
  full day of arms chasing it returned mostly harness and engine defects
  rather than model facts. Parking it stops that loop. **What this defers
  with it:** the `RepairLoop` zero-heading abort (its only validation surface
  is the Mellum fixture tier — see "Smaller items parked with it" below),
  the "talks itself out of the diagnosis" probe, and the two data-integrity
  flags — both in the Backlog's "Evaluation and measurement" group — none
  blocked on anything else. **What it does not touch:** Laguna S work, P24,
  P25. **When it reopens, P18's job has changed** — see the P18 row. *Reopens
  2026-09-05, or sooner by explicit decision.*

- **Shell toggle removed from the Agent tab — moves to Settings.**
  `AgentView`'s "Allow shell commands" control was removed 2026-08-26 (the
  agent now ships in its default deny posture, shell off, with no in-tab
  override); `AgentSettings.shellAllowed` and the `--shell` argv stay. The
  workspace picker remains in the Agent status bar. **Corrected 2026-08-26:**
  shell was turned on as a tactical expedient to unblock progress (the deny
  posture caused the 23-round read/search stall); the long-term fix is P24's
  digested first-class tools + mediated bash, not raw shell-on. *Reopens as: a
  Settings pane for spawn-time agent controls (shell toggle, workspace,
  context) when the Settings scene is next touched — the Chat-retirement phase
  is the natural home, now shared with P24's shell-on retirement.*

- **Two-phase `/spike`** — P20's descoped command: an exploratory worktree spike, phase 1 read-only recon, phase 2 gated execution. The measured spike (2026-08-26 shell-on) proved the shell lever is the capability ceiling, but P24 retires shell-on for mediated bash. *Reopens behind P24: phase 2 rides P24's mediated-bash ladder (host-run, deterministically digested, policy-gated); until then only a phase-1-only (read-only) spike is designable.* Source: [`2026-08-26-spike-shell-on-findings.md`](docs/superpowers/research/2026-08-26-spike-shell-on-findings.md).

- **Retry-round evidence coherence — confirmed 2026-08-26, and worse than
  filed.** This entry's own reopen condition ("a retry round is observed
  reasoning about the wrong file state") has fired: `RepairLoop.swift:193-207`
  leaves `head` unchanged on `.validationFailed`, so round N+1's worktree is
  re-prepared from the same base and round N's written file is gone, not
  merely its traceback stale. In `captures/agenttest/20260826-050316-roadmap`,
  Mellum wrote `app.py` in round 1 and `models.py` in round 2 — individually
  correct, jointly sufficient, and never applied together, because round 2
  started from a tree with no `app.py`. Confirmed by a red probe test
  ([`2026-08-26-probe-validationfailed-discards-work.patch`](docs/superpowers/research/2026-08-26-probe-validationfailed-discards-work.patch))
  that the existing `RepairLoopTests.swift:285` cannot catch, because its
  round 2 happens to rewrite round 1's file rather than write a second one.
  This is not a coherence-of-evidence problem; it is the reason "N rounds" of
  repair does not mean N rounds. *Reopens as: recommendation 1 in
  [`2026-08-26-overnight-80-cell-verdict.md`](docs/superpowers/research/2026-08-26-overnight-80-cell-verdict.md)
  — make `.validationFailed` commit its tree and advance `head`, landing the
  probe test with it.*

- **`validationFailedReceiptRetriesWithFreshEvidence` proves the retry
  happened, not that fresh evidence reached round 2.** The fixture's
  validation command (`test -f marker.txt`) produces no distinguishing output,
  so a regression that continued the loop but dropped the `lastGrade =`
  refresh would still pass. Strengthen with a validation command that emits
  identifiable stderr, then assert it appears in `repair-packet-2.json`'s
  `taskText`. *Reopens next time `RepairLoop.swift` is touched.*

- **`AGENTTEST_REPAIR_THINK` is inert, and bounded thinking for the repair role
  is unvalidated.** Nothing at dispatch time reads `packet.sampling`; thinking is
  set once at engine-spawn from `AGENTTEST_THINK`, a whole-process property. The
  packet used to record `.bounded` while the engine ran `--nothink` — a
  capture-integrity lie, fixed by making the packet mirror what the engine
  actually runs, with a stderr warning when the inert var is set. Real per-worker
  think control needs new machinery (per-worker engine control, or a second
  engine). *Reopens with bounded-thinking validation for the repair role
  (originally P12.6's second half, never run).*

- **Repair cannot honor `AGENTTEST_PATH_STYLE=absolute`.** D5 mandates building
  the repair packet *before* `WorktreeDispatcher.prepare`, so no worktree URL
  exists yet to render an absolute root from — `repairPacket` always renders
  relative paths. An `AGENTTEST_PATH_STYLE=absolute` run therefore implements
  with absolute paths and repairs with relative ones: an uncontrolled variable
  flip inside one run, in the arm where path presentation is a *known* lever
  (C13/B8). Not fixed — fixing it means relaxing D5's ordering. *Reopens if an
  absolute-path arm is ever run with repair enabled; until then, don't combine
  them without accounting for the flip.*

- **Two P15 harvest limitations never filed** (its others were). (1) The
  repeated-heading abort can drop a file that first appears *after* the first
  repeat — not observed, structurally possible. (2) First-occurrence-wins
  discards a self-corrected re-emission: if the model writes a file, notices an
  error, and re-emits it correctly, the harvest keeps the first (broken) copy.
  Real, with the tradeoff consciously recorded at the time. *Reopens if a run is
  ever traced to either.*

- **P15's design "Deferred" list, unfiled in full**: a packet `mode` enum
  (`agentic|textContract`) instead of the current implicit selection; tightening
  the emission protocol's Section 1; a tool-free engine mode / sampler `</think>`
  handling; a steering profile (P13-deferred); and a per-model pass-rate
  guarantee. Source:
  [`host-controlled-action-mode-design.md`](docs/superpowers/specs/2026-08-25-host-controlled-action-mode-design.md).
  *Reopens with any further text-contract work.*

- **The harvest gate requires `stopReason == .eos`.** A turn that runs to the
  token wall is never harvested, so nothing is written and validation fails on
  an empty tree — 1 of 9 build runs. The repeated-heading abort could recover
  such a turn's first pass, but never sees it. Widening the gate touches session
  -exhaustion semantics, which differ per arm (repair reuses the worker across
  rounds; build handles exhaustion after phase finalization). *Reopens when
  token-wall runs are a measurable share of failures.*

- **The lenient harvest blurs the failure taxonomy.** Without a fence there is no
  delimiter, so prose under an allowlisted heading is written as file content,
  and turns once classified `contractNotFollowed` can land as `validationFailed`
  instead. A content-vs-prose discriminator is deliberately *not* wanted: it
  would be a guard holding less information than the authoritative layer, the
  same mistake as the removed contract-blind pre-edit guard. *Reopens if a
  measurement needs to separate "ignored the contract" from "wrote buggy code" —
  the honest fix is a stricter emission contract, not a smarter parser.*

- **Specialized tool subagents** — split 2026-08-27 by naming: a **tool** is deterministic host code (no model — run one command in its JSON mode, digest the output); a **subagent** is the model-backed escalation (apply the fix when the run says what it is, or summarize when the deterministic digest isn't decision-adequate). The deterministic half — ruff, pyrefly, pytest, sphinx, roadmap admin run+digest — is now **P24's** direction (`test`/`lint`/`scout`); the subagent half stays here. Budgeted to fit an 8k context on AFM3; because Swift runs the evocation, repeated invocations make the limit a budget rather than a wall. The open question is dispatch — how the orchestrating model+agent decides which specialized agent to call. The economics are measured, not assumed: locally, prefill is the scarce resource, so deterministic work first is a *performance* rule — `ruff --fix` beats the model typing the same 40-line edit by ~500x, and clustering 40 pytest failures to 2 representatives turns a 178s prefill at depth into 9s (rates from `docs/harvest/telemetry-findings.md`; worked table in the ds4-control survey cited by `2026-08-22-p11-engine-constraints-and-corrections.md`). *Reopens when P11 lands and the pool design can hold a one-command worker, or as P24's subagent escalation; this is a candidate shape for P11's workers, not a phase of its own.* Source: P11 "Subagent pool".

- **The dispatch decision** — what the handoff packet maker must know to route a task, on three axes. **(1) Parallelism:** dependency edges declared by the plan author are authoritative; the maker may additionally *prove* independence from disjoint writable-file sets plus disjoint validation commands, and must refuse when it cannot — file-disjointness is necessary, not sufficient (an API change and its consumer share no file). **(2) Thinking requirement:** a task is delegable to a reasoning-light worker only when acceptance is a machine-checkable predicate, the tool surface is bounded (`read`/`write`/`edit`, no `bash`), and the writable-file set is exact — and thinking is a stage, not a property: "fix the broken test" needs diagnosis (thinking) before the apply is mechanical. **(3) Executor:** whether the packet goes to a full-context worker, to a deterministic **tool** (a one-command host run in its JSON mode — ruff, pyrefly, pytest, sphinx, roadmap admin — now P24's direction), or to a model-backed **subagent** that applies the fix when the run says what it is, with AFM3's 8k as the budget for the latter and repeat evocations for anything longer. The lesson travels with it: the maker enforces declared intent and computes conservative proofs; it never re-derives semantics with less information than the plan author — the same lesson as the removed contract-blind pre-edit guard. *This is P10's routing design; axis 3 is what the "Specialized tool subagents" entry feeds. **Reopen condition fired 2026-08-22 (P10 landed); the consumer is P20's `/orchestrate` coordination loop, still a stub in the app.*** Source: P10 "Isolation", the "Specialized tool subagents" backlog entry.

- **House style as a compiled artifact** — the long-term goal is an agent that
  writes code the way the author would have written it. The cheap approach —
  infer style from surrounding code on every prompt — recomputes a function of
  a corpus that changes on the scale of days, and matches *the nearest example
  in context* rather than the dominant convention, so it drifts on
  first-of-a-kind files and faithfully reproduces whatever outlier grep
  surfaced. Four moves in dependence order: (1) style compliance becomes a
  P9/P10 **objective**, so the model discovers convention from rejection
  instead of carrying it — zero context cost, and it works precisely where
  inference is weakest; (2) an out-of-band pass **compiles** what it can into
  executable checks — ruff and refurb are *selected* not authored (neither
  takes user-written rules), `ast-grep`/`semgrep` carry project-specific
  patterns, `pyrefly` types, HTML/CSS validation of rendered output for
  tdom-shaped work, `pytest`/`sybil`/`sphinx` as executable truth; (3) it
  **elects a canonical exemplar** per pattern-kind, so D5's names-only staged
  reads point at known-good precedent; (4) the P9/P10 correction stream is
  **mined** for anti-patterns, which compile easily and arrive for free.
  Attaches to D6 — same properties (deterministic, out-of-band, incrementally
  maintained, no inference), different invalidation clock: commits rather than
  events. The specialist-subagent form is bounded by this engine rather than
  free: exact-prefix-only KV reuse plus D8's shared-root short-lived workers
  makes a per-specialist recipe a divergent prefix, costing either the shared
  root or ~1.5–6.1 GB of scratch per long-lived specialist — which is why
  existing `tdom`/`hopscotch`/`svcs` skills should *be* the specialist
  definition rather than a parallel recipe format, and why worker budgets
  (4k–16k, D8) argue for checks over prose in the first place. **Nothing here
  is measured.** *Reopens when P9's objectives exist, since the gate is the
  load-bearing move and needs them. The cheap probe that decides the shape:
  measure the compile fraction on tdom's practices — high means gates carry it
  and specialists stay small; low means recipes carry the weight and the
  residency cost above becomes the real problem.* Source:
  [`docs/superpowers/research/2026-08-23-house-style-as-a-compiled-artifact.md`](docs/superpowers/research/2026-08-23-house-style-as-a-compiled-artifact.md).

- **Disambiguate the orchestrate directive on dispatch ordering.** The
  directive says only *"One-shot-first: dispatch each phase once"*
  (`Sources/SwiftStarKit/OrchestrateDirective.swift:34`) and never says whether
  "once" constrains cardinality or ordering — may phases go out together, or
  must each wait for the previous receipt? Block A seed 109's sibling failure,
  **seed 106**, shows the cost: the orchestrator produced 28,355 characters,
  made 6 tool calls, dispatched **nothing**, and lost the cell relitigating
  that exact question — *"Actually, I want to reconsider whether to dispatch
  all three phases at once or one at a time… Wait, but actually… Hmm, but
  actually, re-reading:"* (`captures/agenttest/20260829-014957-roadmap-directive`).
  Its reasoning is correct, which is what makes this ours rather than the
  model's: Phase 2 edits the `app.py` Phase 1 creates, so concurrent dispatch
  really would race, and the directive gives it nothing to resolve the tension
  with. One clause stating that phases are dispatched sequentially, each after
  the previous receipt, should close it. **This is the third instance of one
  defect family** — a harness prompt that underspecifies and a model that
  dutifully pays for it: P17's false *"exactly one file is wrong"*, the
  singular repair emission follow-up found in
  [Block B's analysis](docs/superpowers/research/2026-08-29-block-b-negative-result-analysis.md),
  and now this. Worth a standing check on authored prompts rather than three
  separate fixes. *Cheap; needs a re-measurement arm against Block A's 27/29
  baseline to confirm, not just a reading of the prompt.*

- **`runDirectiveOnce` dropped `sharedContext` — fixed 2026-08-29, same defect
  family, fourth instance.** The non-directive phase loop (`runOnce`,
  `Sources/swiftstar-agenttest/main.swift:202,390`) always includes
  `sharedContext` (mission + `tech-stack.md`, which pins `fastapi[standard]`)
  in its packets; `runDirectiveOnce` built the orchestrate prompt from `task`
  alone. Invisible on the `roadmap` spec — its implementation-style phrasing
  happens to cue the right framework — but a generalization arm on
  `roadmap-user-story` (business-outcome phrasing, same target app, same
  oracle) lost 3 of its first 3 graded cells to the orchestrator building the
  **entire app in Flask instead of FastAPI**: it passed its own phase
  validation (which never checks the framework either) and then failed the
  acceptance suite's `from app import app` at collection time — a total loss,
  not a partial one. Confirmed by hand: recovered the leaked dispatch
  worktree for seed 203 before the sweeper could take it and re-ran the
  acceptance suite directly —
  `ModuleNotFoundError: No module named 'flask'`
  (`captures/agenttest/20260829-130604-roadmap-user-story-directive`). The arm
  was stopped at n=4 once the cause was confirmed rather than run to n=10
  confirming the same bug repeatedly. **Fixed**: `OrchestrateDirective.build`
  gained an optional `projectContext` parameter (default empty; all 8
  pre-existing tests unaffected, 3 new tests added,
  `Tests/SwiftStarKitTests/OrchestrateDirectiveTests.swift`), and the directive
  call site now passes `sharedContext`. A re-run arm at seeds 211–220
  (`experiment-manifest-orchestrate-userstory-fixed.tsv`) will confirm the fix
  holds before this note is closed. See
  [`docs/pathologies.md`](docs/pathologies.md) #10 for the general shape:
  **silent framework substitution** when project context is missing.

- **"Swift body, Python brain"** — agent policy in a hot-reloadable uv-managed
  peer process. *Reopens if agent policy starts changing faster than the app
  can ship.* Source: `SWIFTSTAR.md`.

### Pool and context economy

- **Small-ctx worker sessions for the pool (the RLM lever).** The app's
  `/chat` now runs its worker as a context-isolated session in the one
  engine, but at the *full* `-c` ctx — ~2.5 GB KV + ~6.15 GB scratch at 50k
  (`agent_worker_effective_ctx_size` reads the session ctx; there is no
  per-worker override). Correction 2 names the lever: a 4k worker is ~1.7 GB,
  not ~8.7 GB. *Descoped from P20 2026-08-27 → its own phase, merged with P23's per-worker think control (one engine patch, fork-ledger row #13, golden recapture). The patch: give pool workers their own ctx (a per-worker override — `agent_worker_effective_ctx_size` reads the session ctx and none exists), or a kept-alive `rewind`-ed small-ctx template session. The Laguna XS line (P22) is the natural worker model — depends on P22's XS golden recapture.*

- **Worker-2 session-context ceiling across multiple phase repairs.** D8 sized
  worker 2 for two rounds of *one* repair (~10–12k, fits ctx=32768). P12.8
  changes the shape: up to three phase failures per run, each dispatching to the
  same worker-2 session with full-surface evidence (six writable files + a
  traceback). Three sequential repairs plausibly approach the ceiling, and the
  failure mode is the one D8 already calls fatal — a repair turn ending at
  `limit`/`contextFull` leaves worker 2 unusable and the run must stop. Options:
  reset worker 2 between phase repairs (`agent_worker_reset_to_sysprompt` exists
  engine-side), widen the pool and rotate, or accept it with the existing stop
  guard and record the ceiling. Needs engine + pool-wire work — "its own small
  phase." *Reopens when a multi-phase-repair run is actually attempted at scale.*

- **Context-economy tooling** — two deterministic moves that exist because KV
  reuse is exact-prefix-only and prefill is the scarce resource: (1)
  *don't-re-read* — hash+mtime every file the agent has read and answer an
  unchanged re-read with "unchanged since turn N" instead of contents, worth
  up to ~130s per avoided deep re-read at measured rates; (2) *warm-prefix
  routing* — when a pool exists, route a task to the session whose live
  prefix already contains its files (`ds4_session_common_prefix` is free
  engine-side; needs a wire query). *(1) **reopened 2026-08-27** — P9's host
  tools shipped AND the 1809 capture measured the win (one file re-read 31× =
  37% of Σsuffix); P24's tool list absorbs it as the read-guard. (2)
  **partially unblocked 2026-08-27** — the pool shipped (P11/P20); still needs
  the `ds4_session_common_prefix` wire query. See the [1809 findings](docs/superpowers/research/2026-08-27-1809-prefill-tail-findings.md).* Source:
  `2026-08-22-p11-engine-constraints-and-corrections.md` and the ds4-control
  survey it cites.

- **A `recall` tool** — the agent can page files (`read`/`search`/`more`) but
  not its own history: the transcript is a flat token array whose head is
  destroyed at compaction. The persist half is nearly free — the engine's
  session `.kv` files already store the full rendered conversation as plain
  UTF-8 behind a fixed 48-byte header, and pre-compaction prefixes survive on
  disk until evicted — so the work is pinning the pre-compaction entry against
  eviction plus a `recall(query)` tool backed by deterministic search over
  that text. Compaction becomes lossy-in-context, lossless-on-disk, with zero
  extra inference. *Reopens when P9 lands (host-owned tools make it app-side
  rather than a C patch) or when a compaction is first observed discarding
  something a later turn needed.* **REOPENED 2026-08-27** — both conditions:
  P9's host tools landed, and a compaction was observed discarding context a
  later turn re-read (the post-compaction AgentView.swift re-reads in the 1809
  capture). See the [1809 findings](docs/superpowers/research/2026-08-27-1809-prefill-tail-findings.md). Source:
  `2026-08-22-p11-engine-constraints-and-corrections.md` and the ds4-control
  survey it cites. **Deferred again 2026-08-30** — the window-honoring-reads
  spec that superseded the original read-guard spec explicitly scopes `recall`
  back out, "sequence after P24": see
  [`2026-08-30-p24-1-window-honoring-reads-design.md`](docs/superpowers/specs/2026-08-30-p24-1-window-honoring-reads-design.md).
  Still reopens on the same two conditions; P24 just isn't done yet.

- **A session browser over `~/.ds4/kvcache`** — listing, metadata (tokens,
  ctx, created, last-used), and full-text search across past agent sessions,
  read directly from the `.kv` header + rendered-text region with no model
  and no engine. Also the substrate `recall` searches. *Reopens with P7 (an
  agent tab wants session listing/resume) or with `recall`.* Source: same
  note; format verified by parsing a real file with `struct.unpack`.

- **A deterministic compaction skeleton** — of the five things the engine's
  compaction prompt asks the model to reconstruct, two (files
  inspected/edited with paths and ranges; commands run) are losslessly
  reconstructible today from `--json-events` tool params, and a tool-call
  ledger cannot hallucinate which file it edited. The wire is *not* lossless
  for results (only the bash family emits `output`), so this is a skeleton
  plus a smaller model summary, not a replacement. Requires forking the
  compaction path in `ds4_agent.c`; payoff is real but small (compaction
  fires roughly once per full context). *REOPENED 2026-08-27* — a compaction
  was observed at the everyday context size with a measured cost: five in 24
  min at 28–29k, each discarding ~23k tokens (the 1809 capture). Still
  requires the `ds4_agent.c` fork. See the [1809 findings](docs/superpowers/research/2026-08-27-1809-prefill-tail-findings.md). Source: same note.
  **Deferred again 2026-08-30** — same window-honoring-reads spec, same
  "sequence after P24" scoping; the 1809 capture's five compactions are now
  understood partly as a starvation-loop artifact (see the read-guard's
  supersession note), so the compaction-discards-needed-context reopen
  condition should be re-verified once window-honoring reads ships and re-reads
  drop, not assumed to still hold at its original strength.

- **Recursive sub-queries — the RLM pattern as P11's third lifetime tier.**
  A project is a long-lived session; a subagent is a short-lived one sharing
  the parent's root; an RLM sub-query is an *ephemeral* session over a slice
  of a large input, whose result folds back into a root context that is
  deliberately kept small (Recursive Language Models, arXiv:2512.24601: flat
  scaling with input length *provided chunk size stays constant*). Same pool,
  three lifetime policies. The economics are this hardware's own: splitting
  a 131k prefill into eight sequential 16k prefills is up to ~4.2x cheaper by
  the measured curve, with no concurrency required — which is fortunate,
  since none exists (the pool is single-threaded by design — see Prior
  work's P11 entry). Two constraints a naive reading of
  the paper misses: a sub-query session must be a small-ctx *template kept
  alive and rewound*, not a fresh allocation (each Laguna session pins
  ~6.1 GB of scratch), and the shared preamble is repeated per sub-query, so
  the win shrinks with preamble size. Compaction is already a degenerate
  instance — a bounded summarizer whose output folds back into the parent.
  *Reopens when P11's pool exists and a task is observed needing more input
  than fits one shallow context — a large-file read, a multi-file review —
  which is the measurement that tells us the real gain under the 4.2x
  ceiling.* Source: `2026-08-22-p11-engine-constraints-and-corrections.md`,
  "The finding under P11."

- **Multi-project residency** — N long-lived project sessions sharing one
  engine, switched without reload. Priced honestly: KV is
  `49,152 × ctx + 72 MiB` per session *plus* ~6.1 GB scratch each, so five
  64k-ctx sessions ≈ 89 GiB with the model — over the default wired ceiling
  on a 96 GB machine. Viable shape: snapshot idle sessions to disk
  (`ds4_session_save_payload`/`load_snapshot`, ~13 GB IO per 150k swap —
  seconds, versus minutes of re-prefill) with a small resident working set.
  *Reopens after P11's pool exists and a second concurrent project is
  actually wanted.* Source: same note.

- **Snapshot-before-risk, rewind-on-failure.** Before a speculative multi-step
  action (an uncertain edit sequence, a risky tool chain), `ds4_session_save_payload`
  the session; on failure, `ds4_session_rewind`/`load_snapshot` back to the
  checkpoint instead of asking the model to undo itself in-context (which costs
  tokens, is unreliable, and risks forcing a compaction). Host-driven exact
  backtracking of session state, not conversational backtracking. Unmeasured:
  nothing in the codebase exercises `rewind`/`save_payload`/`load_snapshot`
  today beyond `Multi-project residency`'s idle-session-eviction use above, and
  that use is disk-swap, not undo. *Reopens when a task is observed where the
  model's own in-context correction of a failed multi-step action is
  measurably expensive or unreliable enough to be worth a host-side revert
  instead.* Source: brainstorm 2026-08-30, grounded in the session primitives
  named at [`2026-08-23-p11-subagent-pool-design.md`](docs/superpowers/specs/2026-08-23-p11-subagent-pool-design.md).

- **Compare-before-commit via shared-prefix forks.** Snapshot at a decision
  point, run two short candidate continuations from that checkpoint, keep the
  better one, discard the other's session. **Not a concurrency win** — the
  pool is serialized (P11 D1), so both continuations run one after another on
  the same GPU; the benefit is a better-chosen answer per token spent (a
  cheap shared-prefix comparison instead of committing to one plan and paying
  a full retry later if it's wrong), not wall-clock speed. Needs a cheap
  host-side or bounded-model judge to pick the winner, or the comparison
  itself becomes the tax it was meant to avoid. *Reopens when a concrete
  decision point exists where two plans are a genuine toss-up and picking
  wrong is expensive enough to justify the extra shallow generation.* Source:
  brainstorm 2026-08-30, same spec.

- **Admission-control scheduler priced by the measured prefill-depth curve.**
  The docs already have the KV-size formula (`49,152 × ctx + 72 MiB`) and the
  measured prefill-depth throughput curve (231→114 tok/s, 12k→30k ctx). A
  host-side scheduler could predict the token/time cost of a prospective
  dispatch or route *before* committing — the same philosophy as the existing
  memory-feasibility gate, applied to time instead of RAM — so the
  orchestrator picks the cheapest routing deterministically instead of
  discovering the cost after the fact. Overlaps with the already-scheduled
  dispatch-preference rule (P20) and warm-prefix routing (above); this entry
  is the cost-prediction piece neither of those names explicitly. *Reopens
  when P20's dispatch-preference rule is live and a routing decision is
  observed choosing between options with materially different prefill
  depth.* Source: brainstorm 2026-08-30.

- **`.kv`/wire captures as deterministic replay fixtures for host-tool
  regression tests.** P24.1's Task 4 already does one instance of this — replay
  the 1809 capture's read sequence through a fresh `ReadGuard` with no model,
  no engine — but the trick generalizes: any real captured session (`.kv` text
  or `wire.ndjson`) is a corpus of deterministic replay fixtures for testing
  *any* host-side tool-logic change, cheaper than a live capture and closer to
  production shape than a synthetic fixture. *Reopens with the next host-tool
  behavior change that wants regression coverage beyond synthetic fixtures —
  P24.2's re-decided read guard is a likely first customer.* Source: brainstorm
  2026-08-30, precedent in [`2026-08-30-p24-1-read-guard.md`](docs/superpowers/plans/2026-08-30-p24-1-read-guard.md) Task 4 (superseded but the replay technique survives).

- **Cross-session fact mining from historical `.kv` files.** Deterministic text
  search over old sessions' rendered conversations (no inference) to seed a
  project's persistent knowledge, instead of the agent re-deriving the same
  facts fresh every session or paying a summarization pass. Cheaper than
  compaction's model-authored summary; read-only against artifacts that
  already exist on disk. Substantially the same substrate as the backlogged
  `recall` tool and session browser above — this entry is the "mine it
  proactively into memory" framing rather than "search it on demand."
  *Reopens together with `recall`/the session browser, once either lands and a
  concrete case shows an agent re-deriving a fact a past session already
  established.* Source: brainstorm 2026-08-30.

### Model and engine features

- **Generation-time stopping control.** The engine's pool protocol has no cancel,
  so a degenerate run pays to the token wall before the host can react; the
  repeated-heading abort is harvest-time only. *Reopens only if engine-side work
  is on the table — it is the one P15 item that is not host-addressable.*

- **An engine-side memory-plan / tokenize CLI** — an additive mode that
  prints the memory plan for a given ctx and exits without loading weights
  (the estimator needs only GGUF metadata; `inspect_only` exists), and a
  tokenize mode (the tokenizer loads vocab without weights). The first
  retires the P3 under-report *and* the temptation to mirror allocator math
  in Swift; the second enables pre-flight token budgeting ("this read is 18k
  tokens and will cross the compaction threshold") without linkage.
  Upstream-bound; must include the estimator's Laguna scratch fix or it
  ships the same under-report with a nicer interface. *Reopens with the
  upstream proposal for the P3 correction, or when P9's budgeting needs
  token counts.* Source: same note.

- **Laguna XS 2.1 at 16 GB — feasible, unconfirmed** — the SSD-streaming
  footprint work is done and the numbers clear 16 GB comfortably: 6.53 GiB
  planned / 6.46 GiB task footprint ("fits easily under 10 GB including
  context"), from the uniform RoutedQ3_K artifact plus `--prefill-chunk`. What
  remains is confirmation, not new engineering: the 16 GB hardware acceptance
  never ran (the numbers come from a 128 GB dev machine, whose OS page cache
  hides SSD-miss throughput), so the committed target stays 32 GB until the
  `mini-notes.md` §7 checklist passes on real 16 GB hardware. *Reopens with P13
  (Laguna XS is a P13 variant) or when a real 16 GB machine is available.*
  Source: `~/projects/ds4/.claude/worktrees/laguna-xs2.1` — `LAGUNA-XS.md`,
  `docs/superpowers/LAGUNA-XS21.md` §6, `docs/superpowers/plans/mini-notes.md`
  §7, and
  `docs/superpowers/research/laguna-xs21-p26-p27-hotlist-acceptance.md`.

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
  costing a real turn.* **REOPENED 2026-08-29 — the condition is met three
  times over, and the split matters.** Two historical turns were killed
  ([Block C](docs/superpowers/research/2026-08-28-block-c-capture-mining.md)):
  one where the model emitted its own system-prompt placeholder as a tool name
  (`"name": "{function-name}"`), one where 467 tokens of *correct* reasoning
  about the right file were discarded. The third arrived in a fresh
  pre-registered run — Block A seed 109 lost an entire cell to three
  consecutive `tool calling is not allowed inside <think></think>` rejections
  followed by the engine's `too many malformed tool calls in a row` kill
  (`captures/agenttest/20260829-090231-roadmap-directive`). **The two classes
  need different fixes.** A plain grammar cleanly prevents the malformed-*name*
  class. The *placement* class — a well-formed call emitted inside `<think>` —
  is not a syntax error and a grammar over tool-call text will not catch it; it
  needs think-state-aware constraint or engine-side hoisting. Placement is also
  the more expensive and more common class (5 of 8 observed malformed calls),
  and it can only affect thinking-enabled roles, which is exactly what the
  orchestrate loop is. Base rate is tail risk, not a tax: 0.21% of 3,796 tool
  requests, and 1 of 38 Block A cells. Note the engine already emits a
  corrective nudge ("finish thinking before emitting `<tool_call>`") and the
  model repeated the mistake anyway, so text feedback is not the remedy.

- **DFlash speculative decoding.** `laguna-s-2.1-DFlash-Q8_0.gguf` (1.1 GB) is
  a draft head for Laguna S, not a standalone model — its GGUF declares
  `general.architecture: dflash` and `dflash.block_count`, not a servable
  architecture, and the engine only accepts it via `--dflash <path>` alongside
  a full Laguna GGUF (confirmed against `external/ds4/README.md` and by loading
  it standalone, which fails: `required metadata key is missing:
  deepseek4.block_count`). It has no code path today: `AgentCommand.argv` emits
  no draft-model flag, and `Variant` has one `modelFile`, so a draft/target pair
  is unrepresentable. Deliberately not pursued now (2026-08-27 call) — it forces
  **greedy decoding** (DFlash only engages at temp 0; the Laguna default is
  0.7), which is a behavior change to agent turns, not a free speed knob, and
  it is a throughput claim the P24 guardrail says to measure as a paired bill,
  not assume. *Reopens if decode throughput at temp 0 becomes worth trading
  sampling diversity for — model it as a `draftModel` field on Laguna S's
  `Variant`, not a fifth registry entry, since it has no context range or
  memory budget of its own.*

- **Energy-aware pacing** — pace-to-read decoding and watts-aware scheduling via
  a runtime control message. The control message must be *built*, not exposed:
  `ds4_session_set_power` rejects Laguna at any value below 100 and is
  engine-wide, not per-session, where it does apply (verified 2026-08-22).
  *Reopens when idle or sustained power shows a cost worth paying for; the
  current measurement says idle draw is under 1W — the reopen path is P21's
  "expose the wire's `power` field" step, to measure the sustained draw of
  the prefill spikes before building the lever.*

- **An embedding spike.** *Reopens only if dynamic Swift-defined per-token logit
  masking becomes critical-path. Nothing else in `SWIFTSTAR.md` requires
  in-process access.*

### Evaluation and measurement

- **Orchestrate-loop generalization: does 93% hold on a second task?
  (arm 3 complete 2026-08-30 — verdict: signal, not confirmation; still
  open.)** Block A measured the `/orchestrate` loop at **27/29 = 93%
  [78%, 98%]** — but every one of those cells ran the **same task**
  (`roadmap` spec, one synthetic app, one 13-test oracle). Thirty seeds on one
  task measures seed variance, not task variance, and `/goal` v5's
  byte-identical-prompt swing (2/3 → 0/3) is a standing warning that
  task-to-task variance may be the larger term. **The 93% figure should carry
  "measured on one task" until this closes.**
  *Two earlier attempts were stopped deliberately, each having found a real
  harness defect rather than an answer:*
  1. **Seeds 201–204** — 4/4 lost to the orchestrator building the app in
     **Flask instead of FastAPI**: `runDirectiveOnce` never passed
     `sharedContext` (mission + `tech-stack.md`) into the prompt, though the
     non-directive phase loop always had. **Fixed** (`OrchestrateDirective.build`
     gained `projectContext`).
  2. **Seeds 211–215** — 5/5 lost to an **engine false positive**: the
     degeneracy guard aborted legitimate writes whose tail was a 64-dash
     comment separator. **Fixed** as fork divergence **#15**; unit-verified
     across a 13-case table and both test tiers (785 tests).
  **Arm 3 (seeds 221–230, `roadmap-user-story`, n=10) ran both fixes live for
  the first time.** Manifest:
  [`experiment-manifest-orchestrate-userstory-221.tsv`](docs/superpowers/research/experiment-manifest-orchestrate-userstory-221.tsv);
  results:
  [`experiment-results-orchestrate-userstory-221.tsv`](docs/superpowers/research/experiment-results-orchestrate-userstory-221.tsv).
  **Neither fixed bug recurred** — zero Flask substitutions, zero
  degeneracy-guard aborts across all 10 captures; both fixes verified live,
  not just unit-tested. **Graded rate: 6/9 = 67% [35%, 88%]** (seed 222 is
  `harness-void` — a 1501s turn timeout at the 1500s cap, mid-write, not a
  grade — excluded from the denominator per the pre-registration's own rule;
  scoring it as a fail gives 6/10 = 60%, same band). Block A's 93% CI and
  this arm's CI overlap, so **arm 3 does not establish a difference from
  Block A, only that the ≥8/10 generalization bar was not reached** —
  **verdict: band 2, "real signal that task framing matters beyond the two
  fixed bugs, underpowered to size it further at n=9."** Three graded
  failures, reconstructed by wire-replay against the real acceptance suite
  since the harness prints no failure detail for directive cells (a gap
  worth fixing before the next arm — `main.swift:1352` already has
  `finalGrade`'s report, it just isn't printed on this path):
  - **Seed 223 — ambiguous, do not count as a clean model failure.** Seeded
    `complaints` in a startup/lifespan hook instead of at module import, so
    acceptance's `TestClient(app)` (no `with`) sees an empty store at
    snapshot time. The user-story spec never says seeding must happen *at
    import* — only `roadmap.md` (the other spec) does — so this is plausibly
    a fair reading of the prompt failing an oracle written for the other
    spec's stricter contract, not a model competence gap. It's also a
    **double failure**: `dispatches=0` (the orchestrator built the whole app
    itself), which independently fails the harness's own `dispatches >= 1`
    pass bar — at n=9 one cell like this moves the rate 11 points on its
    own. Left in the denominator (per the pre-registration's rule) but
    flagged here rather than treated as settled evidence.
  - **Seed 226 — genuine content miss.** Form on its own page/route instead
    of on the board; wrong markup (`list-group` not cards); dropped the
    verbatim seed string "Scope creep never ends." All three are stated
    explicitly in the user-story spec, so this is a fair grade.
  - **Seed 228 — same shape as 226**, independently: separate submit page,
    wrong markup, wrong heading, dropped seed string. Two of three graded
    failures share this signature — a real, consistent pattern, not noise.
  *What this cannot conclude:* anything about tasks other than `roadmap` and
  `roadmap-user-story`; a precise rate at n=10 (the CI spans 35–88 points);
  whether other directive-vs-phase-loop gaps exist beyond the two now fixed.
  **223's ambiguity resolved 2026-08-30**, oracle side:
  [`test_acceptance.py`](fixtures/agenttest/acceptance/test_acceptance.py)'s
  `client = TestClient(app)` now calls `client.__enter__()` before
  `SEED_COMPLAINTS` snapshots the store, so a startup-hook seeder (seed 223's
  own pattern, and the idiom its own `tests/test_app.py` used independently)
  is no longer graded as an empty board. Verified by replaying seed 223's
  actual capture files against the fixed oracle: **13/13**, where the
  pre-fix oracle scored 2/13 failing on the identical solution; the
  reference (static-seeding) solution still scores 13/13, so this is not a
  regression for the other seeding style. **This is a code fix, not a live
  measurement** — no cell has been re-run under it, and seed 223's own
  cell is not retroactively reclassified as a pass in the results table
  above (append-only). *Reopens as:* a fourth arm on `roadmap-user-story`
  (fresh seeds, disjoint from 201–230) run under the fixed oracle — ideally
  once the directive-cell failure-detail gap is also closed so causes don't
  again require manual wire-replay — before pooling anything with Block A.
  Nothing else is blocked on it.

- **The largest single failure population is not the one the campaign chased
  (2026-08-29).** The 2026-08-29 failure classification of 24 non-passing
  repair captures found **7 of 24** sharing one shape: the model **correctly
  names the bug on a first pass, then explicitly reasons itself out of fixing
  it** and never emits the file — *"I don't see any issues with the `<html>`
  tag."* That is a bigger and more consistent population than the delivery
  defect the campaign spent the day on (2 of 24), and the classification
  called it out unprompted as the next thing worth targeting. Nothing has been
  tried against it. Unlike the delivery defect, there is **no evidence yet
  that it is a harness artifact** — it may be the model, and saying so needs a
  probe, not an assumption. See
  [`2026-08-29-failure-classification.md`](docs/superpowers/research/2026-08-29-failure-classification.md)
  and [`docs/pathologies.md`](docs/pathologies.md) #2. *Reopens whenever
  repair-loop quality is worked on again; it is the highest-yield known target
  in that area.*

- **Two data-integrity flags from the same classification (2026-08-29), both
  unexamined.** (1) A **false `V6` void**: `plausible-wrong-fix` seed 5 was
  recorded as harness-void while its underlying candidate actually graded
  **13/13** — if that is a scorer defect rather than a one-off, it silently
  removes passing cells from denominators, which is the exact class of error
  this campaign's discipline exists to catch. (2) A **content regression at
  seed 60** not present in the earlier Block B analysis. Both are named in the
  classification doc and neither has been chased. *Reopens before the next
  arm that reuses those denominators — a scorer that drops passes is worse
  than one that drops fails, because it flatters the result.*

- **Eval-system consolidation (Later half of the 2026-08-29 audit).**
  Swift-native `swiftstar-analyze findings`/`index` verbs wired to the
  existing `DiagnosticsAnalyzer`; port the Python campaign
  report/taxonomy scripts into those verbs and delete the originals; a
  zero-Metal replay tier over stored captures; a kill list of dead one-off
  runners and superseded audit checks; `DeepSeekGrader` calibration; a second
  fixture app and a real hard/superhard difficulty tier. None of this gates
  the next campaign run — P26 (Now) does. *Reopens when eval infrastructure
  work is next picked up.* Source:
  [`2026-08-29-eval-system-audit-and-later-work.md`](docs/superpowers/research/2026-08-29-eval-system-audit-and-later-work.md).

### ANE watcher tier

- **The ANE watcher tier — a librarian and an inspector over Monty.** A third
  tier beside the GPU main agent and the GPU pool: AFM on the ANE (macOS 26
  CoreML, 27 CoreAI — verify) as the model, and
  [Monty](https://github.com/pydantic/monty) — pydantic's sandboxed Rust
  interpreter for a Python subset — as the executor. Two roles share it. The
  **librarian** is a watcher (a Pi-style guard): it declares the state it cares
  about, the host projects the rolling digest (D6) into a small slice, and the
  librarian's moment-specific reaction runs in Monty — sandboxed,
  resource-limited, type-checked against host-function stubs. Monty never sees
  kv; it sees the projected digest, with a narrow `kv_query(selector)` host
  function as the only door ("`read_customer(id)` is a tool; `read_file(path)`
  is a filesystem"). The **inspector** is the same substrate in the tool loop,
  running P9's validation cadence on the ANE while the model is blocked on the
  tool, findings riding back on the triggering result. The trick that makes
  model-authored Monty trustworthy: Swift owns a fixed, typed envelope (template
  + host-function stubs), the model fills a bounded hole, `ty` is the referee
  before execution, and a retry is a cheap bounded re-prefill. A host function
  (`ask_model`) runs a chat prompt and returns, so a Monty loop orchestrates
  bounded model calls deterministically — the RLM/slicing pattern with the
  strategy as a short program rather than a token-stream plan. Reactions can be
  declared as App Intents, making a user's librarian discoverable by the system
  AI — the extension-system shape. *Reopens when P11's pool exists and either a
  kv/digest watcher is wanted or P9's validation cadence is being built with the
  AFM-on-ANE shape — and only after the two falsifiers are measured, not
  assumed: the macOS 26 AFM invocation API is confirmed callable for text
  generation, and the fill-success rate (a primed hole type-checks and runs
  first time) is measured.* **Split 2026-08-27:** the deterministic background files+symbols index (what feeds P24's `scout`) is P24's, not this tier's; this entry keeps the model-backed roles — the librarian's Monty reactions and the inspector as P24's ANE-only-phrases escalation when deterministic clustering isn't decision-adequate. Both stay AFM-gated. **CAG filing 2026-08-28:** see [`2026-08-28-cag-and-the-librarian.md`](docs/superpowers/research/2026-08-28-cag-and-the-librarian.md) for the capacity analysis (4k-window sufficiency, layer decomposition, deciding measurement). Source:
  `docs/superpowers/research/2026-08-23-monty-and-the-ane-watcher-tier.md`,
  `docs/superpowers/research/2026-08-28-cag-and-the-librarian.md` (arXiv 2412.15605v2).
  **Falsifier 1 resolved 2026-08-30** — checked against Apple's public docs
  (`developer.apple.com/documentation/foundationmodels`, `import
  FoundationModels`, not the guessed CoreML/CoreAI naming): `LanguageModelSession`
  is a real, stateful, multi-turn API with a documented KV cache (Apple's own
  "Optimizing key-value caching in language model sessions" guide), append-only
  cache-friendly turns, `prewarm(promptPrefix:)`, and transcript rehydration
  across restarts. Not a one-shot predictor. The invocation-API falsifier is
  cleared; the fill-success-rate falsifier is not — still needs measuring.

### Process and tooling

- **`fixtures/agent/golden.{ndjson,trace}` and `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}` are byte-identical, manually-synced duplicates, with no build-time mechanism enforcing it (2026-08-29).** A symlink was tried and confirmed to break — SwiftPM's resource-copy step preserves the symlink rather than dereferencing it, so it dangles once relocated into the `.build` bundle. Documented at the point of use (`FixtureReplay.swift`, `DiagnosticsFixture.swift`, `fixtures/agent/provenance.md`) and partially guarded by `FixtureReplayTests.bundledFixtureMatchesRepoFixture` — which itself only diffs the `.ndjson` pair, not `.trace`. The real fix is a build-time resource-generation step (a `Package.swift` plugin or a pre-build copy script) so there's exactly one file on disk. *Reopens when a recapture updates one copy and not the other, or when `Package.swift` next changes and touching the resource declaration is already on the table.*
- **Fork branch name contradicts the fork ledger's own stated structure
  (2026-08-29).** `.gitmodules` pins `p20-dispatch-schema`, a branch cut for
  P20's dispatch schema (divergence #12) that has since accreted #13, #13a,
  #13b, #14 and #15 — it is the integration line, but its name describes one
  of six things it carries. The ledger's divergence **#6** defines the intended
  structure as `swiftstar-integration` = `laguna-s2.1` + patch set, and a
  branch by that name exists but is a **strict ancestor** (307 behind, 0
  ahead), so it is a stale marker rather than an alternative. P23's plan
  already listed *"reconcile `.gitmodules` vs the pinned branch"* as blocking
  task 0b; it was worked around instead. Fast-forwarding `swiftstar-integration`
  and repointing `.gitmodules` is mechanically trivial — **the cost is that
  9+ research documents name `p20-dispatch-schema` as the branch a given
  divergence lives on**, and those are historical records that should not be
  rewritten, so the rename owes a ledger note saying when it happened.
  *Belongs in P26's hygiene work, not a tired end-of-day rename.*

- **The strict docs build has been failing on `main` since before 2026-08-29.**
  `just docs` (`sphinx-build -W`) fails on two documents that are in `docs/`
  but in no toctree (`glossary.md`, `2026-08-26-old-ui-element-inventory.md`).
  Verified by building with and without the day's new file. Not caused by this
  work — `docs/pathologies.md` was added to the toctree so it adds no third
  warning — and deliberately not fixed inside an unrelated commit, since a
  silently red gate is worth seeing. *Reopens the next time anyone relies on
  the docs gate to mean anything.* *Fixed 2026-08-29: both documents added to
  a toctree in `docs/index.md` (glossary into the main hidden toctree,
  the old-UI inventory into a new "Archive" toctree); `just docs` is green.*

- **Smaller items parked with it (2026-08-29).** (a) `main.swift`'s 18
  `exit()` calls skip their `defer`s, so a FAIL orphans the engine and leaks
  the worktree — worked around all day by the driver's reaper and sweeper,
  never fixed at source (~1–1.5 h). (b) `RepairLoop.swift:215` returns
  `.exhausted` on a zero-heading harvest, abandoning remaining rounds; the
  change is ~15 min but alters repair semantics, and its **only** validation
  surface is the Mellum fixture tier, so it should wait for P18 rather than
  ship unvalidated. Note the *other* `contractNotFollowed` site (line 119) is
  a deliberate refusal and must not be "fixed" by pattern-matching the
  receipt name. (c) A second temp-dir leak class, `swiftstar-wt-*` dispatch
  worktrees, dating to 2026-08-25 — distinct from the `agenttest-*` dirs
  already swept, and still uncovered by any sweeper. (d) A standing guard
  against under-specified authored prompts: **four instances in one day**
  (P17's "exactly one file", the singular emission follow-up, the directive's
  silence on dispatch ordering, the missing `projectContext`). Form is an open
  question — test, lint, or review step — and picking wrong yields something
  that gets disabled in three months.

- **Golden agent capture predates the wire's `kind` field — the kind-driven
  tool card has no fixture test.** `fixtures/agent/golden-tools.ndjson` was
  captured before the engine's `param_begin` events carried `kind`
  (`ds4_agent.c:9197` pins `"kind":"path"`), so `ToolParam.kind` /
  `ToolCard.path` enrichment is verified only by the 2026-08-26 live probe
  (`/tmp/swiftstar-probe/wire.ndjson`, Laguna-XS Q4_K_M, exact app argv) and
  the engine's own C tests — not by any committed fixture. *Reopens as: a
  complete clean agent run against the real binary (submodule-pinned), a
  fresh `golden-tools` recapture with provenance, and a fixture test
  asserting `kind`/`path`/`finished` populate from it.*

- **P6 has no verification record**, unlike P1–P5 and P7–P11. Not a defect in
  the phase — the analyzer and its fixtures are committed and tested — but the
  house convention is a record per closed phase, and P6's absence was only
  noticed during the 2026-08-25 P12 audit. *Reopens if the diagnostics tier is
  ever revisited, or as cheap cleanup alongside another docs pass.*

- **Warm-started metrics for `swiftstar-agenttest`.** Wall-clock elapsed and
  context/token counters currently start (`runStart = Date()`,
  `Sources/swiftstar-agenttest/main.swift`) *before* `PoolOrchestrator` is
  constructed — i.e. before the engine attaches to Metal and the weights are
  mapped in. On a cold page cache this can add real seconds (observed:
  ~200ms warm, ~4.6s on one cold load this session) that have nothing to do
  with task performance, and it's exactly the wrong number for the question
  people actually ask — "how fast does this run in the middle of a work
  session," not "how fast including the one-time engine boot." Fix
  direction: attach the engine, run one throwaway minimal prompt ("hello
  world" or similar) to absorb first-prompt-specific setup cost, *then*
  start every counter this harness reports (wall-clock, `ctx_used`, tool
  calls) from that point. One number, not two — the warm-up is a discarded
  pre-step, not a second reported figure. *Reopens when someone needs a
  trustworthy wall-clock/context comparison from this harness again* (it
  already bit one such comparison this session — see
  `.superpowers/sdd/2026-08-24-p12-4-repair-role/progress.md` if that
  session's ledger is still around). Source: this session, 2026-08-25.

- **Agent harness (Pi) tooling: lazy Context7 stays, Superpowers goes lazy.**
  The dev harness runs both as Pi packages (`npm:@upstash/context7-pi`,
  `git:github.com/obra/superpowers`). Context7 already ships the right shape —
  two natively registered tools (`resolve-library-id`, `query-docs`) plus a
  progressive-disclosure skill; it costs ~160 tokens of description in the
  system prompt and nothing else until a library question matches, with no
  forced load. OpenCode's `ctx7` CLI route (`npx ctx7@latest library|docs` via
  AGENTS.md) is the fallback, not the target. Superpowers is the outlier:
  `.pi/extensions/superpowers.ts` force-injects a ~1.1k-token bootstrap (the
  `using-superpowers` body + a Pi tool mapping) into the first agent run of
  every session and again after each compaction — redundant with its own
  discoverable skill description, and heavy on small windows (8–16K contexts:
  11–22% peak overhead). Measured always-on cost is ~700 tokens of skill
  descriptions, every prompt; the bootstrap is transient and never persisted
  (verified against all 40 stored session files). *Reopens as: a small
  Pi-harness work item — (1) drop the `context` bootstrap injection (an
  override/local extension, so it survives git-package reconciles), (2) trim
  the skill list and verbose descriptions via a settings `skills` filter,
  (3) optionally gate the rest with `disable-model-invocation` — validated by
  re-measuring system-prompt + first-run token cost on the real
  small-context models.* Source:
  [`2026-08-27-pi-harness-context7-superpowers.md`](docs/superpowers/research/2026-08-27-pi-harness-context7-superpowers.md).

### Declined

- **A menu-bar extra.** Explicitly declined 2026-08-21. *Reopens only on a
  direct request; the at-a-glance glance is the one thing it was good for.*

## Prior work

Completed phases P0-P15 are narrated in detail in [`docs/superpowers/research/prior-work-archive.md`](docs/superpowers/research/prior-work-archive.md); the phase table above and each phase's own verdict/closure doc carry the current status.

## Workflow

This repository runs on spec-driven development — see [`docs/sdd.md`](docs/sdd.md).
Each phase gets a committed design spec, then an implementation plan, then code.
The default test suite needs no model, no network, and no subprocess; process
behavior lives in a marked integration tier; and anything needing real weights
lives in a live tier that never runs in CI.
