# Engine constraints that correct P11's premise (and touch P3, P5, P6)

**Status:** research note; corrections to recorded claims, with the commands
that recompute them. Not a plan.
**Date:** 2026-08-22
**Provenance:** every citation below was verified against **this repository's
own submodule checkout** (`external/ds4`, branch `swiftstar-integration`) on
2026-08-22 — line numbers are that checkout's. The fuller survey these
corrections come from is `docs/superpowers/research/
2026-08-22-engine-architecture-and-work-tiers.md` in the `ds4-control`
worktree (`feat/agent-mode-laguna` @ `f2e65a5`); that document's claims were
themselves filtered through an adversarial review that rejected roughly a
third of them. Only what survived, and what was re-verified here, appears
below.

---

## Correction 1 — Laguna has no cross-session batch path at all

The roadmap's dependency note says sessions with `graph.ssd_streaming` are
excluded from the engine's batch path "regardless of family," framing the
constraint as a P11↔P12 interaction. That is true but critically incomplete:

`ds4_sessions_eval_batch_metal_supported()` (`external/ds4/ds4.c:64270`)
returns false when `DS4_MODEL_FAMILY == DS4_MODEL_FAMILY_LAGUNA`
(`ds4.c:64276`) — **unconditionally**, before ssd_streaming is ever
consulted. The fallback in `ds4_sessions_eval_batch()` is a sequential
`ds4_session_eval` loop. The companion
`ds4_sessions_eval_batch_with_prefill()` does *not* family-exclude Laguna,
but its only callers are two test files (`tests/test_metal_session_batch.c`,
`tests/test_cuda_mixed_batch.c`) — nothing shipped calls it.

```bash
# recompute:
grep -n "DS4_MODEL_FAMILY_LAGUNA" external/ds4/ds4.c | grep -n 64276
grep -rn "ds4_sessions_eval_batch_with_prefill" external/ds4 --include=*.c | grep -v "ds4.c:"
```

**Consequence for P11:** the pool's workers run **one at a time** on the model
line the app ships first — S or XS, ssd_streaming or not. This is not a
P11↔P12 sequencing question; it is a property of the family. The pool design
should be a queue over one serialized engine, not a scheduler over concurrent
sessions.

**What it does *not* change:** the isolation hypothesis. Its mechanism is the
context tax, not parallelism, and the tax argument works sequentially.
Integrating the measured prefill curve, one 131,072-token context prefilled
once costs ~2,100s while 8 × 16,384-token contexts prefilled **sequentially**
cost ~475–500s — an up-to-~4x win with zero concurrency. Treat 4x as an upper
bound: it prices two context *shapes*, not one task done two ways (shared
preamble repeated per session, results reported back into a growing parent,
cross-chunk reasoning lost). The harvest doc's measurement gate — "does the
wall-clock win correlate with subagent context staying small" — is already
aimed at the right mechanism; the expectation to delete is any parallel-
throughput win.

## Correction 2 — the engine's memory plan omits ~6.1 GB of per-session scratch

`laguna_graph_alloc()` (`ds4.c:47834`) allocates the session's GPU activation
workspace as ~28 buffers each sized `rows × width`, where
`rows = prefill_cap = min(ctx, 16384)` (`ds4.c:47841`). Summing the
`DS4_LAGUNA_ALLOC` widths against the Laguna shape table (`ds4.c:669`:
n_embd 3072, n_head 72, n_head_kv 8, n_head_dim 128, n_ff_dense 12288,
n_expert 256/used 10, n_ff_exp 1024) gives **375,156 bytes per row**, so
**≈6.15 GB per session for any ctx ≥ 16,384**, held for the session's
lifetime.

The startup memory plan's estimator
(`ds4_context_memory_estimate_with_prefill_mode`, `ds4.c:35631`) computes its
Laguna `scratch_bytes` from **single-row** buffer sizes: 784,752 bytes.
**This repository's own committed fixture carries the under-report**
verbatim — `fixtures/agent/golden.ndjson`'s `ready` events say
`"scratch_bytes":784752` — a factor-of-~7,800 under-statement of what the
allocator actually reserves at that ctx.

```bash
# recompute the per-row sum (shape table at ds4.c:669, alloc list at ds4.c:47846-):
# 9 embd-wide f32 rows + q/heads (72*128) + k/v/staged (8*128) + 3 ffn_max (12288)
# + routed_mid (10*1024) + router (256*2 + 10*2) + tokens
python3 -c "e=3072;print((9*e + 2*72*128 + 2*8*128 + 3*12288 + 10*1024 + 2*256 + 2*10)*4 + 2*8*128*2 + 4)"
# -> 375156;  375156 * 16384 = 6,146,555,904
grep -m1 '"t":"ready"' fixtures/agent/golden.ndjson
```

**Consequences:**

- **P3 (shipped).** `Feasibility.check` is the *right* design — pure
  arithmetic on the engine's own `planned_bytes`, no mirrored formula — and
  precisely because of that it inherits the engine's error: on Laguna a launch
  that clears the gate by less than ~6.1 GB will be admitted and then exceed
  the plan when the session allocates. Fix direction: the estimator's Laguna
  branch should multiply by `prefill_cap` rows, upstream — this belongs in
  `docs/upstream-proposals.md` alongside the startup-memory-plan patch it
  corrects. Until then, the correction term (`+ min(ctx,16384) × 375,156` for
  Laguna) is a documented, citeable constant, not a re-derived mirror.
- **P11.** N sessions cost N × (KV + 6.1 GB), not N × KV. Laguna KV is
  exactly `49,152 × ctx + 75,497,472` bytes (12 global layers × 8 KV heads ×
  256 dims × 2 B/token, plus 36 SWA layers × 512 window × 4,096 B fixed) —
  this formula reproduces both measured `ready` events byte-exactly
  (ctx 32,768 → 1,686,110,208; ctx 150,000 → 7,448,297,472). A pool premised
  on "sessions are cheap" is mispriced; the levers are small-ctx workers
  (scratch scales with `min(ctx, 16384)`, so a 4k worker's scratch is ~1.5 GB
  not 6.1) and `ds4_session_save_payload`/`load_snapshot` for idle-session
  eviction to disk.

## Correction 3 — preemption, power, and the pool scheduler

Facts a P11 scheduler design must absorb, all verified here:

- **Prefill preempts per chunk, and the chunk is not a knob.** Cooperative
  cancel is checked once per prefill chunk; `prefill_cap` is hardcoded
  `min(ctx, 16384)` (`ds4.c:47841`) and Laguna **rejects `--prefill-chunk`
  at engine open** (`ds4.c:59530`). At measured depth rates (~40 tok/s at
  ctx≈92k) one deep chunk can hold the GPU for minutes. Background decode
  preempts per token and is safe; a queued pool must never schedule a deep
  prefill "in the background" of an interactive turn.
- **No per-session power lever.** `ds4_session_set_power` errors for Laguna
  at any value < 100 and writes `engine->power_percent` — engine-wide —
  when it does apply. The Backlog's energy-aware pacing entry should note
  the lever must be *built* (a runtime control message), not exposed.
- **The agent's KV store is a shared path.** `agent_default_cache_dir()`
  is `$HOME/.ds4/kvcache` for every worker; `sysprompt.kv` lives there once.
  N workers writing one path is a race to design around — and an asset: one
  prefilled system prompt serves every worker read-only.

## What this schedules, and where

- **P5 (now):** capture the agent's `--trace` channel alongside stdout.
  Compaction's rebuild statistics (`old`, `new`, `tail_start`, `tail`) are
  deliberately suppressed on the `--json-events` wire but **already emitted
  via `agent_trace()`** — no new engine patch. If P5 fixes the capture
  format without a trace sidecar, P6 re-opens the format to get it.
- **P6:** the deterministic analyzer gets compaction stats from the trace
  capture; "would compaction help" (BRIEF, diagnostics job #1) becomes
  answerable from recorded fact.
- **P11 planning:** this note is input; the premise corrections above are
  the plan's starting constraints.
- **Backlog:** recall tool, session browser over `~/.ds4/kvcache`, hybrid
  compaction skeleton, engine-side memory-plan/tokenize CLI, multi-project
  residency — each entered with its reopen condition in `ROADMAP.md`.

## What this does not change

- **The isolation hypothesis** (context tax, sequential) — intact, with a
  cleaner mechanism than before.
- **The spawned-seam decision** — intact. Scratch cost is allocator
  behavior on either side of the seam; serialization is model-family
  behavior; neither is an embedding argument. One addition to the brief's
  additive-wire list: exact tokenization is reachable engine-free (the
  tokenizer loads vocab without weights), so pre-flight token budgeting
  needs a small CLI, not linkage.
- **The Mellum line** — untouched by all of the above; nothing here bears
  on it.
