# Roadmap

> **Planning surface, not the front door.** Where the current phase, the concept
> budget, deferred candidates, and the backlog live. Not where a new reader
> should start — see [`README.md`](README.md) for what this is, and
> [`BRIEF.md`](BRIEF.md) for the settled design.

*Phases group feature cycles. One direction at a time. Tangents go to the
Backlog, not into the current phase.*

## Now

**P18: build `mellum-fixture` — a small, one-shot benchmark. Not another
repair loop.**

**Also landed 2026-08-26 (out-of-phase, now formalized as P19–P21):** the app
is one Agent surface (Chat retired), with the ported UI, Settings, per-turn
summaries, subagents in the one engine (`--subagent-pool N`, `/chat`,
smart/dumb lever), and live session capture — see the phase table. The forward
sequence is **P22 (Laguna XS + model switching)** then **P23 (wire-level think
control)**, then **P24 (digested first-class tools)**; power pacing stays in the Backlog until P21's power measurement
reopens it. P19–P21 were done on `main` outside the phase structure and are
recorded here to keep the trail honest. Which of these ideas have live
evidence: the [`2026-08-26 evidence report`](docs/superpowers/research/2026-08-26-evidence-report.md).

P17 answered the original repair-limit question — see
[`2026-08-26-p17-repair-limit-verdict.md`](docs/superpowers/research/2026-08-26-p17-repair-limit-verdict.md).
Mellum's multi-file repair failure was **predominantly a harness defect**: the
repair directive asserted "Exactly one file is wrong" on every cell, including
cells where three were. With it removed, repair depth stops predicting failure
(1/2/3-file editing tasks: 6/6, 4/5, 5/6 pooled; the clean framing arm
`framing-2-edit` scored 5/6 against `depth-2`'s 4/5, so evidence shape is not
the limit either) and the round budget has no measurable effect on editing.
**Mellum on 15/17 editing cells is a genuine result: a bounded, reliable
single/multi-file editor.** The surviving difficulty is **authoring a file from
scratch whose contract is only implied by the tests** (1/6) — a different
capability, not a deeper case of the same one.

**Why not a second attempt at optimising the repair loop (`/goal` v5,
retired):** it tried to measure whether extra rounds or targeted feedback
improve editing, using the same pipeline/fixture apparatus. Its dev screen
could not resolve an effect from engine sampling noise at the sample size
tried — a byte-identical prompt at a fixed seed swung outcome 2/3 → 0/3 between
runs — and continuous regrading of its three result sets (not just binary
pass/fail) showed no arm moving against another outside that noise
(95.2% / 92.3% / 94.9% on the 20 of 36 cells with a scoreable grade). Retired,
not concluded: see
[`goal-ledger-v5.md`](docs/superpowers/research/superseded/goal-ledger-v5.md)'s
closing entry. **Give up on tuning Mellum's multi-round loop with this
apparatus, not on Mellum as an editor.**

**P16's ">=10 valid Mellum pipeline cells" stays demoted.** It was a proxy for
the repair-limit question, already answered more cheaply at fixture tier.

**P18's shape, deliberately boring:**

1. **Fixture-only, one task family per run.** Start with "repair visible
   files" (editing). Keep "author a missing file from implied tests" as a
   *separate* benchmark — P17 shows it is a different capability, not a harder
   version of the first.
2. **One attempt, no repair rounds, no prompt interventions.** A pinned broken
   tree, the writable files, an explicit task/acceptance contract. Capture
   output, apply it, grade it. Nothing self-modifying.
3. **A flat oracle**, not a collection-gated pytest run: 13 independently
   evaluable requirements, each pass/fail, even when imports fail. Pre-register
   both the primary metric (all 13 pass) and the secondary (count passed) —
   partial scores real from the start, not retrofitted after a binary metric
   turns out to have no resolution (as v5's did).
4. **Freeze the prompt and fixture manifest before sampling.** ~10–20
   fresh-process trials per fixture, shuffled across fixtures. Raw packet,
   engine argv, output, resulting tree, and requirement vector are the record.
   Never overwrite or rerun a recorded cell.
5. **Only then, as a separate bounded comparison**, test rounds: if one-shot
   results are stable, compare exactly one predeclared feedback policy (e.g.
   1 vs 3 rounds) on the same fixtures and oracle. No prompt tuning between
   arms.

**A new, standalone `mellum-fixture` runner, not an extension of
`swiftstar-agenttest`.** Near-zero policy: construct fixture → call Mellum →
apply output → independently score → save artifacts. It answers one narrow
question — what can this Mellum configuration do on explicit, pinned repair
tasks — and does not diagnose the pipeline, repair its own methodology, or turn
every surprising result into another feature.

## Concept budget

*Every term below is a cost against the reader's ability to hold the design in
mind. Checked at the end of each phase; a term earns its place by naming
something the design actually needs, not by being convenient shorthand.*

Seed terms, to be defined in this repository's own words when the phase that
needs each one lands: **patch set**, **shipped integration**. (The
seed terms **handoff packet** and **candidate ref** were defined by P10 and now
appear below.) Defined so far:

- **feasibility** (P3) — the engine's startup memory plan vs. available RAM,
  computed, with an actionable refusal (deficit, levers, re-check number).

- **seam** — the spawned-child-plus-wire boundary between the app and the engine.
- **wire** — the byte stream on that seam (P2: SSE from `ds4-server`).
- **capture** — a byte-for-byte recording of the seam (wire + stderr + trace),
  timestamped on the wire and anchored in wall-clock by its provenance.
- **handshake** — the wire's first line: a version/capability `hello` object; a
  consumer refuses a mismatch loudly (binding rule 7).
- **trace** — the engine's `--trace` channel, a separate timestamped file carrying
  what the wire suppresses (compaction rebuild stats); captured alongside the wire.
- **fixture** — a committed capture used by tests.
- **finding** (P6) — a machine-computed diagnostic result: a typed value with a
  severity and the computed numbers it reports; phrased by a deterministic
  renderer now, a model later.
- **baseline** (P6) — a session's own early prefill throughput (highest
  `prefill_tps` at `ctx_used ≤ 8,192`), against which later throughput is
  compared; the session measures itself, no external calibration.
- **diagnostic** (P6) — a finding the analyzer computes from a capture, never a
  model's judgment. The model only phrases.
- **workspace** (P7) — the confinement root plus the cwd the app grants at
  spawn (`--workspace`); the file tools (`read`/`more`/`write`/`list`/`edit`/
  `search`) fail closed outside it — an unresolvable or escaping path is
  refused, not silently `chdir`'d.
- **tool card** (P7) — the transcript's per-call reconstruction of one tool
  invocation from the wire's phase stream (`start`/`tool`/`param_*`/`output`/
  `finish`); appended at the `tool` phase, mutated in place by `param_end`/
  `output`/`finish`, keyed by `idx` scoped to the current block.
- **turn outcome** (P7) — the capture-grade per-turn record (model/build/sampler
  and task, token and context use, stop reason, and each tool-call lifecycle
  transition) that P10's handoff packets consume instead of trusting the
  transcript's prose.
- **bootstrap** (P8) — the deterministic skills index `SuperpowersBootstrap`
  renders from a skills dir (`name`/`description` front-matter, sorted by name,
  one line per skill), passed to the agent via `ds4-agent -sys`; the engine's
  existing `sysprompt.kv` rebuild-on-mismatch makes it "prefilled once." A
  missing skills dir degrades to "No skills available in this workspace."
  rather than fabricating skills the agent cannot `read`.
- **progressive disclosure** (P8) — the index lives in the system prompt; the
  full skill bodies are staged into the workspace (`.swiftstar/skills/<name>/`)
  at spawn and `read` on demand inside the workspace grant. The bootstrap never
  inlines skill bodies, so the agent pays the prefill cost only for the skills
  it loads.
- **tool request** (P9) — the `--host-tools` wire event the engine emits on stdout
  when the host owns execution: `{"t":"tool_request","idx":N,"name":"<tool>",
  "params":[…],"ts":<µs>}`, one per tool call in a block. The engine blocks on a
  matching `tool_result` from stdin; a mismatched `idx` or any non-`tool_result`
  line is a loud refusal. `hello` advertises `"tool_request"` in `caps` iff the
  flag is set.
- **tool result** (P9) — the host's answer on stdin:
  `{"t":"tool_result","idx":N,"ok":true|false,"s":"<condensed result text>"}`.
  `ok:false` is a result, not an absence — the engine consumes it and continues.
  The `s` is condensed (`ToolResultCondenser`, cap 8000) before it enters KV.
- **host tool execution** (P9) — the app owns tool execution: with `--host-tools`,
  the engine emits `tool_request` and blocks; the app's `ToolCallbackResponder`
  enforces the workspace/shell consent, executes the call, condenses the result,
  writes the `tool_result` back, and records the host facts into the per-turn
  `TurnOutcome`. Without the flag the engine executes internally and the wire is
  observation-only.
- **handoff packet** (P10) — the typed contract a dispatched attempt runs under:
  `taskText`, the exact `writableFiles` (worktree-relative), the
  `validationCommand` the parent will actually run, a per-file `FileBaseline`
  (`sha256` + `lineEnding` + Unix `mode`) read from the worktree at dispatch time
  rather than guessed, and turn/tool-call budgets. The worker gets
  `read`/`write`/`edit` (+`list`/`search` as read aids) and no `bash`; every
  mutation is revision-checked against `writableFiles`. It consumes the P9
  host-authoritative facts — success is never inferred from prose.
- **candidate ref** (P10) — the reviewable commit a dispatched attempt returns
  when the turn ends without a revision-check violation and (when the packet's
  `validationCommand` is set) the validation passes: the dispatcher commits the
  worktree's diff to a throwaway branch and returns the SHA. The ref resolves via
  `git rev-parse` after the worktree is removed (the commit object survives); the
  parent reviews it. Nothing merges.
- **receipt** (P10) — the typed refusal a dispatched attempt returns otherwise,
  naming the reason: a mutation outside `writableFiles` (`.refusedTool`, first
  offending path), a turn/tool-call budget exceeded (`.budgetExceeded`), the
  validation command failing (`.validationFailed` with exit status + stdout
  digest), or no mutations (`.noChanges`). The reason is machine-computed from the
  P9 `TurnOutcome`, not inferred from the transcript.
- **revision check** (P10) — the membership test a dispatched attempt runs on
  every mutation: a `write`/`edit` whose workspace-relative path is not in the
  packet's `writableFiles` is refused host-side (`ToolCallbackResponder.consent`
  refuses the tool, does not execute, does not record it), so an out-of-set write
  never lands in the worktree. Two checks by design: the host-side refusal is the
  production confinement; the pure verdict's `.refusedTool` is the backstop (a
  mutation that *is* in `allowedMutations` but outside `writableFiles` — a
  symlink escape, or the integration test's scripted mutation).

- **rolling digest** (P11) — the objective-independent "always-want" reduced
  form of the conversation, maintained incrementally and inference-free by the
  host: strip tool noise, keep the host-authoritative ledger (files touched,
  refs, receipts, exit statuses). Backed by the session `.kv` rendered text for
  crash recovery. The packet-maker's extraction reads this, never the raw
  conversation — Layer 1 of context distillation, pre-chewed before the
  objective is known.

- **context assembly** (P11) — the packet-maker's `deterministic-load → rolling
  digest → adaptation → packet` pipeline: the `dispatch` tool's objective plus
  the digest plus staged read names plus the deterministic adaptation (D7) become
  a *prepared* packet `taskText`, not P10's bare sentence.

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
| P13 | More models | Laguna XS 2.1 and/or Mellum 2.1 as first-class variants — **neither line has a shipping artifact yet**; deferred behind P12 so there is a harness that can actually evaluate a variant | complete (2026-08-25) — verdict: blocked on Mellum's tool-call **initiation** gate. **The broader "competence, not the harness" reading was overturned:** P15 found the action mode harness-addressable, and [P17](docs/superpowers/research/2026-08-26-p17-repair-limit-verdict.md) found the multi-file repair failure was *predominantly a harness defect* (a directive asserting "exactly one file is wrong" on every cell) — with it removed, repair depth stops predicting failure and Mellum edits 15/17. The residual limit is authoring from an implied contract (1/6), not repair depth. Corrected 2026-08-27 |
| P14 | A docs site | Sphinx content and Pages publishing, once there is a reader who isn't the author | planned |
| P15 | Host-controlled action mode | The model drafts as text (`#path` + fenced blocks), the host harvests, writes, and verifies — isolating "should I act" from content competence for Mellum-class models; exit is a verdict, not a product | complete (2026-08-25) — verdict: **harness-addressable**; repair 4/4 at 13/13, build 3/9 at 13/13 with 0 tool calls |
| P16 | Repair harness validity | Fix the four defects (round-discard, collection gate, packet budget, withheld phase brief) blocking any real measurement of Mellum's repair competence, driven by a validity-gated `/goal` loop | **demoted, not resumed** — superseded by P17's cheaper fixture-tier answer; `/goal` v1-v3 closed without meeting their goals, see [`goal-ledger.md`](docs/superpowers/research/goal-ledger.md) and [`goal-ledger-v3.md`](docs/superpowers/research/goal-ledger-v3.md) |
| P17 | Repair-limit fixture experiment | Pre-registered fixture-tier experiment answering whether Mellum's multi-file repair failure is a budget, framing, or depth limit; then a follow-on attempt to optimise the repair loop itself | **complete (2026-08-26)** — verdict: predominantly a harness defect (a false "exactly one file" directive), not the model; Mellum 15/17 on editing tasks; the follow-on optimisation attempt (`/goal` v5) retired without a resolvable result — see [`2026-08-26-p17-repair-limit-verdict.md`](docs/superpowers/research/2026-08-26-p17-repair-limit-verdict.md) and [`goal-ledger-v5.md`](docs/superpowers/research/superseded/goal-ledger-v5.md) |
| P18 | `mellum-fixture` benchmark | A small, one-shot fixture benchmark for Mellum: one attempt, a flat 13-requirement oracle, frozen pre-registered manifest, no repair rounds, no self-modifying loop — separate from `swiftstar-agenttest` | **planned** |
| P19 | One surface | The Agent is the app: Chat retired (the `ds4-server`/SSE path, `EngineController`, the tab), the ported Agent UI (composer, workspace picker, status bar + rings, message rendering, tool cards), Settings (shell toggle, font-size slider), per-turn summary on bubbles | **landed 2026-08-26** — Chat retirement `f546671`; UI port `ebfc046`; Settings `5d7c1de`; turn summary `8b9710b`; stop-button fix `478d871`. See the [`agent-surface-port verification record`](docs/superpowers/research/2026-08-26-agent-surface-port-verification-record.md) and the [`old-ui element inventory`](docs/2026-08-26-old-ui-element-inventory.md). Reopened and **complete 2026-08-27**: **P19.0** (consulted answer styling, stable-row-ID decision) and **P19.1** (the app shell) — a Tahoe-forward `NavigationSplitView` shell with a real customizable toolbar, collapsible sidebar, Settings moves (pool size, session capture, smart/dumb default, workspace default), one toolbar model choice with the engine lifecycle hidden, a component/region design vocabulary, and the Swift 6 concurrency gates. See the [`P19.1 design`](docs/superpowers/specs/2026-08-27-p19-1-app-shell-design.md) |
| P20 | Delegation in one engine | Subagents without a second process: the app's agent spawns with `--subagent-pool N`; `/chat` (manual → pool-routed → answer surfaced); smart/dumb handoff-packet lever + dumb-mode dispatch refusal; restart-safe pool state | **mostly landed 2026-08-26** — pool routing `00b5d80`; orchestrate `52257b8`/`95ac5c3`; dumb lever `2011203`/`53b7ee5`; pool reset `3e07b54`; real-engine pool protocol test (worker prompt → `pong`, one process, two sessions). Forward: **dispatch-preference bootstrap rule** (prefer dispatch after ~N exploration rounds), **two-phase `/spike`**; **small-ctx workers** (the RLM lever — may split into its own phase: engine patch, fork-ledger row, recapture) |
| P21 | Measurable sessions | Telemetry you can act on: live session capture (wire + trace + stderr per spawn under `captures/live/`), the telemetry analyses (heavy-session compaction, spike shell-on findings) | **landed 2026-08-26** — capture `96fcc49`/`4e7cb3a`. See the [`heavy-session findings`](docs/superpowers/research/2026-08-26-heavy-session-telemetry-findings.md) and the [`spike shell-on findings`](docs/superpowers/research/2026-08-26-spike-shell-on-findings.md). Forward: the **DumbImplementer eval** (design around Σsuffix — Σprompt double-counts, so Σcached/Σprompt is not a cache-hit rate), and **expose the wire's `power` field** (already emitted; the parser drops it) as the first step toward the power question. The kind assertions and the DialLogic re-anchor landed 2026-08-27 — the fixture already carries kinds (no recapture needed), and the anchors are re-anchored to the app's 50k (25k/37.5k; critical now reachable) |
| P22 | More models: Laguna XS + model switching | Laguna XS 2.1 as a first-class, choosable preset at parity with Laguna S — merge the unmerged `p13-laguna-xs-variant` branch (9 commits; its spec `2026-08-26-p13-laguna-xs-variant-design.md` lives on that branch), the completed live acceptance run, XS golden recapture — plus **model switching** (woven in): an "Apply this model" action that stops and re-spawns the agent with the new model, feasibility-/VariantGate-admitted *before* the stop (never kill a working session to switch to an infeasible model), transcript preserved, provenance per-spawn reflects the new model, pool re-spawns with it, switch refused mid-generation. XS is also the natural line for P20's small-ctx workers | **acceptance done 2026-08-27** — variant + engine-flag wiring shipped on `p13-laguna-xs-variant`; live acceptance green on the real engine with `--ssd-streaming`: agentclinic `roadmap` passed via `DS4_AGENT_TOOL_NUDGE=2` (13/13, verdict good), `roadmap-user-story` passed on defaults (13/13, verdict good); 614 declared tests on that branch (main: 552, of which 82 are integration-tier and do not run in the fast tier); GLM 5.3 APPROVE. See the [`acceptance verdict`](docs/superpowers/research/2026-08-27-p22-laguna-xs-acceptance-verdict.md). Forward: merge the branch — **fix its default model path first**: the branch resolves XS to `~/models/laguna-xs-2.1-RoutedQ3_K-biased.gguf`, but that directory holds only the Mellum file (the XS gguf is in `~/projects/ds4/gguf/`), so on merge the picker yields `.unreadableFile` unless `SWIFTSTAR_LAGUNA_XS_MODEL` is set — which is exactly what the acceptance run did, masking it. Note also the acceptance ran the **RoutedQ3_K** file, not the `Q4_K_M` one, which the branch's `downType: .q3_k` contract would refuse; **XS golden recapture**; **model switching** (the "Apply this model" action); **SSD support across the Laguna line** (Laguna S still refuses `--ssd-streaming` — the pin's gate admits XS21 only; the 6-line enabling commit `2613723` sits on local `laguna-s21-ssd`; merge → submodule bump → recapture, add a `laguna-s-2.1` Variant so the shared `EngineRuntimeConfig` carries the flags, then validate S-ssd footprint + DFlash interplay); 16 GB hardware acceptance (still unconfirmed — ran on 128 GB) |
| P23 | Wire-level control | Per-turn think on the agent wire (`reasoning_effort`-style): the no-think "quick reply" — Chat's use case surviving as a toolless fast turn, no restart. Additive engine patch, fork-ledger row | **planned** |
| P23.5 | DFlash: wire the draft model | `laguna-s-2.1-DFlash-Q8_0.gguf` (1.1 GB) sits on disk with **no code path**: `AgentCommand.argv` emits no draft-model flag, `Variant` has a single `modelFile` so a draft/target *pair* is unrepresentable, and `SamplerDefaults` is declared-only — and per [`engine-lines`](docs/harvest/engine-lines.md) DFlash engages only under **greedy** decoding while the Laguna default temperature is 0.7. Three independent reasons it cannot engage today, none of them recorded until now. *Needs: a draft-model field on `Variant`, `--dflash` + a temperature flag in argv, and a measured verdict (speculative decoding is a throughput claim — measure the paired bill, per P24's guardrail).* | **planned** (raised from a P22 sub-clause 2026-08-27) |
| P24 | Digested first-class tools | P9's deferred condensation direction, now motivated by the measured enemy: the sum of prefill tails, each taxed by depth (231→134 tok/s over 12k→27k ctx). Deterministic host-owned **tools** (no model, millisecond Swift): `test` (pytest → ~2 clustered representatives, lossless-for-the-decision, full output re-runnable), `scout` (index-backed locate), `lint` (ruff/pyrefly digests) — plus the ladder for the rest: **mediated bash** (host-run, deterministically digested, policy-gated, never raw) and **model-asks-human** for the novel; retires the shell-on expedient (2026-08-26). The model-backed half (ANE only phrases) stays in the ANE watcher tier Backlog entry, gated on the two AFM falsifiers. Naming: a **tool** is deterministic (no model); a **subagent** has a model in the loop. The other legs of the prefill-tail attack are already scheduled: P20's forward items (small-ctx workers, dispatch-preference) and P21's DumbImplementer eval (the measurement). Source: JetBrains RTK token-savings benchmark (2026-07) — the guardrail: a tool's self-reported savings are a claim about its counterfactual, not about your bill; measure the paired bill | **planned** |

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

Deferred, each with the condition that reopens it.

- **~~Chat as a separate surface~~ — RETIRED 2026-08-26 by product decision.**
  One surface: the Agent. Retire the Chat tab, the `ds4-server`/SSE wire, and
  `EngineController`; the app owns one `ds4-agent` process, one model load.
  Chat's use case survives as a toolless agent turn with per-turn think
  control. *Reopens as: its own phase — remove the Chat surface and fold a
  no-think "quick reply" mode into the Agent, with `reasoning_effort`-style
  per-turn control on the agent wire (additive engine patch, fork-ledger
  row).*
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
- **Small-ctx worker sessions for the pool (the RLM lever).** The app's
  `/chat` now runs its worker as a context-isolated session in the one
  engine, but at the *full* `-c` ctx — ~2.5 GB KV + ~6.15 GB scratch at 50k
  (`agent_worker_effective_ctx_size` reads the session ctx; there is no
  per-worker override). Correction 2 names the lever: a 4k worker is ~1.7 GB,
  not ~8.7 GB. *Reopens as P20's forward item (may split into its own phase):
  a small engine patch (fork divergence) giving pool
  workers their own ctx, or a kept-alive `rewind`-ed small-ctx template
  session — with a fork-ledger row and golden recapture, per the submodule
  rules. The Laguna XS line (P22) is the natural worker model.*
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
  cumulative — see the escalated entry directly below, no longer a
  hypothetical.
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
- **P6 has no verification record**, unlike P1–P5 and P7–P11. Not a defect in
  the phase — the analyzer and its fixtures are committed and tested — but the
  house convention is a record per closed phase, and P6's absence was only
  noticed during the 2026-08-25 P12 audit. *Reopens if the diagnostics tier is
  ever revisited, or as cheap cleanup alongside another docs pass.*
- **The harvest gate requires `stopReason == .eos`.** A turn that runs to the
  token wall is never harvested, so nothing is written and validation fails on
  an empty tree — 1 of 9 build runs. The repeated-heading abort could recover
  such a turn's first pass, but never sees it. Widening the gate touches session
  -exhaustion semantics, which differ per arm (repair reuses the worker across
  rounds; build handles exhaustion after phase finalization). *Reopens when
  token-wall runs are a measurable share of failures.*
- **Generation-time stopping control.** The engine's pool protocol has no cancel,
  so a degenerate run pays to the token wall before the host can react; the
  repeated-heading abort is harvest-time only. *Reopens only if engine-side work
  is on the table — it is the one P15 item that is not host-addressable.*
- **The lenient harvest blurs the failure taxonomy.** Without a fence there is no
  delimiter, so prose under an allowlisted heading is written as file content,
  and turns once classified `contractNotFollowed` can land as `validationFailed`
  instead. A content-vs-prose discriminator is deliberately *not* wanted: it
  would be a guard holding less information than the authoritative layer, the
  same mistake as the removed contract-blind pre-edit guard. *Reopens if a
  measurement needs to separate "ignored the contract" from "wrote buggy code" —
  the honest fix is a stricter emission contract, not a smarter parser.*

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
- **Specialized tool subagents** — split 2026-08-27 by naming: a **tool** is deterministic host code (no model — run one command in its JSON mode, digest the output); a **subagent** is the model-backed escalation (apply the fix when the run says what it is, or summarize when the deterministic digest isn't decision-adequate). The deterministic half — ruff, pyrefly, pytest, sphinx, roadmap admin run+digest — is now **P24's** direction (`test`/`lint`/`scout`); the subagent half stays here. Budgeted to fit an 8k context on AFM3; because Swift runs the evocation, repeated invocations make the limit a budget rather than a wall. The open question is dispatch — how the orchestrating model+agent decides which specialized agent to call. The economics are measured, not assumed: locally, prefill is the scarce resource, so deterministic work first is a *performance* rule — `ruff --fix` beats the model typing the same 40-line edit by ~500x, and clustering 40 pytest failures to 2 representatives turns a 178s prefill at depth into 9s (rates from `docs/harvest/telemetry-findings.md`; worked table in the ds4-control survey cited by `2026-08-22-p11-engine-constraints-and-corrections.md`). *Reopens when P11 lands and the pool design can hold a one-command worker, or as P24's subagent escalation; this is a candidate shape for P11's workers, not a phase of its own.* Source: P11 "Subagent pool".
- **The dispatch decision** — what the handoff packet maker must know to route a task, on three axes. **(1) Parallelism:** dependency edges declared by the plan author are authoritative; the maker may additionally *prove* independence from disjoint writable-file sets plus disjoint validation commands, and must refuse when it cannot — file-disjointness is necessary, not sufficient (an API change and its consumer share no file). **(2) Thinking requirement:** a task is delegable to a reasoning-light worker only when acceptance is a machine-checkable predicate, the tool surface is bounded (`read`/`write`/`edit`, no `bash`), and the writable-file set is exact — and thinking is a stage, not a property: "fix the broken test" needs diagnosis (thinking) before the apply is mechanical. **(3) Executor:** whether the packet goes to a full-context worker, to a deterministic **tool** (a one-command host run in its JSON mode — ruff, pyrefly, pytest, sphinx, roadmap admin — now P24's direction), or to a model-backed **subagent** that applies the fix when the run says what it is, with AFM3's 8k as the budget for the latter and repeat evocations for anything longer. The lesson travels with it: the maker enforces declared intent and computes conservative proofs; it never re-derives semantics with less information than the plan author — the same lesson as the removed contract-blind pre-edit guard. *This is P10's routing design; axis 3 is what the "Specialized tool subagents" entry feeds. Reopens when P10 is planned.* Source: P10 "Isolation", the "Specialized tool subagents" backlog entry.
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
- **Context-economy tooling** — two deterministic moves that exist because KV
  reuse is exact-prefix-only and prefill is the scarce resource: (1)
  *don't-re-read* — hash+mtime every file the agent has read and answer an
  unchanged re-read with "unchanged since turn N" instead of contents, worth
  up to ~130s per avoided deep re-read at measured rates; (2) *warm-prefix
  routing* — when a pool exists, route a task to the session whose live
  prefix already contains its files (`ds4_session_common_prefix` is free
  engine-side; needs a wire query). *(1) reopens with P9 — the host must own
  tool results to substitute them; (2) reopens with P11.* Source:
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
  something a later turn needed.* Source:
  `2026-08-22-p11-engine-constraints-and-corrections.md` and the ds4-control
  survey it cites.
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
  fires roughly once per full context). *Reopens when a compaction is
  actually observed at the everyday context size and its measured cost or a
  misremembered-summary incident justifies the fork.* Source: same note.
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
- **Recursive sub-queries — the RLM pattern as P11's third lifetime tier.**
  A project is a long-lived session; a subagent is a short-lived one sharing
  the parent's root; an RLM sub-query is an *ephemeral* session over a slice
  of a large input, whose result folds back into a root context that is
  deliberately kept small (Recursive Language Models, arXiv:2512.24601: flat
  scaling with input length *provided chunk size stays constant*). Same pool,
  three lifetime policies. The economics are this hardware's own: splitting
  a 131k prefill into eight sequential 16k prefills is up to ~4.2x cheaper by
  the measured curve, with no concurrency required — which is fortunate,
  since none exists (P11 bullet above). Two constraints a naive reading of
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
  costing a real turn.*
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
  first time) is measured.* **Split 2026-08-27:** the deterministic background files+symbols index (what feeds P24's `scout`) is P24's, not this tier's; this entry keeps the model-backed roles — the librarian's Monty reactions and the inspector as P24's ANE-only-phrases escalation when deterministic clustering isn't decision-adequate. Both stay AFM-gated. Source:
  `docs/superpowers/research/2026-08-23-monty-and-the-ane-watcher-tier.md`.
- **"Swift body, Python brain"** — agent policy in a hot-reloadable uv-managed
  peer process. *Reopens if agent policy starts changing faster than the app
  can ship.* Source: `SWIFTSTAR.md`.
- **A menu-bar extra.** Explicitly declined 2026-08-21. *Reopens only on a
  direct request; the at-a-glance glance is the one thing it was good for.*
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

## Prior work

Completed phases move here when the roadmap outgrows the front page.

- **P0 — Scaffolding (2026-08-21).** Repository, `.gitignore`, license, docs
  toolchain (uv + Sphinx + MyST + Furo, `just docs` / `just watch-docs`), the
  `docs/superpowers/` structure, `BRIEF.md`, this file, and the harvest briefs.
  The design session that produced them, including the rejected alternatives and
  the adversarial review that corrected two of them, is recorded in
  [`docs/superpowers/specs/2026-08-21-swiftstar-design.md`](docs/superpowers/specs/2026-08-21-swiftstar-design.md).

- **P1 — The fork, consolidated (2026-08-22).** `pauleveritt/ds4` exists as a
  fork of `antirez/ds4`; the app-required patch set (`--json-events`,
  turn-interrupt, status marker, stale-interrupt latch, startup memory plan)
  is absorbed into one shipped integration branch; a documented command
  builds `ds4-server` and `ds4-agent` from the submodule; the fork ledger and
  `docs/upstream-proposals.md` are in place; two golden captures — SSE from
  `ds4-server`, NDJSON from `ds4-agent` — are taken from the real binaries by
  a throwaway line-stamping script (`swiftstar-drive` did not exist yet;
  P5 replaced the script and is the only sanctioned source of a fixture from
  P5 onward). Spec:
  [`docs/superpowers/specs/2026-08-21-p1-fork-consolidated-design.md`](docs/superpowers/specs/2026-08-21-p1-fork-consolidated-design.md).

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

- **P3 — It can get its weights (2026-08-22).** A chunked parallel HTTP-Range
  downloader (`ChunkedDownload` + `DownloadBitmap`, resume-safe across
  restarts) and `Feasibility.check` — pure arithmetic on the engine's own
  `planned_bytes` from a real `ds4: memory:` boot line, refusing an
  infeasible launch with an actionable message rather than a percentage
  heuristic. Two real bugs found by the tests, not review: the range test
  server died on SIGPIPE and served the wrong byte range on an early client
  close; `SwiftStarAppKit` was split out of the app target because
  `@testable import SwiftStar` (an executable importing SwiftUI) fails to
  link — the download runner and its state moved to the testable library,
  the app stayed thin. *(Later correction, 2026-08-22: `Feasibility.check`'s
  design is right, but on Laguna the engine's own `planned_bytes` itself
  omits ~6.1 GB of per-session GPU scratch — see the P3 dependency bullet
  above and
  `docs/superpowers/research/2026-08-22-p11-engine-constraints-and-corrections.md`.)*
  Spec: [`docs/superpowers/specs/2026-08-22-p3-it-can-get-its-weights-design.md`](docs/superpowers/specs/2026-08-22-p3-it-can-get-its-weights-design.md).

- **P4 — It shows what the machine is doing (2026-08-22).** `SwiftStarKit` gains
  the wire telemetry model (`WireEventParser` for NDJSON `status`/`ready`, the
  ratcheting `MetricsReducer`, and `DialLogic` — absolute context thresholds,
  generic memory thresholds, fixed-width formatting, sanitization) plus the
  `MachineSnapshot` type. `SwiftStarAppKit` gains `ProcessStatsCollector`
  (`proc_pid_rusage` footprint, `host_processor_info` CPU, `IOAccelerator` GPU,
  private `IOReport` watts — linked via `.linkedLibrary("IOReport")`) and
  `FixtureReplay` (bundled `golden.ndjson`). `SwiftStar` gains the `MetricsModel`
  + `MetricsView`, replacing the placeholder: a severity-colored context ring
  with a widened hit region, fixed-width Prompt/Decode readouts, and a
  capture-replay banner. The lead dials (`ctx_used`, throughput) are
  fixture-replayed until P7's agent migration; memory/GPU/CPU/power are live.
  Spec: [`docs/superpowers/specs/2026-08-22-p4-it-shows-what-the-machine-is-doing-design.md`](docs/superpowers/specs/2026-08-22-p4-it-shows-what-the-machine-is-doing-design.md).

- **P5 — Capture is a program, not a lost file (2026-08-22).** `swiftstar-drive`,
  a committed executable target, drives the real `ds4-agent` and writes the fixed
  capture format (`wire.ndjson` + `wire.stderr` + `wire.trace` + `provenance.md` +
  `progress.log`), byte-verbatim. Fork divergence #7 gives the `--json-events` wire
  a version/capability `hello` handshake (first line) and a monotonic `ts` on every
  event, retiring the P1 receive-time sidecar. `WireEventParser` enforces the
  handshake (refuses loudly on a mismatch) and reads `ts`; `CaptureWriter` (Kit)
  pins the format; fixtures are recaptured with the handshake + `trace` + `stderr`.
  The `--trace` channel (compaction rebuild stats) is now captured, which is what
  P6's "would compaction help" needs.
  Spec: [`docs/superpowers/specs/2026-08-22-p5-capture-is-a-program-design.md`](docs/superpowers/specs/2026-08-22-p5-capture-is-a-program-design.md).

- **P6 — Diagnostics that can't lie (2026-08-22).** `SwiftStarKit` gains
  `TraceParser` (parses the `--trace` channel: `compacted` rebuild stats and both
  `prefill sync done` shapes), `DiagnosticsLogic` (baseline/current prefill
  extraction, degradation and cache-health bands, all re-anchorable constants),
  the typed `Finding`/`CompactionVerdict` model, `DeterministicPhraser` (the
  "compute vs. phrase" seam — a model phraser can replace it later), and
  `DiagnosticsAnalyzer`, which computes the BRIEF's first job deterministically:
  where you are in context, current prefill throughput, drift off your own
  session's baseline, and — deep *and* degraded — whether compaction would help
  (distinguishing "cache healthy → won't fix the rate" from "cache missing → may
  recover"). The Diagnostics tab replaces its placeholder with a fixture-driven
  list of findings. Evidence floor met: the analyzer accepts the real `golden`
  capture and rejects a committed synthetic `pathological` fixture reproducing
  the measured 7x curve. No live engine, no model, no engine patch.
  Spec: [`docs/superpowers/specs/2026-08-22-p6-diagnostics-that-cant-lie-design.md`](docs/superpowers/specs/2026-08-22-p6-diagnostics-that-cant-lie-design.md).

- **P7 — Agent mode (2026-08-22).** The Agent tab is real. `SwiftStarKit`
  gains `AgentWireParser` (the NDJSON transcript parser — `hello`/`status`/
  `ready`/`text`/`think`/`tool`/`queued`, handshake-enforced, with the `ready`
  turn-outcome fields), `AgentTranscript` (the tool-card reducer — one card per
  call, keyed by block-scoped `idx`; the `tool` phase appends, `param_end`/
  `output`/`finish` mutate in place), `TurnOutcome`/`TurnOutcomeBuilder` (D12's
  capture-grade per-turn record — model/build/sampler + task, token/context use,
  stop reason, tool-call lifecycles), and `AgentCommand` (the one argv contract —
  `--workspace` + `--shell`). `SwiftStar` gains `AgentController` (spawns
  `ds4-agent`, drains the wire → transcript, writes ETX on interrupt, builds one
  `TurnOutcome` per turn) and `AgentView` (the transcript with tool cards, the
  composer, the interrupt button, the consent controls). The engine
  (`ds4_agent.c`) gains `--workspace` (cwd + file-tool confinement — fail closed)
  and `--shell` (gate `bash` in schema + dispatch), plus the turn-end `ready`
  fields (`stop_reason`/`generated`/`ctx_used`, D12). Two fixtures: `golden.ndjson`
  recaptured at the new SHA, `golden-tools.ndjson` new — five tool blocks
  (`read`/`list`/`write`/`edit`/`bash`) whose five turn-end `ready` events each
  carry `stop_reason`. The fake `ds4-agent` is generated from the real capture,
  never hand-authored. Evidence floor met: the fixture yields turn outcomes with
  the full tool lifecycle and a typed stop reason; the fake validates the exact
  argv and honors ETX. Live Metrics/Diagnostics wiring deferred (D9 — see the P4
  bullet's dated correction).
  Spec: [`docs/superpowers/specs/2026-08-22-p7-agent-mode-design.md`](docs/superpowers/specs/2026-08-22-p7-agent-mode-design.md).

- **P8 — Skills (2026-08-22).** The Superpowers bootstrap is real. `SwiftStarKit`
  gains `SuperpowersBootstrap` — a deterministic index rendered from a skills
  dir (`name`/`description` front-matter, sorted by name, with a generic
  disclosure path), passed to the agent via `AgentCommand`'s new
  `systemPrompt: String?` → `-sys <text>` (appended after `--shell`).
  `SwiftStarAppKit` gains `SkillStager` — a recursive `FileManager` copy of the
  skills tree into `<workspace>/.swiftstar/skills/` at spawn, idempotent
  (removes a pre-existing destination), throwing on a missing skills dir
  (non-fatal degrade). `AgentController` resolves the skills dir
  (`SUPERPOWERS_SKILLS_DIR` else the default), stages (a throw logged and
  non-fatal), builds the bootstrap, and sets `settings.systemPrompt` before the
  spawn argv is built — so the fake's strict-argv validation carries the same
  deterministic bootstrap. Progressive disclosure: the index names skills; the
  agent `read`s each body on demand inside the workspace grant (D5 — never
  fabricate a dispatch call). No engine patch (D4 — `sysprompt.kv` already
  rebuilds on mismatch). Evidence floor met: the bootstrap names every skill;
  the staged workspace contains them; the fake's expected argv carries the
  bootstrap it validates.
  Spec: [`docs/superpowers/specs/2026-08-22-p8-skills-design.md`](docs/superpowers/specs/2026-08-22-p8-skills-design.md).

- **P9 — The tool-callback wire (2026-08-22).** The host owns tool execution.
  The engine's `--host-tools` flag (fork divergence #10) makes
  `agent_execute_tool_calls` emit one `tool_request` per call on stdout and block
  on a matching `tool_result` from stdin (the worker thread owns the blocking
  read, gated by `host_tool_reading` so the UI thread's prompt poll does not
  steal the result line); a mismatched `idx` or any non-`tool_result` line is a
  loud refusal. `hello` advertises `"tool_request"` in `caps` iff the flag is
  set. `SwiftStarKit` gains `.toolRequest` on `AgentWireParser`, a pure
  `ToolResultCondenser` (cap 8000, deterministic digest), and
  `ToolCallbackResponder` (the consent matrix — file tools proceed inside the
  workspace, escapes refuse, `bash` is shell-gated, web tools always refuse —
  plus execution and the condensed `tool_result` line); `FakeAppSource` is the
  fake app side (keyed canned answers + the fixed refusal). `AgentController`
  routes `tool_request` → responder → `tool_result` over stdin and records the
  host facts into the per-turn `TurnOutcome`. The round trip is
  `FakeHostToolsIntegrationTests` (a fake agent compiled from `golden-tools.ndjson`
  with `hostTools:true` ↔ a fake app; the agent emits one request per block,
  blocks, the app answers, the agent continues to `eos`; `ok:false` still
  continues). The live recapture at `c21b831` re-verified the bare wire is
  unchanged (D1: `tool_request`-free, observation-only) and caught a real defect —
  the `741f722` edit dropped the `"]"` closing the `hello` `caps` array, emitting
  invalid JSON the wire consumer refused; the `c21b831` amend closes it and adds
  `test_agent_emit_hello_caps_array_closes` (red-then-green). Spec:
  [`docs/superpowers/specs/2026-08-22-p9-tool-callback-wire-design.md`](docs/superpowers/specs/2026-08-22-p9-tool-callback-wire-design.md).

- **P10 — Isolation (2026-08-22).** A dispatched attempt is isolated.
  `SwiftStarKit` gains `HandoffPacket` (`taskText`, `writableFiles` exact and
  worktree-relative, `validationCommand`, per-file `FileBaseline` baselines —
  `sha256` + `lineEnding` + Unix `mode` read from the worktree, never guessed —
  and turn/tool-call budgets), `DispatchOutcome` (`.candidate(ref:turnOutcome:)`
  | `.receipt(Receipt)`; `Receipt` = `.refusedTool`/`.budgetExceeded`/
  `.validationFailed(exit:digest:)`/`.noChanges`), and the pure
  `WorktreeDispatch.verdict` — the `request → verdict` mapping (revision check →
  budget → validation → `noChanges` → candidate) plus `relativize` (strip the
  worktree prefix so the verdict compares worktree-relative forms against
  `writableFiles`). `SwiftStarAppKit` gains `WorktreeDispatcher.dispatch` (creates
  a disposable worktree on a throwaway branch, reads baselines, runs the
  validation command parent-side, commits the diff, returns the ref; the worktree
  + branch are removed in `defer`, the commit object survives so the ref
  resolves). `SwiftStar` gains the dispatched-attempt entry in `AgentController` —
  a fresh, ephemeral `ds4-agent` at `--workspace <worktree>` with shell off and
  host-tools on, the P9 responder revision-checking each mutation against
  `packet.writableFiles` (an out-of-set `write`/`edit` is refused host-side, not
  executed, not recorded), the finished `TurnOutcome` relativized to the worktree
  before the pure verdict — and a minimal Dispatch tab. The caller's tree is
  never touched; nothing merges. Evidence floor met: the candidate ref is a real
  commit that resolves via `git rev-parse` after the worktree is removed; a
  changed file differs from its baseline; a refused tool / exceeded budget /
  failed validation / no changes each yields a typed receipt. No live end-to-end
  dispatch (the app target has no test target; the pure pieces the dispatch
  routes through are tier-tested; a real-model dispatch is out of scope for the
  tiered oracles). No new wire — the dispatch reuses P9's `--host-tools` spawn.
  Spec: [`docs/superpowers/specs/2026-08-22-p10-isolation-design.md`](docs/superpowers/specs/2026-08-22-p10-isolation-design.md).

- **P11 — Subagent pool (2026-08-23).** Context-isolated subagents share one
  locked engine. The engine patch (`--subagent-pool`, fork divergence #11) hosts
  N sessions in one process on one model load, multiplexes a `worker` id on every
  `--json-events` event (absent when N==1, so the single-session wire is
  byte-identical — the recapture proved it), advertises a `pool` cap, and routes
  inbound `{"t":"prompt","worker":N,"s":"..."}` prompts by worker; generation is
  serialized by a pool mutex around `worker_run_turn` (and around worker init,
  whose concurrent system-prompt prefill segfaulted the first live run — a Metal
  command-buffer race caught only by the live smoke gate). `SwiftStarKit` gains
  the wire-contract layer — `WorkerId`/`PoolWireParser`/`PoolPrompt`/
  `DispatchReceipt` (+ the reserved `DispatchExecutor`), the pure `PoolScheduler`
  (enqueue/start/finish/fail/inject), the `RollingDigest` reducer, `ContextAssembly`
  (deterministic adaptation in v1; the no-think model trip is deferred with the
  RLM tier), `EnvelopeMath` + deterministic perturbation constructors, and
  `DispatchPacketBuilder`. `SwiftStarAppKit` gains `PoolEngine` (spawn argv,
  `.kv` reader, `listFiles`). The app gains the `dispatch` host-tool, the
  dispatch→queue→worker-turn→receipt-injection loop, and the smoke-gate driver.
  The measurement gate's canonical arm is measured: **3.70x realized win vs the
  4.2x ceiling** (deep 131k 1550 s vs 8×16k pool 419 s; overhead ratio 0.88) —
  the sensitivity envelope (bloat/failure/count-sweep) is the follow-up pass.
  Live evidence:
  [`smoke gate`](docs/superpowers/research/2026-08-23-p11-smoke-gate.md),
  [`measurement gate`](docs/superpowers/research/2026-08-23-p11-measurement-gate.md).
  Spec: [`docs/superpowers/specs/2026-08-23-p11-subagent-pool-design.md`](docs/superpowers/specs/2026-08-23-p11-subagent-pool-design.md).

- **P12 — Reliable agency (2026-08-25).** Reframed 2026-08-24 from "More
  models" after an overnight investigation found the blocker was model
  *agency*, not model *variety*: a local model that writes correct code still
  fails to reliably act, and the failures traced to host-side contract and
  prompt shape more often than to the model. One model runs a
  role-differentiated pipeline — decompose, implement, repair — with the host
  owning phase boundaries, budgets, permissions, validation, and recovery.
  **Complete (2026-08-25) — all three roles evidenced live, each at small
  n; not a reliability claim.** What shipped: P12.1 hardened the packet
  validator/parser (schema version, CRLF, block-scalar, comment-stripping
  fixes) and wired `thinkBudget` and path presentation as a real lever;
  P12.2 made the Mellum Q5_0 quant loadable; P12.3 ran the prompt-shape
  ablation for Laguna (absolute paths a real lever, n=3, real grading);
  P12.4 added the repair role (fixture tier 3/3 ×2, plus two live
  non-fixture repairs reaching 13/13, n=2); P12.5 ran live the same day —
  a model-authored decompose packet set matched a hand-authored baseline's
  phase count, orphaned nothing, passed validation, and drove the run to
  the same final result, n=1; P12.6 met the second half of its own
  disjunctive criterion by naming and classifying the next failure mode
  (*completes-and-is-wrong*, not shallow exploration); P12.7 shipped its
  first 2 of 5 pieces the same night — trace-channel capture and
  Σprompt/Σcached/Σsuffix, live-confirmed; P12.8 wired phase-level recovery,
  plus a same-night fix (`953d05a`) so a failed repair now retries with
  fresh evidence instead of exiting immediately.
  What did **not** ship, and is not claimed: **P12.0's source-of-truth
  document was never written** and no superseded-doc banners were applied —
  `2026-08-24-overnight-consolidation.md` still stands as unmerged staging;
  **P12.7 shipped 2 of 5 pieces the same night** — trace-channel capture
  and Σprompt/Σcached/Σsuffix, live-confirmed (`20260825-232102-roadmap`:
  38014/33828/4186); no `DumbImplementer`, no stateful tokens (deliberately
  deferred), no warm-started timing, no `docs/cool_things/` write-up;
  P12.3's Mellum arm never ran; P12.4's live
  end-to-end tier (three phases → 13/13 from packets, at any real n) was
  started and stopped, so beyond those two n=2 instances the evidence is
  fixture-tier only; P12.8's own live phase-boundary confirmation
  specifically (a `validationFailed` receipt mid-build, retried) has not
  recurred since the fix landed — four live attempts since have hit either
  a clean pass or a `noChanges`/eos phase followed by an end-of-run
  acceptance failure (P12.4's repair, not P12.8's), never the mid-build
  validation failure P12.8 targets.
  **Reopen condition P12.5: met 2026-08-25.** Same pattern as P13's verdict
  naming its own reopen condition (which became P15), except this one
  closed the same day rather than opening a new sub-phase. An earlier
  version of this entry claimed P12.0 and P12.7 shipped; both claims were
  false and were corrected 2026-08-25 after an audit.
  Verdict: [`2026-08-25-p12-verdict-record.md`](docs/superpowers/research/2026-08-25-p12-verdict-record.md).
  P12.0's deliverable, landed late and at reduced scope:
  [`2026-08-25-local-model-agency.md`](docs/superpowers/research/2026-08-25-local-model-agency.md).
  Plan: [`2026-08-24-p12-reliable-agency.md`](docs/superpowers/plans/2026-08-24-p12-reliable-agency.md).

- **P13 — More models (2026-08-25).** Mellum 2.1 wired as a first-class
  `Variant` (memory-gated, contract-enforced admission before any engine
  spawn) and benchmarked live against P12's harness: path presentation × nudge
  × seed, at Mellum's published sampler (temp 0.6, top-k 20, top-p 0.95,
  min-p 0.0 — not a hostile setting). **Verdict: the competence gate fails —
  Mellum reliably fails the tool-call initiation gate under the tested
  harness** (0 tool calls across every cell of the 2×2, seed-swept). This
  blocks shipping Mellum as a preset; it is not a claim that Mellum's agent
  competence fails in the absolute, and the variant plumbing itself is
  complete and correct. The verdict named its own reopen condition — the
  out-of-phase host-controlled action mode — which became P15. Design:
  [`2026-08-25-p13-mellum-variant-design.md`](docs/superpowers/specs/2026-08-25-p13-mellum-variant-design.md).
  Benchmark record:
  [`2026-08-25-p13-mellum-benchmark-record.md`](docs/superpowers/research/2026-08-25-p13-mellum-benchmark-record.md).

- **P15 — Host-controlled action mode (2026-08-25).** Asked whether Mellum is
  **harness-addressable** (a host-side fix reaches it) or content-broken, by
  removing tool initiation from the loop: the model emits `#path` headings plus
  file bodies as text, `LabeledBlockParser` harvests them, the host writes the
  files and injects the paths into `TurnOutcome.mutations`, then validates and
  grades as usual. **Verdict: harness-addressable.** Every failure mode the
  phase found was host-side and each yielded to a host-side fix — a two-turn
  emission protocol for turns that reason and then stop; a lenient harvest for
  bodies emitted without fences; first-occurrence-wins plus a repeated-heading
  abort for degenerate resampling; and captured validation output for failures
  that previously recorded only an exit status. No engine work, no sampler
  change, no different model.

  Measured: repair **4/4 at 13/13**; build **3/9 at 13/13**, all three phases,
  **0 tool calls** — 85–128s for the run that happens to pass, but the failed
  attempts along the way cost wall-clock too: summed across all 9 sequential
  runs, **≈4.7 minutes per completed app**. All nine build runs harvested (0
  `contractNotFollowed`, previously 3 of 4). The phase's own bar asks for a
  host-verified candidate with content-bucketed failures and explicitly defers
  any per-model pass-rate guarantee, so 3-of-9 is a recorded measurement rather
  than a missed bar — and it is emphatically **not** a claim of reliability.

  Two numbers were retracted inside the phase after re-reading primary evidence:
  the build arm's "1/4" was a parser artifact, and an early "3/5" did not
  survive a larger sample. All results carry the in-band `resultClass` label
  **"drafting quality + host orchestration, not agency"** — 0 tool calls means
  the model never acted and the host wrote every file. Design:
  [`2026-08-25-host-controlled-action-mode-design.md`](docs/superpowers/specs/2026-08-25-host-controlled-action-mode-design.md).
  Plan:
  [`2026-08-25-host-controlled-action-mode.md`](docs/superpowers/plans/2026-08-25-host-controlled-action-mode.md).
  Verdict record:
  [`2026-08-25-p15-verdict-record.md`](docs/superpowers/research/2026-08-25-p15-verdict-record.md).
  Review:
  [`2026-08-25-p15-fable-review.md`](docs/superpowers/research/2026-08-25-p15-fable-review.md).

## Workflow

This repository runs on spec-driven development — see [`docs/sdd.md`](docs/sdd.md).
Each phase gets a committed design spec, then an implementation plan, then code.
The default test suite needs no model, no network, and no subprocess; process
behavior lives in a marked integration tier; and anything needing real weights
lives in a live tier that never runs in CI.
