# Laptop AI

SwiftStar's premise is **AI that lives on your laptop and runs on your
battery.** A laptop is a resource-constrained device — GPU, CPU, RAM, and a
battery that is one budget with the thermals — and the standard server harness
assumes none of those constraints. Laptop AI is the argument that the
constraints are the design, not a limitation: run a model that *fits*, keep its
context *small*, and do expensive work *once* and reuse it. This document
assembles that argument from the measured facts in [`harvest/`](harvest/index.md)
and the phase list in [`ROADMAP.md`](../ROADMAP.md).

## The budget: GPU, CPU, RAM — and the battery

- **The measured cost is GPU prefill at deep context.** On Apple silicon the
  CPU and GPU share one die and one fan. The 2026-08-21 investigation found the
  CPU under 7% in both low- and high-context sessions; the GPU averaged 35.9%
  at ~3,400 tokens vs 98.0% at ~92,500. Prefill throughput degrades ~7x across
  that range (~300–360 → ~41–46 tok/s), and it is compute-bound — the prefix
  cache stays healthy, and compaction only helps by making the context smaller.
  ([`harvest/telemetry-findings.md`](harvest/telemetry-findings.md))
- **Energy and heat are one budget.** Energy drains the battery; sustained heat
  engages the fan, throttles the chip, and makes the chassis un-lappable — and
  each of those is itself a battery cost (fan draw, throttled wall-clock,
  baseline overhead). Idle draw is well under 1W, so the entire budget is active
  compute.
- **Two levers, and they are not the same.**
  - *Do less work* — reduce the tokens prefilled. Saves energy directly and
    shortens the sustained-load episodes.
  - *Do the same work out-of-band* — prefill during idle (thermal headroom),
    reuse the result later. Saves no compute energy; flattens the power curve,
    which is what the fan, the throttle, and the heat care about.
- **The resource ladder:** every step down adds a technique — full residency →
  aggressive mixed quantization → SSD streaming → a smaller model family. 128 GB
  runs DS4F fully resident; 64 GB runs Laguna S; 32 GB runs Laguna XS streamed;
  16 GB runs Mellum.

## The model ladder

One principle across all four: the *smallest model that stays resident* beats a
bigger one that thrashes against the memory wall.

**128 GB — DS4F (DeepSeek V4 Flash)**
- The flagship: the best open weights for the biggest laptop.
- 2-bit routed-expert quants, imatrix-tuned (`q2-imatrix`, `q2-q4-imatrix`),
  fully resident on Metal.
- Speculative decoding via MTP/DSpark — currently experimental and
  correctness-gated; the real quality story is the aggressive quantization,
  not the speculation.
- The one tier with headroom; the reference the other three are measured
  against.

**64 GB — Laguna S 2.1**
- Full residency via mixed routed Q2_K/Q3_K experts.
- Native Laguna S support; DFlash speculative decoding — Poolside's standalone
  draft model, greedy-only, token-exact at fixed verifier width.
- Family sampling defaults (temp 0.7, top-k 20, top-p 0.95, min-p 0.05) applied
  consistently across CLI, agent, and server. Default temp 0.7 means DFlash does
  not auto-engage unless temp is set to 0.
- Explicitly unsupported for SSD streaming.

**32 GB — Laguna XS 2.1**
- A continuation of Laguna S, not a sibling: SSD-streamed routed experts
  (uniform RoutedQ3_K, all 39 sparse layers cache-eligible).
- Exact Q3 streamed expert cache, hotlist tuning, streamed-cache footprint
  measurement.
- Runs the S-class model from disk where full residency would not fit.
- Committed target **32 GB**. The ~6.5 GiB footprint ("fits under 10 GB
  including context") makes 16 GB look feasible — confirming it on real
  hardware is a backlog item, not new engineering.

**16 GB — Mellum 2.1**
- A smaller grouped-MoE line: dot4-vectorized kernels, SWA-boundary prefill
  drift localized to projection kernels.
- Resident Q8 decode is green at ~144 tok/s; batched true prefill is correct
  but not yet wired into `ds4_session_sync`.
- The mixed Q4_K/Q8 shipping artifact has **never been built** — the dev quant
  (~12 GiB Q8) is not what ships; P12 inherits the unbuilt artifact, not a
  finished engine.

## How ds4 shrinks models and keeps them smart

The engine's whole design is "small enough to fit, still good enough to use."
([`external/ds4/README.md`](../external/ds4/README.md),
[`harvest/engine-lines.md`](harvest/engine-lines.md))

- **Asymmetric routed-expert quantization** — only the routed MoE experts are
  quantized (up/gate `IQ2_XXS`, down `Q2_K`); shared experts, projections, and
  routing stay untouched. The experts are the bulk of the weights, so the
  savings land where the size is, and quality is preserved where it matters.
- **imatrix-tuned quants** — `q2-imatrix`, `q2-q4-imatrix` (last 6 layers at
  Q4), `q4-imatrix`, `pro-q2-imatrix`; routed-MoE imatrix collected from a
  generated calibration corpus.
- **Verified low-bit quality** — 2-bit quants are scored against official
  DeepSeek continuations, with regression test vectors; the quants "behave well,
  work under coding agents, and call tools reliably."
- **Architectural tolerance, exploited deliberately** — DeepSeek V4 Flash/PRO
  and GLM 5.2 tolerate aggressive routed-expert quantization; the engine picks
  models on that basis.
- **Whole-model Metal graph inference** — the production path is one Metal
  graph, not per-op dispatch.
- **SSD streaming** — stream routed experts from disk, hide missing-expert
  loads behind inference of resident experts; run a model bigger than RAM at
  usable speed.
- **Compressed KV caches** — KV is `49,152 × ctx + ~72 MiB` per session; long
  contexts are practical.
- **Speculative decoding** — DFlash (Laguna's standalone draft model, greedy-only)
  and MTP/DSpark (Flash's, experimental) recover decode speed lost to
  quantization.

## How ds4-agent changes the agent game

The agent is built *inside* the engine, in the same process as the KV cache —
so it can use KV-economy primitives that no hosted harness (Claude Code, Pi, or
anything over an API) can reach.
([`external/ds4/AGENT.md`](../external/ds4/AGENT.md),
[`harvest/ds4-control.md`](harvest/ds4-control.md))

- **The bootstrap is prefilled once, ever.** `sysprompt.kv` checkpoint-restores
  the system/tool prompt from disk every session. Hosted harnesses re-process
  their bootstrap each session; this one does not.
- **Compaction rebuilds *from* the system prompt**, so skills survive compaction
  structurally — no re-injection hook.
- **Live KV reuse + disk KV checkpoints** make long local sessions (hours,
  150k ctx) practical: snapshot/restore in seconds vs minutes of re-prefill.
- **Bounded `read` + `more`** make progressive disclosure native — a skill read
  cannot blow the context.
- **A 50K reminder cycle** re-asserts mid-session for free.
- **The parse/execute cut** — model-coupled tool *parsing* stays in C;
  OS-coupled *execution* moves to the host (P9), enabling condensation-before-KV,
  per-tool consent, and tool parallelism.
- **Tool results are condensed before they enter KV** — the best mitigation of
  the 7x context tax; a multi-thousand-token log entering context is exactly the
  compounding cost.
- **An observable, interruptible wire** — NDJSON events with a version handshake
  and timestamps, capture-grade turn outcomes and typed stop reasons; the agent
  is a supervised child process, not a black box.

The new thinking, in one line: **a hosted agent pays a compounding tax because
everything it touches re-enters a growing context; a laptop agent must instead
live *with* the KV cache — reuse it, checkpoint it, keep it small.** ds4-agent
is the first agent whose primitives are built from KV economy.

## The Laptop AI playbook

The terse list of what this project brings to the table:

- Condense tool results before they enter KV (P9).
- Lead the metrics on *absolute* `ctx_used`, not a percentage (P4).
- Isolate context with subagents; the win is the sequential context curve, not
  concurrency (P11).
- Don't re-read unchanged files (hash+mtime) — answer "unchanged" instead of
  re-prefilling (~130s per avoided deep re-read).
- Route to the session whose prefix already holds the files
  (`ds4_session_common_prefix`, warm-prefix routing).
- Recurse over slices with a small root context (RLM).
- Snapshot idle sessions to disk; restore instead of re-prefill (multi-project
  residency).
- Prefill the shared bootstrap once, ever (`sysprompt.kv`).
- Persist pre-compaction context and search it (`recall`) instead of re-reading.
- Compute diagnostics deterministically; let the model only phrase (P6).
- Offload phrasing/condensation to the ANE — the one compute unit that does not
  contend with the GPU.
- Do anticipated work during idle and reuse it (out-of-band).
- Refuse infeasible launches with an actionable explanation, so a 16 GB machine
  never tries to load a 64 GB model (P3).

## Projected impact

A guess, stated plainly: **notable on battery and on all three thermal symptoms
(fan, throttle, lap), with the battery win coming mostly from "less work" and
only second-order from out-of-band.** There is no hidden throttle in the backlog
— pacing is parked because the engine rejects below 100 and idle is already
<1W — so the win is in doing less work and re-timing what remains, not in
capping watts. The floor: a Laguna session pins ~6.1 GB of GPU scratch, the GPU
path is serialized, and a genuinely deep prefill is still a deep prefill when
you need one.

## Caveats

The 7x curve was measured on an idle machine, over sessions under ~25 minutes,
on a narrow single-topic workload — no hour-plus thermal soak, so the heat/fan
link was never directly observed at that scale. The out-of-band and ladder
claims are design intent, not measurement: the enabling facts (healthy prefix
cache, <1W idle, snapshot cost) are measured, but the reuse win has not been.
