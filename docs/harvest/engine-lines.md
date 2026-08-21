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
