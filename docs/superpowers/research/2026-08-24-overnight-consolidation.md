# Overnight consolidation — 2026-08-24

**Purpose.** Several parallel chats produced overlapping, partly stale research on the
Mellum line, the P11 agent test, and the engine merge. This document is the staging area
for consolidating them. **Each session appends one section.** Nothing here is merged or
deduplicated yet; that is the next pass, once every session has contributed.

**Rules for a section.** State what remains true, state what was *disproven* (that is
often the more valuable half), link every file the session wrote, and name the work it
believes comes next. Leave out anything later contradicted, except where recording the
contradiction prevents someone re-deriving a dead end.

---

## Section A — Mellum integration, quantization, and agentic limits

**Session scope:** 2026-08-23 evening → 2026-08-24 early morning. Covers the ds4 engine
merge for Mellum, the memory-footprint correction, a down-quantization shootout, the
first AgentClinic runs against Mellum, and a specialist-pipeline experiment.

**Not in scope, and owned by other sessions:** the Laguna/Flash hard-spec resolution
(`--nothink` + pinned contract facts, commits `914a84d`, `7bf00d9`), tool-budget and
think-loop bounding (`dec657e`, `73cec15`, `9abc310`), and the three-role thinking
pipeline spec (`2026-08-24-laguna-revision-test-spec.md`, untracked). Those changed a
baseline this session measured against — see "Overlaps to resolve."

### A1. Conclusions that still hold

**Engine and artifact**

- **The shipping artifact is the 9.33 GiB selective build**: Q4_K on expert gate/up for
  layers 0–21, Q8_0 everywhere else including all 28 down-projection layers. ds4 loads it
  and generates from it. Decode ~0.94x of pure Q8_0.
- **Real memory at 40k context is ≈10.3 GiB** (9.33 GiB weights + ~0.9–1.0 GiB true
  KV/scratch). This clears a 13 GiB budget with ~2.5 GiB margin. The stated 16 GB-class
  target is met arithmetically, **by simulation and source analysis only** — no real
  16 GB hardware run has ever happened, and the user has deprioritized getting one.
- **`planned_bytes` under-reported Mellum's non-weight memory by ~0.7–1.0 GiB at 40k
  context** — the same bug class already known on Laguna.
  `ds4_context_memory_estimate_with_prefill_mode` (ds4.c:36293) had no
  `DS4_MODEL_FAMILY_MELLUM` branch and fell through to a generic path built for a
  compressive-KV architecture: it hard-caps KV rows at 8192 regardless of `--ctx` and
  never multiplies by `n_head_kv`, and it misses `mellum_prefill_workspace` (~130 MiB)
  and the MoE `s_partial` buffer (~75 MiB) entirely. **Fixed** on the merge branch
  (commit `5208cce`). Note the fix makes the estimate report *more* memory, so any
  preflight gating on it may now refuse configurations that previously (wrongly) passed.
- **Down-projection quantization stays Q8_0.** Measured, not assumed — see A2.
- **Prefill for the Q4_K/Q8 artifact is still slow (~0.21x of Q8_0's batched path)**
  because the expert-major batch kernel stages Q8_0 rows and cannot run Q4_K, forcing the
  tokenwise sync path. This is the largest remaining engineering item on the engine side.

**Architecture (re-confirmed, not new)**

- **SSD streaming, not quantization, is ds4's memory lever.** At a fixed quant level the
  streamed path holds only a budgeted working set of routed experts resident; the normal
  path holds the whole model. For Laguna S at uniform Q3 that is ~22 GiB streamed vs
  ~47 GiB resident. The normal (non-streaming) path is the *high*-memory option.
- **At Q8 there is no ds4-specific weight-memory trick** — same GGUF, same block layout
  as llama.cpp, which ds4 credits directly. Any KV-size advantage on DeepSeek V4 comes
  from that model's own compressed-latent attention, which any correct implementation
  must also implement.
- **Embedding the engine in the Swift app remains rejected**, including the phased
  "supervised now, embedded later" variant. Only dynamic Swift-defined per-token logit
  masking and zero-copy logits genuinely require it, and neither is critical-path.

**Mellum's agentic behavior** — the load-bearing findings of the session

- **Protocol compliance is solved; agent competence is not.** Forced single-tool canary:
  18/20 executed. Open-ended multi-file build: 0 tool calls, on both the detailed and the
  user-story spec. The model narrates a complete, *correct-in-content* solution and stops.
- **Confounds ruled out**: quantization (identical on Q8_0 and Q4_K/Q8), thinking mode
  (identical with `--nothink`), and harness path (Laguna produced 144 tool events through
  the identical pool path the same evening).
- **`DS4_AGENT_TOOL_NUDGE` does not rescue it in the pool path.** The mechanism fires
  correctly — verified in source and observed firing twice — and the model responds by
  re-narrating near-identical content across 3 rounds and ~3,300 tokens.
- **No in-context belief revision under contradicting evidence.** Shown its own offending
  line *and* the verbatim `ImportError` naming the exact symbol, Mellum re-emitted its
  entire 3.8K file **byte-for-byte identically** (`diff` reports no difference). The same
  hallucinated import (`from fastapi import RedirectResponse`) appears in an earlier,
  independent nudge-forced run — two mechanisms, same wrong tokens, so it is stable
  behavior rather than sampling noise.
- **Host-controlled text mode is the one thing that worked.** Taking the model out of the
  agentic loop entirely — host runs the test, selects the file, writes the result, and
  verifies — produced the first host-verified correct Mellum code change in this project
  (a `default_factory` bug fixed byte-identically to the reference, confirmed by a real
  `pytest` exit code).
- **The lever is mode, not role.** Specialization in the pipeline experiment was shallow
  by necessity and still worked: no Swift changes, no per-role system prompts at the
  engine level, no per-role sampling, no concurrency. Roles differed only by prompt text
  and which model binary was invoked.

### A2. Conclusions that were disproven or superseded

Recorded so nobody re-derives them.

| Claim | Status |
|---|---|
| "Mellum passed the easy AgentClinic spec" | **False, never happened.** Laguna passed it, in a separate earlier baseline. Mellum scored 0 tool calls on both specs. Best Mellum has ever achieved is 2-of-4 files (nudge-forced) whose code did not run. |
| "Thinking mode causes the tool-call failure" | **Ruled out.** `--nothink` reproduces it exactly. |
| "A corrective nudge converts narration into work" | **Not in the pool path.** True once in an older standalone run (0→8 tool calls, 2/4 files, broken code); failed cleanly when retested. |
| "Q5_0 on down layers is a viable shrink" | **Fails outright.** Reproducible `NaN` on ordinary held-out text (`negative standard deviation of log(prob)`), confirmed outside the comparison harness. BF16/Q8_0/MXFP4 process the identical file cleanly. |
| "MXFP4 on down layers is near-parity" | **No.** ~5.5x Q8_0's own KLD from BF16 and ~2.1x its RMS Δp. Clean (no NaNs) but well outside the pre-committed strict threshold. |
| "ds4's Q8_0 sits 0.085% from an FP32 oracle" | **Misread.** That figure is ds4-vs-llama.cpp with *both* at Q8_0. Actual Q8_0-vs-FP32 logit RMS in that record is **2.40%**. Any threshold anchored on 0.085% is wrong by ~28x. |
| "10.5 GB is a workable total budget" | **Too tight.** 9.40 GiB planned + real KV/scratch leaves almost no headroom at 16k ctx, let alone 40k. Revised target: 13 GiB at 40k context. |
| "The 8.59 GiB build is the selective artifact" | **Wrong target.** That was Q4_K on all 28 layers with no imatrix. The real target is 9.33 GiB: imatrix-calibrated, Q4_K restricted to layers 0–21. |
| "The mixed Q4_K/Q8 artifact has never been built / has no caller" (`engine-lines.md`) | **Stale.** Built, measured, loads, generates, and has a dedicated `kernel_mellum_q4_K_pair_swiglu_f32` ~25% faster than the borrowed GLM kernel. Corrected in commit `1603570`. |
| "Batched prefill is not wired into `ds4_session_sync`" | **Stale.** It is wired. |
| Framing: "get Mellum from easy to hard" | **Category error.** Mellum handles neither. The decomposer idea bridges *Laguna*, with Mellum as a specialist. |
| "The decomposer will flip the hard spec from fail to pass" | **Untestable as run.** Laguna already passed the hard spec by then (another session's fix). The result degraded to a cost measurement. |

### A3. Open questions this session could not close

- **Does the repaired `split_decode_rows` Metal path ever actually execute?** The merge
  fixed it so it *compiles* (it referenced globals that did not exist), but no test is
  known to exercise it at runtime.
- **`comp_cap` now carries a sliding-window meaning under a compressive-KV name.** Safe
  today because callers sum `total_bytes`, but a semantic landmine if anything reads the
  field by name.
- **Whether the fabricated-validation pattern and the byte-identical re-emission share a
  mechanism.** They look like the same thing viewed twice, but that is inference.
- **Whether any of this is Mellum-specific or general to small MoE models.** No
  comparison against another model of similar active-parameter count was run.

### A4. Files written or changed by this session

**swiftstar** (`~/projects/pauleveritt/swiftstar`)

- [`docs/superpowers/research/2026-08-23-mellum-agentic-tool-use-finding.md`](2026-08-23-mellum-agentic-tool-use-finding.md)
  — write-up drafted for possible sharing with the Mellum/JetBrains team. **Not sent
  anywhere.** Untracked.
- [`docs/superpowers/research/2026-08-23-p11-agenttest-mellum-verification-record.md`](2026-08-23-p11-agenttest-mellum-verification-record.md)
  — the two AgentClinic runs and the nudge follow-up. Commits `9226953`, `88669a4`.
- [`docs/harvest/engine-lines.md`](../../harvest/engine-lines.md) — stale Mellum claims
  corrected and the real P12 inheritance list written. Commit `1603570`.
- `fixtures/agenttest/specs/roadmap-user-story-mellum-decomposed.md` — Mellum's actual
  decomposition output, the input that produced the cost reduction. Untracked; worth
  keeping as evidence.

**ds4 — branch `swiftstar-integration-mellum`** (`~/projects/ds4/.claude/worktrees/swiftstar-integration-mellum`)

Four commits, tip `cde6438`. Metal and CPU builds clean, `ds4_test --metal-kernels`
green, live Mellum smoke test passes. **Not yet pinned by the swiftstar submodule.**

- `d40d4f8` — merge of `mellum-2.1-overnight` (9 real conflicts, resolved semantically).
- `5208cce` — the `planned_bytes` Mellum branch.
- `7dbe4b6` — build fixes for two bugs that clean auto-merges still left broken.
- `cde6438` — reconciliation merge of the concurrent P11 commit `8784fe6`.

**ds4 — branch `mellum-repair-pipeline`**, commit `9e21c05`

- [`docs/superpowers/research/2026-08-24-mellum-specialist-pipeline.md`](file:///Users/pauleveritt/projects/ds4/.claude/worktrees/mellum-repair-pipeline/docs/superpowers/research/2026-08-24-mellum-specialist-pipeline.md)
  — full record of the decompose/build/validate/repair experiment.
- `pipeline/` — scripts, role prompts, and per-round prompt/output/pytest logs for every
  run (61 files).

**ds4 — earlier in the session** (`~/projects/ds4/.claude/worktrees/mellum-2.1`)

- `docs/superpowers/MELLUM.md` — current-state runbook.
- `docs/superpowers/plans/mellum-q4k-artifact.md` — the three-piece Q4_K brief.
- `tools/mellum/build-selective-artifact.sh` — reproduces the 9.33 GiB artifact (~15 min).
- `tools/mellum/RESULTS-selective-artifact.md` — its measurements.
- `docs/superpowers/research/2026-08-21-mellum-experiment-journal.md` — archived journal.

**Data artifacts** — `~/projects/ds4/gguf/mellum-quant-research/` (~58 GB, kept)

BF16 intermediate, a fresh 41 MB imatrix, both down-quant candidates
(`mellum-down-Q5_0.gguf`, `mellum-down-MXFP4.gguf`), the Q8_0 baseline, KLD logs, and
greedy-generation transcripts. The shipping artifact itself is
`~/models/mellum-thinking-TARGET.gguf`.

### A5. What this session thinks comes next

**Immediate, already agreed**

1. **Land `swiftstar-integration-mellum` and bump the swiftstar submodule pin.** This is
   the only step between here and Mellum being loadable in the app. Reconciliation with
   the concurrent P11 work is already done; the branch is one commit ahead of what the
   submodule points at.
2. **Point `modelPath` at the artifact** — SwiftStar has no `Variant` type yet, just an
   `@AppStorage("modelPath")` string plus a file picker, so this is a preset entry in
   `SettingsView.swift`, not a new abstraction.

**Engine work, in value order**

3. **Q4_K expert-major prefill.** The 0.21x prefill penalty is the one thing a user would
   actually feel. Scoped in `mellum-q4k-artifact.md`; note the Q8 pair kernel already uses
   18,432 of 32,768 threadgroup bytes, so a second variant may need restructuring rather
   than copying.
4. **The subagent-pool cross-worker coalescing bug.** `agent_prompt_queue` is global and
   worker-id-less, so a prompt for a busy worker can be drained into a *different*
   worker's turn. Defeats the isolation the pool exists for. Reproduction and fix
   direction recorded; already spun off as a task.

**The experiment that follows directly from the night's actual finding**

5. **Run the build step in host-controlled text mode, all-Mellum.** Never tried. Mellum's
   easy-spec failure was producing a complete, correct-in-content five-file solution as
   prose and never writing it — if the host harvests that text and writes the files, the
   same move that made repair work, it may pass. Cheap, and the only configuration the
   mode finding directly implies.

**Decisions the user still owns**

6. **Whether to send the Mellum-team report**, and to whom. Drafted, verified, not sent.
7. **Whether P12 proceeds with Mellum scoped as a "focused tasks" model** rather than an
   autonomous coding agent. Tonight's evidence supports the former and not the latter.
   P12 still owes fixtures (none are Mellum-shaped), a `Variant` runtime contract (a rope
   export alone once flipped a greedy token at 26 tokens), and feasibility-gate wiring.

### A6. Overlaps to resolve during consolidation

- **The Laguna hard-spec result is contested across sessions.** This session recorded
  Laguna failing the hard spec at phase 2, then observed it passing mid-experiment.
  Commits `914a84d` and `7bf00d9` from another session are the likely cause
  (`--nothink` + pinned contract facts). Whoever consolidates should take that session's
  account as authoritative and treat this section's baseline numbers as pre-fix.
- **`DS4_AGENT_TOOL_NUDGE` appears in two records with opposite outcomes.** Both are
  correct: it worked once in an older standalone run and failed in the pool path. The
  consolidated version should keep both and note the path difference.
- **Tool-budget and think-loop bounding** (`dec657e`, `73cec15`, `9abc310`) may have
  changed conditions under which this session's 0-tool-call runs were measured. Worth a
  re-check before quoting those telemetry numbers as current.
- **Three research docs now describe Mellum's agentic limits** (`MELLUM.md`, the
  agentic-tool-use finding, the specialist-pipeline record). They agree, but the first is
  a runbook and the other two are findings — consolidation should keep the runbook thin
  and point it at the findings rather than restating them.

---

## Section B — Footprint decomposition, host tool-call robustness, and style compilation

**Session scope:** 2026-08-23 → 2026-08-24, on branch `mellum-2.1-overnight`. Covers the
tool-calling robustness work and its closing control run, a Laguna XS 2.1 transfer
investigation, a full weight decomposition and quant-targeting exercise, doc dedup, and
one unrelated swiftstar research note.

**Read A2 first.** This session's headline recommendation — target Q5_0 on down —
**was measured and killed by Section A**, whose evidence is authoritative here. What
survives is the structural analysis that motivated the shootout, one release-blocking
correctness defect, and the procedural call to measure before building.

### B1. Conclusions that still hold

**Weight decomposition** (computed from GGUF block geometry; reproduces the published
12.03 / 9.33 GiB totals, the measured `mapped 9554.64 MiB` load, and — as an out-of-sample
check — the official artifact's known 7.52 GiB from its verified inventory)

| Category | Q8_0 (12.03) | selective (9.33) |
|---|---:|---:|
| Expert gate | 3.66 | 2.30 |
| Expert up | 3.66 | 2.30 |
| **Expert down** | **3.66** | **3.66** |
| Attention / embed / head / norms | 1.05 | 1.05 |

- **Down is 39% of the shipping artifact and the only expert projection untouched.**
  This remains the correct statement of where the weight is, even though the attempt to
  compress it failed.
- **No K-quant can ever reach down.** Its contiguous dimension is 896; K-quants use
  256-element superblocks and 896 ÷ 256 = 3.5. Enforced in ds4 at `ds4.c:4576` and
  `ds4.c:5444–5456`; no padding or partial-block path exists. **Q8_0 works only because
  its block is 32.** So this is geometry, not a tunable — and it means **Q6_K is not a
  candidate for down in any future attempt**, and on gate/up it is *larger* than the Q4_K
  already shipping (0.8203 vs 0.5625 B/elem). Both directions dead.
- **Context is nearly free.** Only 7 of 28 layers scale with `--ctx`; the other 21 are
  sliding-window pinned at 1024 rows. KV alone is 0.26 GiB at 16k, 0.48 at 32k, **0.59 at
  40k**. Independently consistent with Section A's ~0.9–1.0 GiB true KV+scratch at 40k.
  **Weights are the whole game; context budget is not the constraint.**

**A release-blocking correctness defect — the highest-value item in this section**

- **Batch-prefill eligibility infers layout from the wrong tensor.**
  `ds4_engine_bind_mellum_decode_contract` sets `mellum_batched_prefill_unsupported` by
  testing **only** `src->ffn_gate_exps->type == DS4_TENSOR_Q4_K` (`ds4.c:36895`). It never
  inspects down, and all four down kernels are Q8_0-only (`metal/moe.metal:2984, 3038,
  3211, 3230`). Any artifact with Q8_0 gate/up and a non-Q8_0 down leaves that boolean
  *false*, engages the batch path, and runs `kernel_mellum_q8_0_down_batch_f32` over
  foreign bytes — **wrong output, no error**. Verified in code.
- **The fix is an admission contract, not a wider boolean.** No dispatch site should infer
  Q8_0 layout from "not Q4_K"; that inference *is* the defect, and widening the test
  leaves the same trap for the next format. Define supported quant × path combinations
  (decode, token-batch, grouped prefill) and refuse the rest loudly.
- **This survives the death of Q5_0 entirely.** It is a latent silent-corruption pattern
  in the dispatch layer, not a quantization concern.

**Laguna XS 2.1's memory wins do not transfer** (both checked against code, not assumed)

- **The prefill-chunk scratch win has no analogue.** Mellum's per-chunk-token cost is
  ~0.13 GB (prefill workspace alone) or ~0.20 GB counting the MoE bucketing statics —
  20–30× smaller than Laguna's 3.97 GiB. Nothing to recover. Two corrections worth
  keeping: the ~6.1 GB figure associated with Laguna is a *total-resident projection*, not
  scratch; and **Mellum's 1024 chunk cap is structural, not a stale guard** — the sliding
  layers' KV ring is allocated at exactly `DS4_N_SWA`, so a wider chunk would wrap. The
  opposite of Laguna's incidental family-level refusal.
- **The slab-class win does not exist here.** That machinery is SSD-streaming-only and
  Mellum refuses `--ssd-streaming` outright. Unrelated to Mellum having no dense prefix,
  which was the first guess and was wrong.
- **What does transfer is the lesson, via a different mechanism:** the whole-model
  eligibility boolean above is Laguna's uniformity penalty in miniature — non-uniformity
  tripping an all-or-nothing gate that costs more than the non-uniform part. Scoping it
  per layer would recover the six pure-Q8_0 layers, worth **~1.17–1.20× on prefill**
  (arithmetic on published path ratios; 0.21× → ~0.25×). Whether the two paths can be
  mixed *within one prefill pass* is **unverified** — if not, this is a loop restructure,
  not a scoping change.

**`use_more_bits` is positional** (verified against pinned llama.cpp source)

`src/llama-quant.cpp:426` is `i_layer < n_layers/8 || i_layer >= 7*n_layers/8 ||
(i_layer - n_layers/8)%3 == 2` — first eighth, last eighth, every third middle layer. It
consults no imatrix, no weights, no measurement of any model. For n=28 it yields the
official artifact's exact split (Q8_0: 0,1,2,5,8,11,14,17,20,23–27). **Useful to keep:
any future appeal to "the reference artifact chose these layers" is appealing to a
generic positional formula, not to measured sensitivity.**

**Host tool-call robustness** — landed in `66cbf83`, independent of Mellum's competence

- Malformed tool calls retried without limit (one observed turn looped 63 rounds); now
  capped at 2 corrections.
- An unterminated tool call grew unbounded — an observed write degenerated to ~26K output
  tokens and only stopped when compaction failed, losing the whole attempt including
  completed earlier rounds. Now a 64 KiB cap plus a tail-repetition detector.
- **That detector had a false positive on ordinary content:** at unit=1 it fired on 24
  identical bytes, so a markdown rule, an RST underline or a run of padding inside any
  write past 512 bytes was killed as "degeneration". Fixed with a 64-byte span floor;
  regression test trips at byte 2141 under the old constant and passes under the floor,
  while the real `V5V5` runaway is still caught at byte 512 unchanged.
- Host corrections (nudge, preflight error, malformed-call error) were sent as `role=tool`
  with no matching `tool_call` in history, causing a self-referential confusion loop.
  Now `role=user`; only genuinely executed calls are `role=tool`.
- Hitting `-n` mid-call is now classified apart from malformed JSON — "cut off before you
  could finish valid JSON" reads very differently to a model than "you wrote invalid JSON".

### B2. Conclusions disproven or superseded

| Claim | Status |
|---|---|
| **"Target Q5_0 on down; ~8.53 GiB at 40k is the shipping target"** | **Superseded by measurement (Section A).** Q5_0 down produces reproducible `NaN` on held-out text; MXFP4 lands ~5.5× Q8_0's own KLD from BF16. **Down stays Q8_0.** The whole 7.29–8.53 GiB target family is void. |
| "MXFP4 is worth evaluating as a cheaper alternative" | **Evaluated and rejected** (Section A). The loop this session opened is closed. |
| "The official 14/14 split evidences that 5-bit down is safe" | **Self-retracted twice.** First: the split is a mechanical shape-fallback (Q6_K→Q8_0, Q4_K→Q5_0), not a quality choice. Then: my repair — that the *placement* still encodes a real sensitivity ranking — was **also wrong**, since `use_more_bits` is purely positional. Section A then made the whole question moot. |
| "Mellum's `buffers 0.00 GiB` means graph scratch is omitted from the planned total" | **Wrong mechanism, right smell.** Scratch *is* summed in; it prints 0.00 because the missing family branch leaves the estimate at ~99 KB. Corroborated and **already fixed** by Section A's `5208cce`. |
| "KV is under-reported ~7× flat" | **Imprecise.** The reported figure is ctx-invariant (0.068 GiB always), so the error is 3.8× at 16k and ~7× at 32k, growing with context. |
| "Mellum's prefill scratch is ~202 KiB/token" | **~55% high and unshown.** ~130 KiB/token for the prefill workspace proper; the extra 74 KiB is MoE bucketing statics whose membership in the same budget is unresolved. Conclusion unaffected. |
| "The target lands in the class of something demonstrated on the hardware — no swap at 10.9 GB free" | **Imported invalidated evidence.** The source note disavows its own pressure test: the zero-page ballast compressed away, so that proves nothing. Only the 8.24–10.18 GB RSS band is citable. |
| "Thinking mode causes Mellum's tool-call failure" | **Ruled out** — agrees with A2. This session ran the Q8_0 `--nothink` control: rc=0 in 7s, 0 tool calls, 0/4 files, both nudges exhausted, model narrated "I cannot directly access files" and stopped on its own. Possibly the same run A2 cites; see B6. |
| "`make test` is a green/red signal in this worktree" | **It is not.** `ds4_test` aborts at `long-context` needing `ds4flash.gguf`, absent here, and fails identically on a stashed tree. Everything else in the target builds and passes. |
| Plan doc: "Still missing: a layer-level gate" | **Stale.** `test_metal_mellum_q4_layer` exists. Section should be deleted. |

### B3. The procedural call that paid off

This session's sequence put a **llama.cpp-only format shootout ahead of any ds4 kernel
work**, explicitly to avoid committing four new kernels before resolving the one question
that decides which kernels to write. Section A then ran that shootout and both candidates
failed. **The ordering saved the kernel project.** Worth preserving as a rule: when a
format decision gates a multi-kernel commitment and the format is measurable in a tool
that already supports it, measure first — and use teacher-forced logits, greedy-token
agreement and perplexity, not agent task scores, which are too noisy and (here) drawn
from prompts inside the imatrix calibration set.

### B4. Files written or changed

**ds4 — branch `mellum-2.1-overnight`** (`~/projects/ds4/.claude/worktrees/mellum-2.1`),
seven commits `2f8bd32`…`e739816`. **Not merged into
`swiftstar-integration-mellum`;** Section A's merge (`d40d4f8`) predates these.

- [`docs/superpowers/research/2026-08-23-mellum-footprint-target.md`](file:///Users/pauleveritt/projects/ds4/.claude/worktrees/mellum-2.1/docs/superpowers/research/2026-08-23-mellum-footprint-target.md)
  — **new.** The decomposition, geometry argument, Laguna non-transfer, estimator defects.
  **Its target section is now void** per Section A and needs a superseded banner.
- [`docs/superpowers/plans/mellum-q4k-artifact.md`](file:///Users/pauleveritt/projects/ds4/.claude/worktrees/mellum-2.1/docs/superpowers/plans/mellum-q4k-artifact.md)
  — deduped against `MELLUM.md` (`442e8d3`), then given pieces 3a and 4 and a sequence
  that is now partly void.
- [`docs/superpowers/MELLUM.md`](file:///Users/pauleveritt/projects/ds4/.claude/worktrees/mellum-2.1/docs/superpowers/MELLUM.md)
  — the `--nothink` control paragraph; Mellum marked paused.
- `ds4_agent.c` — the robustness work in B1, plus three regression tests.
- `tools/mellum/agent-eval/{phase1.sh,run_arm.sh}` — `-n` 4096 → 8192.

**swiftstar — branch `p11-subagent-pool`**, commit `5ffc16c`

- [`docs/superpowers/research/2026-08-23-house-style-as-a-compiled-artifact.md`](2026-08-23-house-style-as-a-compiled-artifact.md)
  — **new, unrelated to Mellum.** Style inference re-run per prompt is a recomputation
  over a slowly-changing corpus; the load-bearing move is *style as a P9/P10 objective*
  rather than prompt content, with an out-of-band pass compiling what it can into
  executable checks, canonical exemplar election feeding D5's names-only staged reads, and
  the correction stream mined for anti-patterns. Records the constraint that bounds
  specialists: exact-prefix-only KV reuse plus D8's shared-root short-lived workers makes a
  per-specialist recipe a divergent prefix, so recipes are not free. **Nothing in it is
  measured**; it names the compile fraction on tdom's practices as the falsifying number.
- `ROADMAP.md` — matching backlog entry.

**Memory** — `project_mellum_fabricated_validation.md` (fabricated-validation finding and
the P9/P10 action-mode design that answers it).

### B5. What this section thinks comes next

**Footprint is closed as a track.** With down locked at Q8_0 and Laguna's levers ruled
out, there is no multi-GiB weight lever left. Real memory stays ~10.3 GiB at 40k
(Section A). **Prefill is now the only engine item a user would feel** — which agrees with
Section A's ranking, arrived at independently.

1. **The admission contract** (`ds4.c:36895`). Release-blocking, format-independent,
   silent-corruption class. Should land regardless of what happens to quantization.
2. **Q4_K expert-major prefill (piece 3)** — the 0.21× penalty. Target **~300–350 t/s**,
   restoring the Q8_0 expert-major rate, *not* llama.cpp's ~4,000. Endpoint is one shared
   grouped schedule with format-specific row staging; tensor-core work is unnecessary.
3. **Piece 3a, per-layer eligibility** — ~1.17–1.20× for the six pure-Q8_0 layers.
   Cheap *if* paths can mix in one pass; verify that before costing it. Do **not**
   sequence it before piece 3's measurement, or neither result is attributable.
4. **`--prefill-chunk` is accepted and ignored** — it reaches only the estimator, so it
   silently alters diagnostics and nothing else. Wire it or refuse it as GLM does. Note
   the `DS4_MELLUM_PREFILL_CHUNK` **env var does work**; only the CLI flag is inert.
5. **One surviving footprint candidate, small and untested:** extend Q4_K gate/up from
   layers 0–21 to all 28 (9.33 → 8.59 GiB). Same format already validated on 22 of 28
   layers, so far lower risk than any new format on down. A2 notes an 8.59 GiB all-28
   build exists *without* imatrix — **all-28 with imatrix appears untested**, and whether
   the 0–21 restriction was itself a quality decision is not something this session has
   evidence about. Worth one KLD run before it is either adopted or discarded.
6. **Carried debt:** the layer-0 oracle fails on Q4_K (`max_abs=0.0298` against a `0.006`
   limit calibrated for Q8_0) and needs an *independent* Q4_K reference — llama.cpp's
   layer-0 output on the same artifact — and explicitly must **not** be "fixed" by raising
   the threshold. Plus the `ds4_gpu_mellum_q8_0_*` naming fossils now carrying Q4_K, and
   the stale layer-level-gate section to delete.

**Not scheduled: Mellum agent competence.** Paused deliberately. Generic retry cannot fix
fabricated validation, and the answer is the P9/P10 host-controlled action mode — declared
objectives, host-reported state, a retry round requiring a registered tool call, and
claimed test results never trusted without a recorded execution. Section A's host-controlled
text-mode result is the first positive evidence for that design and should be read as
support for it.

### B6. Overlaps to resolve during consolidation

- **Section A supersedes this section on quantization.** Where B named a Q5_0/MXFP4
  target, A has measurements. A wins. B's decomposition and geometry argument remain the
  explanation for *why* down was the target and why nothing else can reach it — keep those,
  drop the target.
- **The `--nothink` control may be double-counted.** A2 and B2 both report thinking mode
  ruled out. B ran a Q8_0 control at `-n 8192`, nudge=2, 180s (rc=0 in 7s, 0 calls, 0/4
  files). If A's is the same run, keep one; if independent, note n=2.
- **The estimator fix is recorded twice.** B diagnosed it on `mellum-2.1-overnight`; A
  fixed it on `swiftstar-integration-mellum` (`5208cce`). Keep A's, and check B's KV
  arithmetic (0.26 / 0.48 / 0.59 GiB at 16k / 32k / 40k) against what A actually shipped.
- **Seven commits on `mellum-2.1-overnight` are not in the integration branch.** One is
  code (`66cbf83`, tool-call robustness), the rest are docs. The code commit is
  independent of Mellum and should be carried forward; the doc commits need the
  superseded-target banner first.
- **`mellum-q4k-artifact.md` now contains a sequence that is partly void.** Steps 1–3 of
  its "agreed sequence" were the format shootout, which A has run. Rewrite to start at the
  admission contract.

### B7. Uncommitted and untracked work across the trees (survey, 2026-08-24)

**Not written by this session** — surveyed because consolidation needs to know what is
unlanded and at risk. Nothing below has been touched, staged, or committed here.

**swiftstar — `p11-subagent-pool`, working tree**

- `docs/superpowers/research/2026-08-24-handoff-packet-frontmatter-schema.md` (133 lines)
  — **untracked research.** "Handoff packet frontmatter schema — draft v1."
- `docs/superpowers/research/2026-08-24-laguna-revision-test-spec.md` (179 lines) —
  **untracked research.** "Laguna S revision test — spec." Section A names this as
  another session's artifact and as out of its scope; it is unlanded.
- **An unlanded feature**, coherent as a set: `Sources/SwiftStarKit/HandoffPacket.swift`
  (modified) plus untracked `HandoffPacketValidator.swift`, `PacketFrontmatter.swift`, and
  `Tests/SwiftStarKitTests/{HandoffPacketValidatorTests,PacketFrontmatterTests}.swift`.
  This is the frontmatter-schema doc's implementation. **Highest-value uncommitted work in
  any tree** — it is P10/P11 packet machinery with tests, and it exists only in the
  working tree.
- `claude_metrics.png` — untracked, provenance unknown.

**ds4 — main checkout `paul/laguna`**

- Untracked research: `docs/superpowers/research/2026-07-29-laguna-s-streaming-footprint.md`,
  `docs/superpowers/research/ds4-laguna-s-greedy-pi-extension.ts`.
- Untracked plan + spec: `docs/superpowers/plans/2026-07-29-tblite-harvest-plan.md`, and
  the entire `docs/superpowers/specs/` directory (one file,
  `2026-07-29-tblite-harvest-design.md`, 12.1K) — **the directory itself is untracked**,
  so nothing in it is under version control.
- Modified: `docs/superpowers/plans/2026-07-29-tblite-scoping-brief.md`,
  `docs/superpowers/superpowers/roadmap-backlog.md`.
- `p28-prefill.log` — untracked output.
- **These are all ~2026-07-29 tblite/Laguna-S work, older than any session in this
  document.** They predate the Mellum line and may be abandoned rather than pending;
  someone who knows that history should decide, not a consolidation pass.

**ds4 — `laguna-xs2.1` (branch `laguna-s21-ssd`)**

- Modified `docs/superpowers/plans/mini-notes.md` — this is the file Section A and B both
  cite for Laguna's scratch and 32 GB acceptance numbers, so an uncommitted edit to it is
  worth reading before quoting either.
- Untracked `gguf` and `p28-prefill.log`.

**ds4 — `mellum-repair-pipeline`**

- Untracked `pipeline/run_laguna.sh` and three untracked log directories
  (`laguna-revision-l1-redirect-q2`, `laguna-revision-l3-nearmiss-q2`,
  `laguna-revision-l3-nearmiss`), plus `scratch/`. Section A committed `pipeline/` at
  `9e21c05`; **these Laguna-revision runs came after and are not in it** — they are
  evidence for the revision-test spec above.

**ds4 — bench worktrees**

- `ds4-main-bench`: `speed-bench/main_bench.csv`.
- `ds4f-mxfp4-bench`: `speed-bench/mxfp4branch_{iq2xxs,mxfp4,mxfp4_rerun}_bench.csv` —
  **MXFP4 benchmark data**, possibly relevant to A2's MXFP4 rejection, which was a
  *quality* result; these are speed.
- `swiftstar-integration-mellum`: untracked `gguf`.

**Clean:** `mellum-2.1` (all seven commits landed), `context-firewall`, `laguna-s-bench`.

**What a consolidator should do with this:** the swiftstar packet-validator set is real
unlanded code with tests and should be landed or explicitly parked; the two swiftstar
research docs need owners; the `paul/laguna` tblite material needs an
abandoned-or-pending call from whoever wrote it; and `mini-notes.md`'s uncommitted diff
should be read before anyone quotes Laguna scratch figures from it.
