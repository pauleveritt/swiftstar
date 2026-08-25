# Roadmap

> **Planning surface, not the front door.** Where the current phase, the concept
> budget, deferred candidates, and the backlog live. Not where a new reader
> should start — see [`README.md`](README.md) for what this is, and
> [`BRIEF.md`](BRIEF.md) for the settled design.

*Phases group feature cycles. One direction at a time. Tangents go to the
Backlog, not into the current phase.*

## Now

**Phase P12 — Reliable agency.** Next up; not started. **Reframed 2026-08-24**
from "More models" after an overnight investigation established that the
blocker is not model *variety* but model *agency*: a local model that can write
correct code still fails to reliably act, and the failures traced to host-side
contract and prompt shape more often than to the model. P12 is therefore one
model in a role-differentiated pipeline — decompose, implement, repair — where
the host owns phase boundaries, budgets, permissions, validation, and recovery,
and the model supplies judgment and code. Variants (Laguna XS 2.1, Mellum 2.1)
move to P13, where the harness that would evaluate them will exist.

The findings that forced the reframe are consolidated in
[`2026-08-24-overnight-consolidation.md`](docs/superpowers/research/2026-08-24-overnight-consolidation.md)
(Sections A–D). **P12 opens with a consolidation gate (P12.0)** that retires
that document into one source of truth — three parallel sessions produced
overlapping and partly contradictory records, and planning against them as-is
means re-deriving the same conclusions a fourth time.

P11 — Subagent pool — is complete: context-isolated
subagents share one locked engine (`--subagent-pool`, one model load, N sessions,
a `worker` id on every event), driven through a queue over the serialized GPU;
the packet-maker assembles a prepared context from a deterministic rolling
digest; a `dispatch` host-tool enqueues workers and receipts fold back into the
orchestrator. The measurement gate's canonical arm is measured: **3.70x realized
win vs the 4.2x ceiling** (overhead ratio 0.88) — the sensitivity envelope is the
remaining follow-up pass.

*P0–P11 are complete; their summaries live in [Prior work](#prior-work), not
here, so this section stays a true "what's happening now."*

## Concept budget

*Every term below is a cost against the reader's ability to hold the design in
mind. Checked at the end of each phase; a term earns its place by naming
something the design actually needs, not by being convenient shorthand.*

Seed terms, to be defined in this repository's own words when the phase that
needs each one lands: **patch set**, **shipped integration**, **variant**. (The
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
| P12 | Reliable agency | One model, three roles, host-owned structure: a typed packet per phase, bounded tools, real validation, and recovery — measured by writes and a passing acceptance suite, not tool calls | planned |
| P13 | More models | Laguna XS 2.1 and/or Mellum 2.1 as first-class variants — **neither line has a shipping artifact yet**; deferred behind P12 so there is a harness that can actually evaluate a variant | planned |
| P14 | A docs site | Sphinx content and Pages publishing, once there is a reader who isn't the author | planned |

Full done-when criteria live in each phase's own plan under
`docs/superpowers/plans/`, not restated here, to avoid drift between two copies.
Each plan is written as its phase begins. P12's plan is written:
[`2026-08-24-p12-reliable-agency.md`](docs/superpowers/plans/2026-08-24-p12-reliable-agency.md).

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
  rule already in `BRIEF.md`: CPU clusters deterministically, ANE only phrases.
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
- **Specialized tool subagents** — reasoning-light, one-command agents (ruff, pyrefly, pytest, sphinx, roadmap admin) that each own a single tool's lifecycle: run it in a non-human JSON mode where one exists, digest the output into something the caller can act on without bloat, and apply the fix when the run says what it is (e.g., a broken test). Budgeted to fit an 8k context on AFM3; because Swift runs the evocation, repeated invocations make the limit a budget rather than a wall. The open question is dispatch — how the orchestrating model+agent decides which specialized agent to call. The economics are measured, not assumed: locally, prefill is the scarce resource, so deterministic work first is a *performance* rule — `ruff --fix` beats the model typing the same 40-line edit by ~500x, and clustering 40 pytest failures to 2 representatives turns a 178s prefill at depth into 9s (rates from `docs/harvest/telemetry-findings.md`; worked table in the ds4-control survey cited by `2026-08-22-p11-engine-constraints-and-corrections.md`). *Reopens when P11 lands and the pool design can hold a one-command worker; this is a candidate shape for P11's workers, not a phase of its own.* Source: P11 "Subagent pool".
- **The dispatch decision** — what the handoff packet maker must know to route a task, on three axes. **(1) Parallelism:** dependency edges declared by the plan author are authoritative; the maker may additionally *prove* independence from disjoint writable-file sets plus disjoint validation commands, and must refuse when it cannot — file-disjointness is necessary, not sufficient (an API change and its consumer share no file). **(2) Thinking requirement:** a task is delegable to a reasoning-light worker only when acceptance is a machine-checkable predicate, the tool surface is bounded (`read`/`write`/`edit`, no `bash`), and the writable-file set is exact — and thinking is a stage, not a property: "fix the broken test" needs diagnosis (thinking) before the apply is mechanical. **(3) Executor:** whether the packet goes to a full-context worker or to a specialized Swift subagent running one command in its JSON mode (ruff, pyrefly, pytest, sphinx, roadmap admin), with AFM3's 8k as the budget for the latter and repeat evocations for anything longer. The lesson travels with it: the maker enforces declared intent and computes conservative proofs; it never re-derives semantics with less information than the plan author — the same lesson as the removed contract-blind pre-edit guard. *This is P10's routing design; axis 3 is what the "Specialized tool subagents" entry feeds. Reopens when P10 is planned.* Source: P10 "Isolation", the "Specialized tool subagents" backlog entry.
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
  current measurement says idle draw is under 1W.*
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
  first time) is measured.* Source:
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

## Workflow

This repository runs on spec-driven development — see [`docs/sdd.md`](docs/sdd.md).
Each phase gets a committed design spec, then an implementation plan, then code.
The default test suite needs no model, no network, and no subprocess; process
behavior lives in a marked integration tier; and anything needing real weights
lives in a live tier that never runs in CI.
