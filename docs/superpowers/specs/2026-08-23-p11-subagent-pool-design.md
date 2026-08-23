# SwiftStar P11 design: Subagent pool

**Date:** 2026-08-23
**Status:** accepted (brainstormed; each decision approved; the dispatch-driver
recommendation reviewed by GLM 5.3 —
[`docs/superpowers/research/2026-08-23-p11-glm-5.3-review.md`](../research/2026-08-23-p11-glm-5.3-review.md);
the finished spec + plan re-reviewed by GLM 5.3 —
[`docs/superpowers/research/2026-08-23-p11-glm-5.3-spec-plan-review.md`](../research/2026-08-23-p11-glm-5.3-spec-plan-review.md)).
**Phase:** P11 — Subagent pool.

This spec is the authority on *how* P11 is done. `BRIEF.md`/`ROADMAP.md` stay
settled.

## Problem

P10 dispatches **one** attempt: a `HandoffPacket` in, a candidate ref or receipt
out, run in a disposable worktree by a fresh single-session engine. P11 makes
that a **pool**: context-isolated subagents sharing **one locked engine** (one
model load, N sessions in one process), driven through a queue over the
serialized GPU, ending at the phase's own measurement gate. The win being
bought is the context curve, not concurrency — and the gate must prove it.

## Gardenable facts (verified against the source)

- **The pool is serialized, by family.** Laguna is excluded from the engine's
  cross-session batch path unconditionally (`ds4.c:64276`); the fallback is a
  sequential eval loop. The pool is a queue over one serialized engine, not a
  scheduler over concurrent sessions.
- **The win is the context curve.** Integrating the measured prefill curve, one
  131,072-token prefill costs ~2,121 s; eight 16,384-token prefills run one after
  another cost ~500 s — ~4.2x, an **upper bound** (each shallow session repeats
  the shared preamble; results fold back into a parent whose context grows and
  re-prefills). The measurement gate must not expect a parallel-throughput win.
- **Sessions are not cheap.** ~6.1 GB of per-session GPU scratch for any
  ctx ≥ 16,384 (`min(ctx, 16384) × 375,156` bytes; a 4k worker is ~1.5 GB), plus
  KV of `49,152 × ctx + 75,497,472` bytes. Levers: small-ctx workers and
  snapshot/rewind of idle tiers. **This bounds N**: N sessions at ctx 16k cost
  ~7 GB each (~56 GB for N=8), so the app must refuse a pool whose
  N × per-session cost is infeasible, and workers must run at small ctx.
- **The engine already has every session primitive.** `ds4_session_new`,
  `ds4_session_rewind`, `ds4_session_save_payload`/`load_snapshot`,
  `ds4_session_common_prefix`, `ds4_session_eval` all exist. The gap is that
  `ds4_agent.c` is a **single-worker** program; the BRIEF names the future
  `--subagent-pool` patch (fork divergence #11).
- **The conversation is readable without inference.** The session `.kv` file
  stores the full rendered conversation as plain UTF-8 behind a fixed 48-byte
  header; the pre-compaction prefix survives on disk until evicted. The host can
  read/search it directly — no model, no engine.
- **KV reuse is exact-prefix-only.** `ds4_session_common_prefix` is free
  engine-side; the system prompt + bootstrap (`sysprompt.kv`) is the one shared
  prefix every worker reads read-only.
- **Compaction is a degenerate RLM sub-query.** A bounded summarizer whose result
  folds back into the parent; a subagent is the structured form of the same
  thing (bounded work in a separate small session, only the result folds back).
- **P10 gives the contract.** `HandoffPacket`, `WorktreeDispatch.verdict`
  (revision → budget → validation → noChanges → candidate), `DispatchOutcome`
  (candidate ref / receipt), and the `writableFiles` revision check. P11
  generalizes this from one attempt to a pool of workers; the per-worker
  contract is unchanged.
- **P9 gives the dispatch channel.** `--host-tools` already makes the wire
  bidirectional (`tool_request` → host → `tool_result`), with the engine
  blocking on the result. A `dispatch` is just another host-executed tool.

## Decisions

- **D1 — One engine, N workers, serialized, bounded.** `--subagent-pool N`
  (divergence #11) hosts N sessions in one process on one model load: worker 0
  (the orchestrator) plus N-1 worker sessions, created **eagerly at startup**.
  Every outbound event carries a `worker` id (**absent when N==1**, so the
  single-session wire is byte-identical to pre-P11). The **inbound** direction
  reuses the same bidirectional wire with a `worker` field on the prompt line —
  `{"t":"prompt","worker":<id>,"s":"..."}` addresses worker `<id>` (a bare line
  = worker 0); `tool_result` carries **no** worker tag because at most one
  `tool_request` is outstanding (exactly one session generates at a time — the
  engine enforces and asserts this invariant). Exactly one session generates at
  a time (the serialized family). The shared `sysprompt.kv` prefix serves every
  worker read-only. **N is bounded by memory**: the app refuses a pool whose
  N × per-session cost exceeds the feasibility gate (the P3 check extended to N
  sessions).

- **D2 — Wire-contract-first (three parts, in order).** (1) Fix the `worker`-id
  wire contract (outbound **and** inbound), the fake engine, and the Swift pool
  against the fake; (2) land the real `--subagent-pool` C patch behind that
  contract; (3) the measurement gate. The fake for part (1) is generated from a
  hand-authored **capture** (the `pool.ndjson` fixture) that encodes the typed
  contract — there is no multi-worker capture to generate from yet — and is
  regenerated from a golden capture once part (2) exists, per the standing
  recapture rule. The contract is the authority; the fake is a temporary
  stand-in, never a guess about the wire.

- **D3 — Dispatch is a host-tool, not a new wire kind.** The orchestrator model
  calls `dispatch(packet)`; it rides P9's `tool_request`/`tool_result`. The
  host answers by enqueuing a worker. No new event kind, no second fork round
  for emission.

- **D4 — Turn-boundary receipt delivery.** The `dispatch` call is a normal tool
  call inside the orchestrator's turn (the host answers `ok:true` with
  "dispatched as worker N"). Receipts are **never delivered mid-turn**: after
  the orchestrator's turn ends at EOS, the app runs each queued worker's turn as
  a separate session, and on completion injects the receipts into the
  orchestrator as a **single combined prompt** (all in-flight workers for that
  dispatch turn, in worker-id order), initiating the orchestrator's next turn.
  No mid-turn session suspend/save/load in v1; turns stay atomic and the
  serialization is trivially honored. The orchestrator's in-flight worker state
  is the app's queue, not an engine suspend.

- **D5 — The packet-maker is context assembly.** `deterministic-load → rolling
  digest → adaptation → packet`. The packet gains a *prepared context* assembled
  from objective + digest + staged reads, not P10's bare `taskText`. **Staged
  reads carry names only** (bounded): the worker reads the file contents on
  demand through its free read aids; contents are not inlined into the packet.

- **D6 — Rolling digest (objective-independent, deterministic, out-of-band).**
  The "always-want" reduced form of the conversation — strip tool noise, keep
  the host-authoritative ledger (files touched, refs, receipts, exit statuses) —
  maintained **incrementally** by the host as events arrive, with no model and
  no inference. The extraction prefill is over this small digest, never the raw
  conversation. **Backed by the `.kv` rendered text** means: the digest is
  *reconstructed from the `.kv` file on app restart* (crash recovery of the pool
  ledger), so the ledger survives a restart without re-running any model.

- **D7 — Adaptation is deterministic in v1; the model trip is deferred.** The
  step that filters the digest to *this* objective and sizes it to the
  implementer's capability (Laguna coarser and more general; Mellum finer, split
  into smaller chunks) is, in P11, a **pure deterministic template** over the
  digest + objective + implementer (`ContextAssembly.deterministicAdaptation`).
  The **no-think model trip** form of this step is deferred with the RLM
  sub-query tier (out of scope); `ContextAssembly.adaptationPrompt` exists as the
  deferred prompt, but no model trip runs in P11. Deterministic load + ledger
  are its inputs; the template does the sizing, no judgment required.

- **D8 — Worker model.** Short-lived, shares the parent's root (bootstrap
  prefix). Budget-or-receipt: a worker's ctx_size equals its budget, and
  exceeding it is a receipt, never a compaction. **Per-worker ctx_size is set at
  session creation** (the orchestrator's `-c` is the project ctx; each worker
  session is created at the packet's budget-mapped small ctx, ~4k–16k, so
  scratch stays ~1.5–6.1 GB not the deep-context figure). Every mutation is
  revision-checked against `writableFiles` (P10 unchanged); read aids stay free.

- **D9 — Compaction rule.** Workers never compact. The orchestrator alone
  compacts, and its pool ledger (spawned worker → ref/receipt) is reconstructed
  host-side from the rolling digest's `summary()` (D6), re-injected after a
  compaction, never trusted to the model's summary. Compaction on the
  orchestrator resets warm-prefix routing (exact-prefix-only KV reuse): the
  summary, not the previously-read files, becomes the new prefix.

- **D10 — A-plumbing is non-slippable; A-routing is deferred, contract-reserved.**
  "Model-driven dispatch" splits into plumbing (the `dispatch` tool schema, the
  receipt schema, worker-id correlation — all in P11) and routing (parallelism
  proofs, thinking-requirement test, executor choice — deferred). The contract
  **reserves one named type now** so nothing churns when routing lands: an
  `executor` discriminator on `DispatchReceipt` (`.fullContext` in v1; the
  specialized one-command worker is the future case). Only the intelligence may
  slip, not the wire.

- **D11 — The measurement gate is an envelope, not a point — and a hard exit
  criterion.** Three reports: (a) **overhead ratio** — realized win / analytic
  4.2x ceiling on canonical packets; (b) **sensitivity envelope** — deterministic
  perturbations (taskText bloat ×1.5/×2, failure injection at fixed rates under
  a fixed retry policy, packet-count sweeps), yielding win-as-a-function-of-
  packet-quality and the threshold where the win stops justifying the fork; (c)
  **instrumentation** — tokens *actually evaluated* vs nominal (where
  snapshot/restore re-eval bugs hide), peak resident memory, and snapshot
  save/restore counts — **as the answer to "does the pool need idle-session
  eviction at all"** (zero in v1 is itself a finding). The **perturbation
  constructors are pure Kit** (deterministic, tested); the retry policy is
  "one retry on a budget/validation receipt, then surface"; the canonical packet
  set is a committed corpus under `fixtures/gate/`. **The phase does not close
  until the gate is measured** — there is no "record as pending" path. Plus
  **use-it-or-lose-it governance**: if A-routing has not landed within one phase
  after P11, divergence #11 is flag-gated off or reverted.

## Components

**SwiftStarKit** (pure — no Process, no IO): the `worker`-id / pool types; the
inbound `PoolPrompt` encoder; the queue/scheduler state machine (a pure
transition function: enqueue, run, complete, fail, receipt-inject); the
rolling-digest reducer (wire events → digest, plus `.kv` reconstruction); the
packet-maker's pure mapping (load + digest + deterministic adaptation → packet);
receipt correlation; the envelope computation and the perturbation constructors.
All typed; a test asserting on source text is a boundary violation.

**SwiftStarAppKit** (IO/Process, no SwiftUI): the `--subagent-pool` spawn; the
worker-id multiplex drain; worker records; the deterministic loaders
(`read`/`list`/`git ls-files`, the `.kv` reader); the snapshot/restore **counters**
for the gate (measurement only — v1 performs no eviction).

**SwiftStar** (the app): the orchestrator wiring (dispatch tool → queue → worker
turn → receipt injection on the next turn), the Dispatch/Agent surface.

**Engine (`ds4_agent.c`, divergence #11):** `--subagent-pool` — N sessions, one
engine, `worker` id on every outbound event (when N>1) and on inbound prompts,
one-session-at-a-time interleave (enforced + asserted), per-worker ctx_size at
session creation; the session primitives already exist.

## Data flow (one dispatch)

1. Orchestrator turn: model emits `dispatch(packet)` → `tool_request` on the
   wire; host answers `ok:true` ("dispatched as worker N"); the turn ends at EOS.
2. App enqueues worker N. The scheduler runs it (the only generating session):
   the worker's turn produces its own `worker`-id-scoped events; the P9
   responder revision-checks mutations against `packet.writableFiles`, executing
   them into the worker's **disposable worktree** (P10's `WorktreeDispatcher`,
   whose turn-runner now drives worker N of the pooled engine instead of
   spawning a fresh process); the pure `WorktreeDispatch.verdict` returns a
   candidate ref or a receipt (P10 unchanged).
3. App records the outcome in the rolling digest (D6) and the pool ledger (D9).
4. App injects the receipts into the orchestrator's next turn as one combined
   prompt; the orchestrator's context contains only the bounded receipts, not
   the worker transcripts.

## Testing

- **Fast tier** (`just test`): the pure types, the inbound `PoolPrompt` encoder,
  scheduler state machine, digest reducer, packet-maker mapping (including
  `deterministicAdaptation`), receipt correlation, the perturbation constructors,
  and envelope math. Typed assertions only; refusal tests each have a sibling
  success test (binding rule 4).
- **Integration tier** (`just integration`): the fake engine's `worker`-id wire
  against the Swift pool — enqueue → run → receipt-inject (the full dispatch
  loop, explicitly tested), the inbound worker-addressed prompt, the
  `writableFiles` revision check per worker, and the receipt correlation (worker
  N's outcome lands on orchestrator turn N+1). The fake is regenerated from a
  golden capture once part (2) exists.
- **Live tier** (`just capture`, never CI): the measurement gate (D11) against
  the real engine and weights — the envelope reports above.

## Concept budget

Two new terms: **rolling digest** (D6) — the objective-independent reduced form,
maintained incrementally and inference-free; and **context assembly** (D5) — the
packet-maker's load → digest → adaptation → packet. Both name something the
design actually needs, not shorthand.

## Out of scope

The model-driven RLM sub-query tier (ephemeral template, rewound between
queries — backlog, reopens when the pool exists) **and the no-think adaptation
trip (D7's deferred model form)**; full A-routing (parallelism proofs,
thinking-requirement test, executor choice — D10); specialized tool subagents;
multi-project residency; the `recall` tool and session browser; merging any
candidate ref (the parent reviews; merge is a human act, P10 unchanged).
