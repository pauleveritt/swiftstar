# Harvest: the engine lines

**Source:** `~/projects/ds4` — a checkout of `antirez/ds4` carrying local
branches that have no durable home. This is the one body of work that **moves
over directly**, because it is the same C codebase reached through a submodule
rather than something being rewritten.

It still goes through phase **P1** so that it arrives consolidated, documented,
and rebasable rather than accumulated.

## The problem P1 solves

Three things are currently true at once, and together they mean SwiftStar has no
engine it owns:

1. `~/projects/ds4` tracks **`antirez/ds4` directly**. Local branches
   (`paul/laguna`, and the worktrees below) exist only on one disk.
2. DS4 Control's submodule points at **`notatestuser/ds4`** — someone else's
   fork — for the patches the app actually depends on: `--json-events`,
   turn-interrupt, a status marker, a stale-interrupt latch, and a startup
   memory plan.
3. Different worktrees pin different submodule SHAs, so "the engine" is not a
   single thing.

P1 forks `antirez/ds4` to **`pauleveritt/ds4`** and absorbs (1) and (2) into one
shipped integration branch. That merge is real work with real conflicts, which
is why P1 is its own phase and why its done-when does not require an app.

## The lines

**Laguna S 2.1** — `laguna-s2.1`, an upstream branch. Targets 64 GB-class
machines at full residency with mixed routed Q2_K/Q3_K experts. Carries native
Laguna S 2.1 support, DFlash speculative decoding on Metal, CUDA, and ROCm,
quantized draft models, and family-level sampling defaults. **Explicitly
unsupported for SSD streaming.**

Two operational facts worth carrying: DFlash only engages under **greedy**
decoding, and the Laguna default temperature is now **0.7**, so it silently does
not engage unless temperature is set to 0. Family sampling defaults are
temperature 0.7, top-k 20, top-p 0.95, min-p 0.05, applied across CLI, agent,
and server.

**Laguna XS 2.1** — `laguna-xs2.1`, a **continuation of** `laguna-s2.1`, not a
sibling. Thirty-odd commits of SSD-streamed routed-expert work targeting 16 GB:
exact Q3 streamed expert cache, address-equivalence proofs, hotlist tuning,
streamed-cache footprint measurement. Engineering was complete as of
2026-07-28; the open work is a real constrained-hardware acceptance run and a
reapply onto updated upstream.

**Mellum 2.1** — an independent line. Two branches exist,
`mellum-2.1` and `mellum-2.1-overnight`; **`mellum-2.1-overnight` is the
canonical one** — it carries the work and the worktree. Grouped MoE
kernels with dot4 vectorization, SWA-boundary prefill drift localized to
projection kernels, oracle envelopes tightened around the measured
implementation, chunk-schedule soak testing, and an RLM readiness probe finding
that exploration works but termination does not. One commit in that history is
worth the whole branch as a cultural artifact: *"Correct a false green: make
test does not pass in this worktree."*

**Corrected 2026-08-23 — superseded by real progress on the branch.** Resident
Q8 decode is green at ~144 tok/s and batched true prefill is now wired into
`ds4_session_sync`. The mixed Q4_K/Q8 artifact SwiftStar would ship **has been
built and measured**: 9.33 GiB (Q4_K expert gate/up on layers 0-21, Q8_0
elsewhere), and ds4 **loads and generates from it** — a dedicated
`kernel_mellum_q4_K_pair_swiglu_f32` exists (not just the borrowed GLM kernel),
~25% faster than the generic one, decode at ~0.94x of Q8_0. This is no longer
the line's largest unpriced work.

What P12 actually inherits instead, in order of what blocks it:

1. **The branch itself was never merged.** SwiftStar's `external/ds4` submodule
   pins `swiftstar-integration-5-ge1312b8` — verified to contain zero Mellum
   commits and no Mellum files. All of the above lives only on
   `mellum-2.1-overnight`, unmerged. P1's branch policy applies here at full
   weight: this is a real merge with likely real conflicts, not a formality.
2. **Prefill is still slow for the Q4_K/Q8 artifact.** The expert-major batch
   kernel stages Q8_0 rows and cannot run Q4_K, so Q4_K/Q8 sessions fall back to
   the tokenwise sync path — measured 0.21x versus Q8_0's batched prefill. This
   is the practical bottleneck a user would feel.
3. **`planned_bytes` has no Mellum branch and under-reports non-weight memory
   by ~0.7-1.0 GiB at 40k context**, the same class of bug found on Laguna
   (`ds4_context_memory_estimate_with_prefill_mode`, ds4.c:36293, falls through
   to a generic path built for a different, compressive-KV architecture — hard
   caps KV rows at 8192 regardless of `--ctx`, and misses the
   `mellum_prefill_workspace` and MoE `s_partial` allocations entirely). Matters
   for P12 specifically because P3's feasibility gate would inherit this on day
   one. Net effect at the current 9.33 GiB artifact: real total ≈ 10.3 GiB at
   40k context — still clears a 13 GiB checkpoint with margin, just not the
   number the engine itself would report.
4. No SwiftStar-side fixtures exist for Mellum yet (`fixtures/agent/`,
   `fixtures/server/` are Laguna/GLM-shaped) — P1/P5's golden-capture pattern
   has nothing to build against.

Two findings from that branch are worth carrying whether or not P12 ever ships a
Mellum `Variant`, because neither is about kernels. First, the branch's
**envelopes measure something one to two orders of magnitude finer than the
accuracy of the reference itself**: an independent FP32 forward from the pinned
weights, run 2026-08-21 (`2026-08-21-mellum2-independent-fp32-oracle.md`,
commit `d8f5190`), puts ds4 within 0.085% of llama.cpp on logits while
llama.cpp's own Q8 sits 2.4% from the FP32 model, and 9.3% at layer 27. So
numerical gates of this kind are regression tripwires, never fidelity
acceptance criteria — a lesson that transfers to any engine SwiftStar pins.
Second, the same run showed a **model config alone flipping the greedy token**:
the older flattened `qwen3_moe` rope export, run against identical weights,
diverges at 26 tokens. A `Variant` is not just a file path and a sampler; the
runtime contract is part of it.

The **RLM probe generalizes past Mellum and bears directly on P9 and P11**:
across five configurations none produced a correct answer, code generation was
solid in every no-think run, no-think never concluded, and thinking terminated
without exploring — twice emitting a confident final answer on fabricated
content. Bounded recursive uses are viable today; open-ended "explore this
corpus and synthesize" is not, and *a false stop signal is worse than no stop
signal* in a loop that propagates termination upward as though it were verified.
The companion orchestrator eval found thinking helping on neither task shape,
with the reasoning checkpoint hitting its cap at both 2,048 and 4,096 tokens.

## The constraint that binds P11 and P12

**Sessions with SSD streaming enabled are excluded from the engine's batch path
regardless of model family.** The subagent-pool plan states it as a Non-Goal.
So Laguna XS support and subagent isolation cannot both be assumed; whichever
ships second inherits the constraint, and the roadmap records this as a
dependency rather than letting a phase discover it.

## The branch policy P1 establishes

- **`main`** — pristine upstream mirror, never edited.
- **The patch set** — app-required engine changes only. Small, rebased, never
  merged.
- **One shipped integration branch** — the union base carrying every model line
  the app ships a `Variant` for, with the patch set applied. **The submodule
  pins a SHA here and nowhere else.**
- **Development branches** (`laguna-xs2.1`, `mellum-2.1`) are never pinned by
  the app. A line enters the shipped integration when SwiftStar ships a
  `Variant` for it — which ties integration size to shipped features rather than
  to experiments.
- **A fork ledger** gives every divergence a row saying why it exists and what
  would retire it, and **`docs/upstream-proposals.md`** is the outbound half, so
  that "upstream-bound" does not quietly become "carried forever."
