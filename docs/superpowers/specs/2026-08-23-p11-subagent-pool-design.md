# SwiftStar P11 design: Subagent pool

**Date:** 2026-08-23
**Status:** accepted (brainstormed; each decision approved; the dispatch-driver
recommendation reviewed by GLM 5.3 — see
[`docs/superpowers/research/2026-08-23-p11-glm-5.3-review.md`](../research/2026-08-23-p11-glm-5.3-review.md)).
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
  snapshot/rewind of idle tiers.
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

- **D1 — One engine, N workers, serialized.** `--subagent-pool` (divergence #11)
  hosts N sessions in one process on one model load, multiplexing a `worker` id
  onto the wire so the app knows which session an event belongs to. Exactly one
  session generates at a time (the serialized family). The shared
  `sysprompt.kv` prefix serves every worker read-only.

- **D2 — Wire-contract-first (three parts, in order).** (1) Fix the `worker`-id
  wire contract, the fake engine, and the Swift pool against the fake; (2) land
  the real `--subagent-pool` C patch behind that contract; (3) the measurement
  gate. The fake for part (1) is hand-authored **against the typed contract**
  (there is no multi-worker capture to generate from yet) and is regenerated
  from a golden capture once part (2) exists, per the standing recapture rule.
  The contract is the authority; the fake is a temporary stand-in, never a
  guess about the wire.

- **D3 — Dispatch is a host-tool, not a new wire kind.** The orchestrator model
  calls `dispatch(packet)`; it rides P9's `tool_request`/`tool_result`. The
  host answers by enqueuing a worker. No new event kind, no second fork round
  for emission.

- **D4 — Turn-boundary receipt delivery.** The `dispatch` call is a normal tool
  call inside the orchestrator's turn (the host answers `ok:true` with
  "dispatched as worker N"). The receipt (candidate ref or refusal) is **never
  delivered mid-turn**: the app runs the worker's turn as a separate session, and
  on completion **injects the receipt** into the orchestrator's *next* turn as a
  prompt. No mid-turn session suspend/save/load in v1; turns stay atomic and the
  serialization is trivially honored. The orchestrator's in-flight worker state
  is the app's queue, not an engine suspend.

- **D5 — The packet-maker is context assembly.** `deterministic-load → rolling
  digest → objective-dependent adaptation → packet`. The packet gains a
  *prepared context* assembled from objective + digest + staged reads, not P10's
  bare `taskText`.

- **D6 — Rolling digest (objective-independent, deterministic, out-of-band).**
  The "always-want" reduced form of the conversation — strip tool noise, keep
  the host-authoritative ledger (files touched, refs, receipts, exit statuses) —
  maintained **incrementally** by the host as events arrive, with no model and
  no inference. Backed by the `.kv` rendered text (readable inference-free). The
  extraction prefill is over this small digest, never the raw conversation. This
  is Layer 1 of distillation, and it is the only part that can be pre-chewed
  before the objective is known.

- **D7 — Objective-dependent adaptation (a no-think model trip).** The one step
  that cannot be pre-chewed: filter the digest to *this* objective and adapt it
  to the implementer's size/capability (Laguna coarser and more general; Mellum
  finer, split into smaller chunks). Runs reasoning-light (think off): cheaper
  on the decode side and keeps think tokens out of the folded-back context, but
  it does not cut prefill — that is D6's job. Deterministic load + ledger are
  its inputs; only the selection/adaptation is judgment.

- **D8 — Worker model.** Short-lived, shares the parent's root (bootstrap
  prefix). Budget-or-receipt: a worker's ctx_size equals its budget, and
  exceeding it is a receipt, never a compaction. Every mutation is
  revision-checked against `writableFiles` (P10 unchanged); read aids stay free.

- **D9 — Compaction rule.** Workers never compact. The orchestrator alone
  compacts, and its pool ledger (spawned worker → ref/receipt) is reconstructed
  host-side from the rolling digest (D6), never trusted to the model's summary.
  Compaction on the orchestrator resets warm-prefix routing (exact-prefix-only
  KV reuse): the summary, not the previously-read files, becomes the new prefix.

- **D10 — A-plumbing is non-slippable; A-routing is deferred, contract-reserved.**
  "Model-driven dispatch" splits into plumbing (the `dispatch` tool schema, the
  receipt schema, worker-id correlation — all in P11) and routing (parallelism
  proofs, thinking-requirement test, executor choice — deferred). The wire
  contract **reserves the routing types now** so nothing churns when routing
  lands; only the intelligence may slip.

- **D11 — The measurement gate is an envelope, not a point.** Three reports:
  (a) **overhead ratio** — realized win / analytic 4.2x ceiling on canonical
  packets; (b) **sensitivity envelope** — deterministic perturbations (taskText
  bloat ×1.5/×2, failure injection at fixed rates under a fixed retry policy,
  packet-count sweeps), yielding win-as-a-function-of-packet-quality and the
  threshold where the win stops justifying the fork; (c) **instrumentation** —
  tokens *actually evaluated* vs nominal (where snapshot/restore re-eval bugs
  hide), peak resident memory, and snapshot save/restore counts — **as the answer
  to "does the pool need idle-session eviction at all"** (zero in v1 is itself a
  finding). Plus
  **use-it-or-lose-it governance**: if A-routing has not landed within one phase
  after P11, divergence #11 is flag-gated off or reverted.

## Components

**SwiftStarKit** (pure — no Process, no IO): the `worker`-id / pool types; the
queue/scheduler state machine (a pure transition function: enqueue, run,
complete, fail, receipt-inject); the rolling-digest reducer (wire events →
digest); the packet-maker's pure mapping (load + digest + adaptation → packet);
receipt correlation; the envelope computation. All typed; a test asserting on
source text is a boundary violation.

**SwiftStarAppKit** (IO/Process, no SwiftUI): the `--subagent-pool` spawn; the
worker-id multiplex drain; worker records; the deterministic loaders
(`read`/`list`/`git ls-files`, the `.kv` reader); snapshot/rewind wiring for the
gate.

**SwiftStar** (the app): the orchestrator wiring (dispatch tool → queue → worker
turn → receipt injection on the next turn), the Dispatch/Agent surface.

**Engine (`ds4_agent.c`, divergence #11):** `--subagent-pool` — N sessions, one
engine, `worker` id on every wire event, one-session-at-a-time interleave; the
session primitives already exist.

## Data flow (one dispatch)

1. Orchestrator turn: model emits `dispatch(packet)` → `tool_request` on the
   wire; host answers `ok:true` ("dispatched as worker N"); the turn ends at EOS.
2. App enqueues worker N. The scheduler runs it (the only generating session):
   the worker's turn produces its own `worker`-id-scoped events; the P9
   responder revision-checks mutations against `packet.writableFiles`; the pure
   `WorktreeDispatch.verdict` returns a candidate ref or a receipt (P10
   unchanged).
3. App records the outcome in the rolling digest (D6) and the pool ledger (D9).
4. App injects the receipt into the orchestrator's next turn as a prompt; the
   orchestrator's context contains only the bounded receipt, not the worker
   transcript.

## Testing

- **Fast tier** (`just test`): the pure types, scheduler state machine, digest
  reducer, packet-maker mapping, receipt correlation, and envelope math. Typed
  assertions only; refusal tests each have a sibling success test (binding rule 4).
- **Integration tier** (`just integration`): the fake engine's `worker`-id wire
  against the Swift pool (enqueue → run → receipt-inject), the `writableFiles`
  revision check per worker, and the receipt correlation (worker N's outcome
  lands on orchestrator turn N+1). The fake is regenerated from a golden capture
  once part (2) exists.
- **Live tier** (`just capture`, never CI): the measurement gate (D11) against
  the real engine and weights — the envelope reports above.

## Concept budget

Two new terms: **rolling digest** (D6) — the objective-independent reduced form,
maintained incrementally and inference-free; and **context assembly** (D5) — the
packet-maker's load → digest → adaptation → packet. Both name something the
design actually needs, not shorthand.

## Out of scope

The model-driven RLM sub-query tier (ephemeral template, rewound between
queries — backlog, reopens when the pool exists); full A-routing (parallelism
proofs, thinking-requirement test, executor choice — D10); specialized tool
subagents; multi-project residency; the `recall` tool and session browser;
merging any candidate ref (the parent reviews; merge is a human act, P10
unchanged).
