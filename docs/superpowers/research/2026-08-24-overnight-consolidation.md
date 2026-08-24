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

### A7. The corpus that needs consolidating

*Global inventory, contributed by this session — not session-A-specific. Surveyed
2026-08-24. `docs/superpowers/` in swiftstar currently holds 27 research notes, 12 plans,
and 13 specs, plus 6 harvest briefs. Listing every file would not help; these are the
clusters where genuine overlap or staleness lives.*

**Cluster 1 — the P11 agent test (densest overlap, 7 documents).**
`plans/2026-08-23-p11-agenttest-addendum.md`, `specs/2026-08-23-p11-agenttest-addendum-design.md`,
and five research notes: `2026-08-23-p11-agenttest-verification-record.md` (Laguna
baseline), `-mellum-verification-record.md` (this session), `-laguna-hard-analysis.md`,
`-telemetry-review.md`, plus the untracked `2026-08-24-laguna-revision-test-spec.md`.
These were written across at least three sessions against a moving harness, and at least
one baseline (Laguna's hard-spec outcome) changed mid-stream. **Highest-value merge
target.**

**Cluster 2 — external model reviews of P11 (4 documents).**
`2026-08-23-p11-glm-5.3-review.md`, `-glm-5.3-spec-plan-review.md`, `-kimi-k3-review.md`,
and the two gate notes `-p11-measurement-gate.md`, `-p11-smoke-gate.md`. Reviews are
point-in-time by nature; consolidation should extract what was *acted on* and archive the
rest rather than keeping five parallel opinions live.

**Cluster 3 — Mellum agentic limits (3 documents).** Covered in A6.

**Cluster 4 — memory and footprint.** This session's `planned_bytes` correction, Section
B's footprint decomposition, and — easy to miss — an untracked ds4 note,
`docs/superpowers/research/2026-07-29-laguna-s-streaming-footprint.md` in
`~/projects/ds4`, which contains the streamed-vs-resident arithmetic and the aging-LFU
cache-policy findings this session cited. **That note exists only as an untracked file on
one disk.**

**Cluster 5 — designed but not built.** `2026-08-23-monty-and-the-ane-watcher-tier.md`,
`2026-08-23-house-style-as-a-compiled-artifact.md`, and the untracked
`2026-08-24-handoff-packet-frontmatter-schema.md`. All three are explicitly speculative
("nothing here is measured"). They should stay clearly labelled as unbuilt so a later
reader does not mistake them for shipped design.

**Cluster 6 — the ds4-side Mellum docs**, in the `mellum-2.1` worktree: `MELLUM.md`
(runbook), `plans/mellum-q4k-artifact.md` (the three-piece brief, partly completed by
this session's merge), `tools/mellum/RESULTS-selective-artifact.md`, and the archived
`research/2026-08-21-mellum-experiment-journal.md`. The brief in particular now overstates
what remains: mixed-layout validation and Q4_K decode are done; only Q4_K prefill is open.

### A8. Uncommitted and unpushed state across the trees

*Surveyed 2026-08-24. This is a fragility inventory, not a to-do list — but several items
exist on exactly one disk with no remote.*

> **Merge with B7.** Another session ran this same survey independently within minutes
> (commit `fcddded`), so A8 and B7 are near-duplicates and must be merged, not read as two
> corroborating sources. They complement rather than conflict: B7 has line counts and the
> judgment that the uncommitted `HandoffPacket` feature set is the highest-value unlanded
> work; A8 has the per-branch upstream table and the unpushed-commit counts. That two
> sessions duplicated a survey this cheaply, on the same night, is itself evidence for why
> this consolidation exists.

**swiftstar** (`p11-subagent-pool`, at `87e6a64`)

- **No upstream tracking at all — this repository has never been pushed.** Every commit
  from every session tonight exists only locally.
- Eight dirty paths, including an **in-flight feature from another session**:
  `Sources/SwiftStarKit/HandoffPacket.swift` (modified), plus untracked
  `HandoffPacketValidator.swift`, `PacketFrontmatter.swift`, their two test files, and
  `research/2026-08-24-handoff-packet-frontmatter-schema.md`. Real code, uncommitted.
- Also untracked: `research/2026-08-24-laguna-revision-test-spec.md`, `claude_metrics.png`.

**ds4 main checkout** (`~/projects/ds4`, branch `paul/laguna`)

- **27 commits unpushed** relative to `origin/laguna-s2.1`.
- Untracked and unique to this disk: `research/2026-07-29-laguna-s-streaming-footprint.md`
  (see Cluster 4), `plans/2026-07-29-tblite-harvest-plan.md`, an entire untracked
  `docs/superpowers/specs/` directory, and `ds4-laguna-s-greedy-pi-extension.ts`.

**ds4 worktrees — none of these branches has an upstream; all exist only on this disk:**

| branch | state |
|---|---|
| `swiftstar-integration-mellum` | 4 commits, tip `cde6438`. Clean except an untracked `gguf` symlink. **This is the branch the submodule is meant to pin.** |
| `mellum-repair-pipeline` | 1 commit, `9e21c05`. Plus **another session's uncommitted Laguna work**: `pipeline/run_laguna.sh` and three `logs/laguna-revision-*` directories — a reuse of this session's pipeline for the Laguna revision test, not captured by `9e21c05`. |
| `laguna-s21-ssd` (worktree `laguna-xs2.1`) | modified `plans/mini-notes.md` — the source of several streaming measurements cited elsewhere. |
| `worktree-ds4f-mxfp4-bench` | 3 untracked benchmark CSVs. |
| `worktree-ds4-main-bench` | 1 untracked benchmark CSV. |
| `mellum-2.1`, `laguna-s-bench`, `context-firewall` | clean. |

**The two items most at risk of being lost**, both because they are untracked *and* on
never-pushed branches: the Laguna streaming-footprint note in the ds4 main checkout, and
the other session's Laguna revision logs inside `mellum-repair-pipeline`. Neither is
this session's to commit; both should be claimed by their owners before any `git clean`.

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

### B8. Late finding — Mellum's zero-initiation is prompt-shape dependent

**Added after Sections A–C were written. This contradicts a conclusion recorded in A1/A2
and should be resolved during consolidation, not read past.**

C1 records that for Laguna, "tool use is prompt-shape dependent, not a standing trait" —
it appeared only on the prompt carrying absolute filesystem paths. **The same test was
never run on Mellum.** It has now been run, on Q8_0, same harness, same `-n 8192`,
`DS4_AGENT_TOOL_NUDGE=2`, 180s cap, no code changes.

| Prompt shape | tool calls | files | nudges | pytest | wall |
|---|---:|---:|---:|---|---:|
| **Relative paths** (the original, and the basis for "0 tool calls") | **0** | **0/4** | 2 wasted | not-run | gave up, 7s |
| **Absolute paths only** — original prompt, verbatim, paths swapped | **6** | **4/4** | 2 used | self-test passed | 78s |
| Absolute + `ls -la` evidence + "none of these exist yet, create with your write tool" | **14** | **4/4** | **0** | self-test passed | hit 180s, still iterating |

**Path shape alone flips it.** The middle row changes exactly one thing against the run
that produced "0 tool calls" and goes to 4/4 files. So **"Mellum scored 0 tool calls on
both specs" is a property of those prompts, not of the model.**

**Concreteness buys grounding on top of initiation.** The two acting runs differ in
quality, not just count. The full-concreteness run needed **no nudge at all** and its test
asserts `"Come in. Sit down. Tell us about your human."` — verbatim from
`specs/mission.md:5` and `specs/roadmap.md:16`, so it demonstrably read the specs with
tools. The absolute-paths-only run invented its content: it asserts `"Welcome to
AgentClinic"` against route `/home`, neither of which is in the spec.

**Caveats, and they are large:**

- **n=1 per cell.** No replication.
- **Both "pytest passed" results are the model's own single-test suite, self-graded.** The
  abspath-only run passes a test asserting an invented string on a route the spec does not
  define. Per C2's grading finding, this carries little evidential weight; neither run was
  scored against a real acceptance suite.
- The full-concreteness run did **not** finish — SIGTERM at the 180s cap, mid-iteration.
- Q8_0 only. Q4_K not retested under the new prompt shape.
- The third row changes several variables at once; only the middle row is a clean ablation.

**One further observation, worth retesting rather than trusting:** in the
full-concreteness run Mellum entered a genuine write → `pytest` → diagnose → fix loop, and
its visible reasoning correctly identified a stray `</head>` inside a template block from
the failure output. That is revision under machine evidence, which is the capability A1
reports Mellum lacking (byte-identical re-emission under an `ImportError`). **These may
not be in conflict** — different bug class, different evidence shape — but "Mellum cannot
revise" should be re-run under this prompt shape before it is treated as settled.

**What this changes for the role assignment.** The pre-test position was that Mellum is
viable only as a decomposer or a harvested generator. The middle row reopens the
implementer role as *worth measuring* rather than ruled out. It does not establish that
Mellum passes AgentClinic — the grading here is too weak to claim that.

**Next, in order:** (1) re-run all three cells n=3 against the **real acceptance suite**,
not the model's own test; (2) re-run the L2 revision test under the absolute-path prompt
shape, since that is the finding most at risk; (3) if it holds, revisit the typed packet's
`workspace.paths: workspace-relative` rule, which currently makes an absolute path a
**hard error** — the one prompt shape now observed to trigger initiation in both Mellum
and Laguna is the shape the contract forbids.

Runs: `/tmp/agentclinic-runs/p1-q8-abspath/1` and `/tmp/agentclinic-runs/p1-q8-abspath-only/1`
(prompt, trace, stdout preserved under `.agentlogs/`).

---

## Section C — Laguna revision capability, the packet contract, and what "thinking" actually costs

**Session scope:** 2026-08-23 overnight → 2026-08-24 morning. Began as telemetry
archaeology on the Flash-vs-Laguna fleet decision, became an investigation of whether
Laguna can *revise* text under evidence, and ended by building and landing the typed
packet contract that the failures kept pointing at.

**This section owns the artifacts A8 and B7 flagged as orphaned.** The uncommitted
`HandoffPacket` feature set, `2026-08-24-laguna-revision-test-spec.md`,
`2026-08-24-handoff-packet-frontmatter-schema.md`, and the untracked
`pipeline/run_laguna.sh` + `logs/laguna-revision-*` directories in `mellum-repair-pipeline`
are all this session's. B7 correctly identified the packet code as the highest-value
unlanded work; it is still uncommitted at the time of writing, deliberately.

**Reviewed adversarially three times** by an independent model (Fable), which materially
changed the conclusions each time. Where a claim below is weaker than an earlier session
stated it, that is usually why.

### C1. Conclusions that still hold

**Laguna's revision capability — the gate question for a repair role**

- **Laguna Q2_K revises correctly under real machine evidence, where Mellum echoed.**
  Given a real unredacted pytest `ImportError` and a broken `app.py`, with no offending
  line called out and no fix stated, three runs at temp 0 each produced a minimal,
  correct, surgical fix (two import lines changed, all 3,877 bytes otherwise preserved),
  verified at **13/13 on the real acceptance suite**. This is precisely Mellum's round-4
  condition, which Mellum failed by re-emitting its entire file byte-for-byte. **The
  non-revision pathology is Mellum-specific, not general to small local models.**
- **Laguna Q2_K also fixed a `default_factory` bug byte-identically to the reference**
  (L3, fix stated in prose), as did Q4_K_M. Both 13/13.
- **Q2_K fits the 55 GiB target natively and Q4_K_M does not.** Measured from the engine's
  own planning line: Q2_K = 44.94 GiB resident + 4.65 GiB KV = **49.59 GiB planned** at
  ctx=100k; Q4_K_M = 63.56 + 4.65 = **68.21 GiB**. So the deployable configuration is
  Q2_K with no SSD streaming and none of its ~42–48% decode/prefill penalty — a
  materially better outcome than Q4_K_M + streaming, and it drops the S21 SSD port from
  the critical path for this workload.

**The fleet decision (Flash vs Laguna) — verified, but weaker than it was stated**

This session began as telemetry archaeology on an overnight "fleet" comparison that
concluded *Flash is the implementer*. Independent re-verification (Fable) confirmed the
numbers and then undercut the conclusion.

- **The measurements replicate.** Tool-call counts recomputed from raw `tool_request`
  events match the analysis doc exactly: Flash hard-spec pass = 10/6/8 tool calls, 7/4/6
  mutations, acceptance exit 0, 735s at tool budget 64; Flash at budget 30 = phase 3
  `budgetExceeded` after **35** tool calls (read×8, search×9, bash×8). Laguna Q4_K_M =
  99/122/62 think events, 14/8/2 tool calls. The **acceptance passes replicate too** — the
  file trees were reconstructed from `code.md` and the real suite re-run under the pinned
  grading env: Flash hard **13/13**, Q2+nothink hard **13/13**, Q4_K_M easy **13/13**,
  and the second "mystery" capture **13/13**. These are not transcript-trust.
- **The double-count bug was real and large.** One capture carries 220 `tool` transcript
  events against 24 `tool_request` execution events — a 9× inflation if counted naively.
  The fix (prefer the `tool_request` view in host-tools mode) is confirmed correct.
- **What the evidence actually supports:** *Flash with reasoning on terminates and acts,
  where Laguna with reasoning loops.* That is a real, wire-verified qualitative difference
  in failure mode — over-exploration is recoverable by raising a budget; non-convergent
  deliberation at Q2 was only fixable by amputating reasoning.
- **Two "mystery" captures resolved cross-session.**
  `20260823-235240-roadmap-user-story-mellum-decomposed` and
  `20260824-000212-roadmap-user-story` are **Section A's specialist-pipeline runs** —
  Laguna Q2_K (44.94 GiB resident) under `--nothink`, decomposed vs raw hard spec. Their
  absence from `/tmp` was because their logs live in the `mellum-repair-pipeline` worktree.

**"Host-controlled text mode" was never a mechanism** — the load-bearing correction

- **There is no tool-free path in the engine short of `--raw-prompt`.** Verified in
  `ds4_agent.c` in *both* builds: `-p --non-interactive` runs
  `agent_worker_reset_to_sysprompt`, which builds the full agent system prompt including
  `read`/`write`/`edit`/`bash`/`google_search`/`visit_page` schemas and tool-call
  tutorials. `-sys` only *appends*. `worker_run_raw_prompt` is the sole tool-free path and
  neither wrapper script used it.
- **So `repair.py`'s docstring ("plain text completion, no tool schema") is false, and the
  Mellum pipeline's "text mode removed tool-call initiation as a confound" is false as
  stated.** Mellum's outcomes are unaffected — all were pytest-verified — and its
  zero-initiation finding actually gets *stronger*: it had tools offered and still never
  used them. But the mechanism was Mellum's own pathology, not harness enforcement.
- **Laguna proved this by acting.** In the L1/L2 runs it emitted `edit`/`write` tool calls
  and executed a real `ls -la` mid-generation — confirmed genuine because the returned
  listing showed the actual scratch directory contents, file size and timestamp, which
  cannot be fabricated. `ds4-agent -p --non-interactive` is a full agent loop seeded by one
  prompt, not a completion API.
- **`--raw-prompt` is dead as a mechanism, for a reason beyond the obvious.**
  `worker_run_raw_prompt` never consults `think_mode`, and for GLM-syntax models thinking
  effort is injected as template system text that raw mode skips. It structurally cannot
  deliver *controlled* thinking, so adopting it would reintroduce `--nothink` through the
  back door — the one thing explicitly ruled out.
- **Tool use is prompt-shape dependent, not a standing trait.** Both L3 smokes (same quant,
  same wrapper, same schemas) emitted a single clean fenced block and zero tool calls. Tool
  use appeared only on the prompt carrying a traceback full of absolute filesystem paths.

**The packet contract — where the "model pathologies" actually lived**

- **Most of the typed contract already existed.** `HandoffPacket` already had
  `writableFiles`, per-file `baselines` (SHA-256 + line ending + mode, read from the
  worktree, never guessed), validation commands, and budgets; `PoolOrchestrator` already
  enforced `shellAllowed: false` plus a **vetted bash** refusing anything but the packet's
  own validation command. **The revision experiments bypassed all of it** by shelling
  directly to `ds4-agent` — which is why Laguna got unsandboxed bash and a bare `/tmp`.
  The environment guards were never missing; they were routed around.
- **Redaction must be checked on the *assembled* packet, not the authored one.**
  `taskText` grows after authoring — the agenttest harness concatenates `sharedContext`
  ([`main.swift:163`](../../../Sources/swiftstar-agenttest/main.swift)), and
  `DispatchPacketBuilder` appends digest + loaded files via `ContextAssembly`. The
  historical contamination lived in exactly that appended content, so a gate on the
  authored fragment would have missed the failure it exists for.
- **The gate immediately found real contamination in the shipped fixture.**
  `fixtures/agenttest/specs/roadmap.md` phase 2 states `default_factory` verbatim, so the
  near-miss bug is now *mechanically* disqualified as an L1/L2 cell rather than relying on
  someone reading the spec carefully.
- **Validation must run before the model loads.** First wiring put it inside the phase
  loop, i.e. after `PoolOrchestrator` spawns and loads 45–65 GiB — making the
  "costs microseconds" claim false. Moved to top level; the contaminated run now prints no
  `ds4:` line at all and exits 2.

**The thinking revision — what changed and why** (the design arc this session is pursuing)

The user's requirement is Laguna *thinking* at three points: decompose (user story →
scoped packet), implement, and repair. `--nothink` satisfies none of that, so the question
became how to get reliability without amputating reasoning. The reasoning, in order:

1. **The defect is termination, not reasoning.** Laguna's ~12 redrafts inside thinking
   were measured **byte-identical** across six files — deliberation changed nothing. It
   converges on content almost immediately and then fails to stop.
2. **So `-n` is the wrong bound.** It is a blunt timer: it fires mid-draft (`stop=limit`,
   no grade, in both Q4_K_M loop runs) and harvests nothing. **Convergence-based
   termination** — stop when draft N ≈ draft N−1 — gives the model all the thinking it
   wants and cuts exactly where thinking stops adding value.
3. **Thinking is not equally valuable per role.** Decompose is genuinely underdetermined
   and deserves it; implement demonstrably does not (byte-identical redrafts); repair is
   untested but needed no deliberation on canonical bugs. So the unit of configuration is
   the **role**, not the process — which is why `--nothink` as a global switch was the
   wrong abstraction rather than a wrong value.
4. **The typed packet is what makes bounded thinking safe.** Ambiguity converts directly
   into deliberation for this model, and pinning one fact merely relocates the
   deliberation to the next open sub-question. A packet that pins the *whole* contract
   removes the deliberation triggers, which is what lets the implementer run at `off` or
   `bounded` without forfeiting anything. **The packet work and the thinking work are the
   same work** — that is the load-bearing connection, and it is why this session built the
   contract before running the thinking experiment.
5. **A typed packet also makes decompose cheap to grade.** Schema-validating a packet costs
   microseconds; discovering the same defect by running an implementer costs a model load
   and three phases. That is what makes generous thinking affordable in the one role that
   needs it — failure is caught by a gate, not by a burned run.

**Framing that survived**

- **The defect is termination, not reasoning.** Laguna's think-loop drafts were previously
  measured byte-identical across ~12 redrafts of six files — deliberation contributed zero
  content. That reframes the lever from "less thinking" to "stop when content converges,"
  which is the only bound that preserves thinking.
- **Per-role sampling, not a global switch.** `--nothink` as a process-wide flag was the
  wrong abstraction; think mode belongs in the packet so decompose, implement, and repair
  can differ.
- **"Fleet" is not indicated.** The Mellum pipeline's own conclusion — specialization was
  shallow, roles differed only by prompt text and model binary, no Swift changes needed —
  argues for three sequential invocations with different bounding policies, not
  concurrency or per-role engine work.

### C2. Conclusions disproven or superseded — including several of this session's own

| Claim | Status |
|---|---|
| **"Laguna revises at L1"** | **Mislabeled; it is L2.** A pytest `ImportError` traceback quotes the offending source line verbatim, so for any import-time error L1 ≡ L2 by construction. The ladder's bottom two rungs collapse for that whole bug class. The result stands, the label does not. |
| **"temp 0 ⇒ deterministic, so n=3 tells us nothing n=1 wouldn't"** | **False.** The three runs took *different trajectories* (run 1: edit→write; runs 2–3: edit→`ls -la`→write) while converging on a byte-identical artifact. The engine is nondeterministic at temp 0 — plausibly Metal reductions or the speculative-argmax path. n=3 demonstrated artifact stability across nondeterministic paths. |
| **"3/3 mechanically extractable"** | **2/3 under the pipeline's real parser.** Run 3 hit the token cap and never closed its markdown fence; `repair.py`'s `parse_single_fence` requires a closed fence and would have returned nothing. It was "extractable" only via a lenient regex written after the fact. |
| **"The near-miss `default_factory` bug is a valid L1 cell"** | **Contaminated.** Its fix appears verbatim in `pipeline/spec_context.md:54` *and* in `roadmap.md`. Caught by manual read, now caught mechanically. **There is currently no valid L1 bug in the design.** |
| **"Laguna always reaches for tools when offered"** | **Falsified by this session's own L3 smokes** — zero tool calls, same quant, same wrapper, same schemas. |
| **"`--nothink` is a Q2-specific crutch to be eliminated"** | **Too strong.** For the *implementer* the evidence says thinking adds nothing (byte-identical redrafts; Q2+nothink is the best-replicated pass in the corpus, 3–4 runs). The defensible position is per-role: `off` for implement, `on` for decompose (underdetermined, and failure is cheap once packets are schema-checked), `bounded` for repair. |
| **"Validating the packet costs microseconds"** (as first wired) | **False as written** — it ran after the model load. True now. |
| **"The `sampling` field gives per-role thinking"** | **Not yet.** `--nothink`/`-n` are built into worker argv from `AgentSettings` at spawn ([`AgentCommand.swift:64`](../../../Sources/SwiftStarKit/AgentCommand.swift)). The packet field is **descriptive only** — it records the run's config, it does not control it. |
| **"The quantization hypothesis is confirmed"** (prior doc, `laguna-hard-analysis.md:147`) | **Contradicted by that same document's later runs.** Written on one Q4_K_M pass; the next two Q4_K_M hard runs think-looped to `limit`. Honest form: Q4_K_M changed the acting rate from ~0/4 to ~1/3. n=3 is not confirmation. The bolded claim should be retracted in place. |
| **"Laguna S Q4 hard: 1/3 acts, 2/3 think-loops"** as a clean binary | **Messier.** One of the two "think-looped" runs made 17 tool calls including 6 writes in a segment that never got a turn-end `ready`. |
| **"Flash is the implementer" (fleet conclusion)** | **A hypothesis wearing a conclusion's clothes.** It is n=1 at a tool budget chosen *after* watching n=1 fail. Both models needed exactly one accommodation each — Flash budget 64, Laguna `--nothink` + `-n` — so "Flash passes without the crutch" is slanted framing. Flash's budget-30 run also produced 3,485 think events and a silent mid-run context compaction (ctx 15468→9100), so it is not categorically free of the resource-exhaustion family either. |
| "Flash is better because low quant breaks judgment" | **Not a general law.** Flash is itself a q2-q4 mixed-quant artifact. The claim is Laguna-specific. |
| The fleet comparison as a complete decision | **Ignores the cost axis.** 91 GiB Flash vs ~48 GiB Laguna-Q2, the latter of which passed the same hard spec 3–4 times. No results table carries a memory or spec-version column. |
| "Before: 0/3 → after: pass" as a clean before/after | **Confounded by spec drift.** Commits `9abc310` (20:55) and `e00ec58` (21:17) pinned data-model and `.card` contracts *into the hard spec* mid-experiment, so no post-21:17 result is comparable to the 0/3 baseline. The one control that exists — run `20260823-205557`, Q2_K + think + pinned spec + `-n` cap — **still looped** (2,087 think events, 0 tool calls), n=1 evidence that pinning alone does not rescue Q2. |
| `generated` token counts as a cross-model cost comparison | **Apples-to-oranges.** The value at `ready` is round-scoped, not turn-scoped, in multi-round host-tools runs. The telemetry review fixed "turns" and ctx labeling but left this one. |
| Grader "DeepSeek good" as corroboration | **Carries no evidential weight.** The project's own verification record shows the grader returning "good" for 7/13 code. Acceptance exit codes are the only signal, and they are **not persisted in captures** — recoverable only because `code.md` is dumped. |

### C3. Open questions this session could not close

- **Does Laguna actually think, and does revision survive when it does?** *The gate
  question, still open.* All five revision runs showed **zero deliberation** in the raw
  output despite `--think` — the renderer strips only the `<think>` tags and passes the
  text through, so thinking would have been visible. The prompts were fully pinned, which
  is exactly the condition prior work found produces zero think events. **So every
  "revision works" result above is really "revision works with thinking off."** A batch
  testing this (Q2_K, hard spec, `AGENTTEST_THINK=1`, n=3, through the newly-wired
  sandboxed harness) was launched as this section was written. **It has since reported —
  see C9, which closes this question.**
- **Whether Laguna's think-loop and Mellum's byte-identical re-emission share a mechanism.**
  Both are "emits the same tokens again under new information," at different scopes.
  Unresolved, and A3 asks the same question from the Mellum side.
- **Whether a genuine L1 cell can be built for this fixture at all.** It needs a failure
  whose traceback does *not* quote the defect line (assertion-style), a spec redacted of
  the fix, and ideally a bug with a plausible *wrong* fix — nothing tested so far
  distinguishes "revises" from "recites a canonical fix."
- **Reproducibility of the grading environment.** Grading depends on a mutable out-of-repo
  uv project; an independent re-run under current PyPI versions flipped one previously-13/13
  result to 10/13 (legacy `TemplateResponse` signature under newer Starlette/Jinja2).
  Recorded results are correct *today* only.

### C4. Files written or changed by this session

**swiftstar — `p11-subagent-pool`, all uncommitted at time of writing**

- [`docs/superpowers/research/2026-08-24-laguna-revision-test-spec.md`](2026-08-24-laguna-revision-test-spec.md)
  — the L1/L2/L3 hand-holding ladder, four named outcomes fixed in advance, and the
  sequencing note that Q2_K is the *target* (55 GiB, native) tested second only because it
  carries a confound, not because it is lower priority.
- [`docs/superpowers/research/2026-08-24-handoff-packet-frontmatter-schema.md`](2026-08-24-handoff-packet-frontmatter-schema.md)
  — schema v1. B7 saw this as "draft"; it is now **implemented**, with an honest
  implemented/not-implemented rule list and a documented statement of what the redaction
  gate *cannot* do.
- `Sources/SwiftStarKit/HandoffPacket.swift` — **modified.** Adds `facts`, `redacts`,
  `role` (`PacketRole`), `sampling` (`SamplingPolicy`/`ThinkMode`), plus a hand-written
  `init(from:)`. **That decoder is not optional:** synthesized `Codable` throws on missing
  keys, so adding fields silently broke decoding of every persisted dispatch. A test pins it.
- `Sources/SwiftStarKit/HandoffPacketValidator.swift` — **new.** Redaction across five
  channels (task, facts, both commands, writable paths), absolute-path and `..`-traversal
  rejection, budget and empty-field rules.
- `Sources/SwiftStarKit/PacketFrontmatter.swift` — **new.** Hand-rolled parser, no
  dependency. Throws on unrecognized `role`/`think` or non-numeric budgets rather than
  defaulting.
- `Sources/SwiftStarKit/PhasePacketBuilder.swift` — **new.** Phase assembly extracted from
  the harness so the assembly order is testable and so the validated packet is provably the
  dispatched one.
- `Sources/swiftstar-agenttest/main.swift` — **modified.** Builds packets through
  `PhasePacketBuilder`, validates every phase **before** the orchestrator constructs,
  records sampling on the packet, and reads withheld strings from `AGENTTEST_REDACT`.
- `Tests/SwiftStarKitTests/{HandoffPacketValidatorTests,PacketFrontmatterTests,PhasePacketBuilderTests}.swift`
  — **new.** 376 tests green overall.

**ds4 — `mellum-repair-pipeline`, untracked (the logs B7 flagged)**

- `pipeline/run_laguna.sh` — fork of `run_mellum.sh` with thinking on. Note the fork fixed
  a latent **bash 3.2** bug present in the original: `"${ARR[@]}"` on an empty array under
  `set -u` aborts on macOS's default `/bin/bash`.
- `pipeline/logs/laguna-revision-l3-nearmiss/` (Q4_K_M), `-l3-nearmiss-q2/` (Q2_K),
  `-l1-redirect-q2/` (Q2_K, n=3) — prompts, raw and stripped outputs for every run above.

### C5. What this session thinks comes next

**In flight**

1. **The think-on batch** — Q2_K, hard spec, `AGENTTEST_THINK=1`, n=3, through the
   sandboxed pooled harness. Measures **think events from the wire**, not just pass/fail.
   Expected to reproduce the think-loop; that failure is the point, since it would be the
   first observation of the pathology inside a controlled harness with real telemetry, and
   is the evidence needed to justify convergence-based termination.

**Then, branching on that result**

2. **If it loops → convergence-based termination in the engine.** Stop when draft N ≈
   draft N−1. This is the only bound that gives thinking *and* reliability; `-n` is a blunt
   timer that cuts mid-draft and harvests nothing (both prior `stop=limit` runs produced no
   grade).
3. **If it holds → wire `sampling` to actually control behavior.** Requires per-phase
   respawn since argv is fixed at spawn; the reload cost looks tolerable (residency 4907 ms
   cold, **295 ms warm** in observed logs), so this is plumbing rather than an engine change.
4. **Then the three-role pipeline**: three sequential invocations, per-role bounding
   policy, deterministic gate between them. Not concurrency.

**Independent of that branch**

5. **Build a genuine L1 cell** — redacted spec variant plus an assertion-style bug whose
   traceback does not quote the defect line, and one bug with a plausible wrong fix. The
   gate now makes contamination loud, which was the prerequisite.
6. **Persist acceptance evidence in captures** (pytest exit + tail) and **pin the grading
   environment** into the repo. Demote grader verdicts from results tables until the grader
   discriminates.
7. **Finish the validator rules** the doc lists as unimplemented: `packet` version,
   `workspace.paths`, `sampling.maxTokens > 0`, `validation.command` required. `packet: 99`
   is accepted today.
8. **Parser hardening** (all silent-mis-parse class, none yet fixed): trailing `# comment`
   retained in scalars; `command: |` block scalars yielding the string `"|"`; CRLF
   documents throwing a misleading `missingFrontmatter` because `.whitespaces` does not
   strip `\r` — plausible input in a repo that has a `LineEnding.crlf` case.
9. **Land the packet work.** B7 is right that it is the highest-value unlanded code in any
   tree.

### C6. Overlaps to resolve during consolidation

- **This section supersedes A6's request** for an authoritative account of the Laguna
  hard-spec result *only regarding revision and quant footprint*; the `--nothink` + pinned
  facts fix itself belongs to whichever session owns commits `914a84d` / `7bf00d9`, not
  this one.
- **A2's "Mellum has no in-context belief revision" and C1's "Laguna does revise" are the
  same experiment run on two models** and should be presented together during
  consolidation — the contrast is the finding, and it is the strongest evidence in the
  corpus for a model-selection decision on the repair role.
- **`laguna-hard-analysis.md` needs an in-place retraction** of "the quantization
  hypothesis is confirmed" (C2). Consolidation should not silently inherit it.
- **Cluster 5 in A7 lists the frontmatter schema as "designed but not built."** No longer
  true — it is built, tested, and wired. Cluster 5's framing ("nothing here is measured")
  still applies to the other two documents in it.
- **Three Fable reviews shaped this section** and are not written up as standalone
  documents. If consolidation wants the reasoning rather than the conclusions, it lives
  only in this session's transcript — a gap worth knowing about.
- **The revision-test spec's L1 rung is now known to be unreachable for import-class bugs.**
  Anyone reading that spec fresh will not know this without C2; either cross-link or amend
  the spec in place.

### C7. Tree state at the close of this session (delta from A8 / B7)

**Read A8 and B7 first — this is an update to them, not a third independent survey.**
Both were accurate when taken; this session then *added* to the uncommitted set rather
than landing any of it.

**swiftstar — `p11-subagent-pool`. Still no upstream; this repository has never been
pushed.** Twelve dirty paths:

| path | state | vs B7 |
|---|---|---|
| `Sources/SwiftStarKit/HandoffPacket.swift` | modified | also in B7 |
| `Sources/SwiftStarKit/HandoffPacketValidator.swift` | untracked | also in B7 |
| `Sources/SwiftStarKit/PacketFrontmatter.swift` | untracked | also in B7 |
| `Sources/SwiftStarKit/PhasePacketBuilder.swift` | untracked | **new since B7** |
| `Sources/swiftstar-agenttest/main.swift` | modified | **new since B7** — the harness wiring |
| `Tests/.../HandoffPacketValidatorTests.swift` | untracked | also in B7 |
| `Tests/.../PacketFrontmatterTests.swift` | untracked | also in B7 |
| `Tests/.../PhasePacketBuilderTests.swift` | untracked | **new since B7** |
| `research/2026-08-24-handoff-packet-frontmatter-schema.md` | untracked | in B7 as "draft"; now implemented |
| `research/2026-08-24-laguna-revision-test-spec.md` | untracked | also in B7 |
| `research/2026-08-24-overnight-consolidation.md` | **modified** | this section |
| `claude_metrics.png` | untracked | also in B7; **provenance still unknown — not this session's** |

The packet set is now a *larger* coherent feature than B7 assessed: schema + parser +
validator + builder + harness wiring + three test files, 376 tests green. B7's judgment
that it is the highest-value unlanded work still stands, more so.

**ds4 — `mellum-repair-pipeline`** (branch has no upstream, exists on one disk):
untracked `pipeline/run_laguna.sh`, `pipeline/logs/laguna-revision-l1-redirect-q2/`,
`-l3-nearmiss-q2/`, `-l3-nearmiss/`, and `scratch/`. **These are this session's** and are
the raw evidence behind every claim in C1. `scratch/` is generated workspaces and is
disposable; the rest is not.

**Not surveyed here:** the `paul/laguna` tblite material and the bench-worktree CSVs. B7
covers them and this session did not touch them.

### C8. Research files this session touched, for the consolidation pass

*Written by this session* (all untracked, all in `docs/superpowers/research/`):
`2026-08-24-laguna-revision-test-spec.md`, `2026-08-24-handoff-packet-frontmatter-schema.md`,
and Section C of this document.

*Depended on and now partly stale* — these are the ones a consolidator must reconcile,
and all sit in A7's **Cluster 1**, already named the highest-value merge target:

| file | what this session changed about its standing |
|---|---|
| `2026-08-23-p11-agenttest-laguna-hard-analysis.md` | **Needs an in-place retraction** of "the quantization hypothesis is confirmed" (C2). Its Flash section and its own later runs already contradict it. Also carries the un-asterisked before/after table confounded by spec drift. |
| `2026-08-23-p11-agenttest-telemetry-review.md` | Still sound, and its double-count fix independently re-verified here. One gap it did not close: `generated` is round-scoped (C2). |
| `2026-08-23-p11-agenttest-verification-record.md` | Its finding that the grader returns "good" for 7/13 code is the reason grader verdicts should be demoted corpus-wide. Underused. |
| `2026-08-23-p11-agenttest-mellum-verification-record.md` | Unaffected, and the most rigorous document of the set. Pairs with C1's Laguna result — see C6. |
| `2026-08-24-mellum-specialist-pipeline.md` (ds4 worktree) | Its "host-controlled text mode" framing is **mechanically false** (C1); outcomes unaffected. Needs a footnote, not a retraction. |
| `2026-08-24-laguna-revision-test-spec.md` | Its L1 rung is unreachable for import-class bugs (C2). Amend in place or cross-link. |

### C9. The think-on batch result — the gate question, answered

**Laguna Q2_K with thinking on does not act. 0/3.** Reproduced cleanly inside the
sandboxed harness with wire telemetry, the first controlled observation of the pathology.

| run | think events | tool calls | text | generated | ctx_used | capture |
|---|---:|---:|---:|---:|---:|---|
| 1 | 1,480 | 0 | 0 | 8,192 (cap) | 10,081 | `20260824-100526-…-run1` |
| 2 | 1,827 | 0 | 0 | 8,192 (cap) | 10,081 | `20260824-100815-…-run2` |
| 3 | 2,016 | 0 | 0 | 8,192 (cap) | 10,081 | `20260824-101146-…-run3` |

All three hit the `-n 8192` cap in ~2–4 minutes with **zero output**, stopping at
ctx 10,081 of 32,768 — so `-n` converted the old context-death failure into a bounded
one. Every run stopped at phase 1 with `receipt noChanges (limit)`; phases 2 and 3
never ran.

**The failure is a transition failure, not a convergence failure — this corrects C1.**
The think stream holds a *complete file set*: 27 fenced blocks in run 1, two full drafts.
`base.html` is **byte-identical** between drafts (898 B both) while `models.py` differs by
2 bytes, so content does converge. The pathology is visible verbatim in the tail:

> *"OK, let me write all the files now. I'm confident in my plan. One last thing: I need
> to make sure the `app.py` file doesn't have any syntax errors. Let me review it:"*

It announces readiness to act, then defers to one more review, indefinitely. So the
earlier "byte-identical redraft" framing and this are the same trajectory seen at
different budgets — and **convergence detection alone is the wrong lever**: stopping
yields nothing. The useful action is to *harvest what converged and write it*.

**Harvest works, and is not yet mechanically reliable.** Extracting run 1's second draft
and running the real acceptance suite gives **5/13 — exactly the phase-1 tests, all of
them, with all 8 failures in phases 2–3.** The model did its assigned phase completely and
correctly and never emitted a tool call. That is direct evidence for the harvest lever
Section A proposed as its untested next step, pointed at Laguna instead of Mellum.

**But the labeling convention is unstable, which is the blocking detail.** Harvest depends
on pairing each fenced block with a filename. Run 1 emitted **12** `### \`path\`` headings;
runs 2 and 3 emitted **zero**. Consequently a mechanical harvester recovers run 1 correctly
but misassigns runs 2–3 (`app.py` receives `models.py`'s body in run 2; `models.py`
receives HTML in run 3). **Mechanical harvest therefore needs the label format pinned as a
packet directive** — the same "pin the contract" lever that already works, and cheap to
add.

`ThinkHarvest` ([`Sources/SwiftStarKit/ThinkHarvest.swift`](../../../Sources/SwiftStarKit/ThinkHarvest.swift),
new, TDD, 6 tests) implements the rules that survived: closed fences only (an unterminated
trailing block is the cap cutting mid-draft, and writing it would overwrite a good earlier
draft), allowlist-bounded so harvest can never widen the packet's grant, and last-draft-wins.
One bug in it was **found by running it against real captures**: `app.py` matches as a
substring inside `tests/test_app.py` at a later index, so a plain substring search handed
the test file's body to `app.py`. Fixed with a boundary check and pinned by a regression
test named for the capture that found it.

**Revised next step, replacing C5's item 2.** Not "convergence-based termination" but:
(1) pin the block-label format in the packet, (2) harvest on a `noChanges` outcome and
write the harvested files into the worktree so the phase chain continues, (3) rerun the
batch and see whether the full 13/13 falls out of thinking that never became action.
Phases 2–3 have never executed under thinking, so that remains genuinely unmeasured.

### C10. Second Fable review of C9 — the mechanism, and three overclaims corrected

Reviewed adversarially again before acting on C9's plan. This review changed the plan
materially, not just the framing.

**The mechanism: `--nothink` and `.bounded` are the same lever at different times, and
Laguna Q2_K is stuck on the un-implemented one.** Traced in the engine source
(`ds4.c:37471-37480`, `ds4_chat_append_assistant_prefix`): when thinking is enabled the
engine pushes `think_start_id` as the assistant-turn prefix; when disabled it pushes
`think_end_id` directly. **`--nothink` does not disable reasoning — it pre-emits `</think>`
so the turn starts already in the act channel.** With thinking on, the model must itself
emit the single token `</think>` to transition, and Laguna Q2_K never produces it under
this prompt. `HandoffPacket.ThinkMode.bounded` already declares "reasons under a token
ceiling" ([`HandoffPacket.swift:44-48`](../../../Sources/SwiftStarKit/HandoffPacket.swift))
— nothing implements it. `packet.sampling` is consumed by no orchestrator code (write-only,
confirmed by grep); `AgentCommand.argv` maps think to only `--nothink` or engine default;
the engine itself has only NONE/HIGH/MAX (`ds4.h:26-28`), no ceiling. **The fix is a forced
`</think>` injection at a token budget** — the standard thinking-budget technique, and a
small patch to an engine this project already patches. It preserves thinking at all three
pipeline points and produces *committed* tool calls rather than scraped drafts.

**Control confirmed: think-then-act already works on this exact harness, for another
model.** `captures/agenttest/20260824-071332-roadmap-user-story` (Flash, budget-30 run)
carries **4,353 think events *and* 63 `tool_request`s** through the identical pooled
`--host-tools` path and identical packet text. That isolates C9's failure to Laguna's
inability to self-emit the transition token — not tools, not prompt, not wire.

**Three corrections to C9:**

1. **"Defers indefinitely" outran the evidence.** All three runs end mid-sentence at the
   `-n 8192` cap. Supported: "defers past 8,192 tokens through two full draft-review
   cycles." Not supported: indefinitely. One phase-1 run at a higher cap settles it — see
   C11.
2. **Harvest is a fallback, not a destination, and structurally cannot serve repair.** The
   model never sees the pytest output it would need to react to inside a harvested draft,
   so harvest cannot satisfy think-at-repair — a third of the actual requirement. 5/13 was
   n=1, best-case, hand-extracted; mechanical harvest recovers only 1 of 3 runs (C9's own
   finding). Harvested results must stay labeled as such: they measure drafting quality,
   not agency.
3. **`ThinkHarvest` has two more bugs of the class already fixed, found by independent
   reimplementation against the real captures, not by unit tests:**
   - `isWholePath` ([`ThinkHarvest.swift:74`](../../../Sources/SwiftStarKit/ThinkHarvest.swift))
     checks only the *preceding* character. `models.py` matches inside `models.pyc`;
     `app.py` inside `app.py.bak` — the mirror image of the `test_app.py` bug already fixed.
   - The fence regex `[a-zA-Z]*` rejects digit-bearing language tags (`jinja2`, `html5`);
     an unmatched opener flips fence parity and turns prose into a "file body." Not
     triggered in these three runs, but the label format is exactly what is not yet pinned.
   - **It is last-*block*-wins, not last-*draft*-wins**, and this already bit: reimplementing
     the exact rules against the real captures reproduces both C9 misassignments precisely,
     and shows why — the re-review tail is dominated by *snippet* fences (a single import, a
     single test function) that carry a granted filename in their preceding window. In run 1
     a 30-byte `from models import complaints` block gets assigned to `app.py`; only a later
     full second draft rescues it. Since compulsive re-review is this model's own pathology,
     tail snippets will systematically overwrite good drafts as harvest scales. Fix once
     labels are pinned: match **only** explicitly-labeled blocks, fail closed (unlabeled →
     no file, never the wrong file), and validate the harvested tree with the packet's own
     vetted commands before treating it as a result.

**One comment in the codebase is now known false.** [`main.swift:105`](../../../Sources/swiftstar-agenttest/main.swift)
claims the packet's sampling makes captures self-describing; the packet is never written
to `captureDir`. Working from artifacts alone, distinguishing the Laguna batch from the
same-morning Flash runs required opening `wire.ndjson` and reading memory-plan lines.
Ten-line fix (write `packet.json` into the capture dir); not yet done.

**Revised order, replacing C9's "revised next step":**

1. One phase-1 run at a higher token cap — zero code beyond an env var, settles the
   "indefinitely" question. **Run as this section was written; see C11.**
2. Implement `.bounded` as forced `</think>` injection in the engine.
3. Keep harvest as the `noChanges` fallback only, with label-only matching and a
   vetted-command validation gate — not the primary lever.
4. Make captures self-describing.

Phases 2–3 under thinking remain unmeasured under any of the above; the forced-transition
path is the one that reaches them without laundering a result through harvest.

### C10.5 — resolved: `<think>` reopens after `</think>`, unrestricted, confirmed in source and on the wire

The open question C11 left unresolved is answered.

**Structurally: nothing gates it.** Searched the full engine for any logit ban, grammar
constraint, or sampling restriction tied to `think_start_id`. There is none —
`ds4_chat_append_assistant_prefix` ([`ds4.c:37471`](../../../external/ds4/ds4.c)) decides
only the turn's *opening* token; nothing afterward stops the model sampling `<think>`
again. The `in_think` flag that does exist ([`ds4_agent.c:4558-4570`](../../../external/ds4/ds4_agent.c))
is purely reactive — it toggles rendering/parsing based on tags the model already emitted,
not a constraint on what it can emit next.

**Empirically: it happened, in the `-n 20000` run, unforced.** At wire line 1588 two tool
calls finished and their results were fed back. The model's very next generated bytes
([`captures/agenttest/20260824-110645-roadmap-user-story/wire.ndjson:1589-1593`](../../../captures/agenttest/20260824-110645-roadmap-user-story/wire.ndjson))
are classified `think` by the renderer's literal `bytes_has_prefix(cur, rem, think_open)`
check — the model re-emitted the actual `<think>` tag, immediately, unprompted, right
after seeing real tool output. It didn't drift back gradually; it walked straight back in.

**Scope of the fix: a standing per-turn ban, not a one-time prefix decision.**

- **Location, confirmed by reading the loop.** `worker_run_turn`
  ([`ds4_agent.c:13108`](../../../external/ds4/ds4_agent.c)) contains *both* the tool-call
  round-trip (`for (int tool_round = 0; ; tool_round++)`, ~line 13163) and the per-token
  sampling loop (`while (generated < max_tokens...)`, ~line 13296) in the same C function,
  same stack frame — the code's own comment documents this design ("after a DSML stanza
  completes we terminate that assistant message, append the tool result as a tool message,
  then ask the model to continue"). **A ban flag can therefore be an ordinary function-local
  variable**, declared once above the `tool_round` loop: it survives every tool round-trip
  within a turn for free, and resets naturally on the next call (next turn). No promotion
  to the `agent_worker` struct is needed — the earlier hedge that this might require
  cross-call persistence was wrong; the loop structure rules it out.
- **The mechanism.** `ds4_session_sample` ([`ds4.c:63262`](../../../external/ds4/ds4.c))
  reads logits straight from `s->logits`, which the caller already has direct access to.
  Immediately after each `int token = ds4_session_sample(...)` call in the sampling loop,
  add `if (token == vocab->think_end_id) think_closed = true;` (symmetric with the existing
  `ds4_token_is_stop` check one line below it). Immediately *before* each sampling call,
  when `think_closed` is true, set `w->session->logits[vocab->think_start_id] = -INFINITY`.
  There are two sampling call sites inside `worker_run_turn`'s scope pattern (the plain path
  and the speculative-argmax path); both need the mask, or the wrapper `worker_sample_with_mode`
  ([`ds4_agent.c:13020`](../../../external/ds4/ds4_agent.c)) — which already demonstrates the
  precedent of conditionally altering sampling behavior from loop state, for the DSML
  greedy-sampling case — is the natural place to centralize it.
- **Composing with `.bounded` / forced injection.** `HandoffPacket.ThinkMode.bounded`
  ([`HandoffPacket.swift:44-48`](../../../Sources/SwiftStarKit/HandoffPacket.swift)) needs
  forced `</think>` injection at a token budget (C10's original proposal) *and* this standing
  ban firing at the same moment the injection fires — otherwise forced injection reproduces
  exactly the `-n 20000` run's outcome (act briefly, walk back in, cap with nothing written).
  The two are one change, not two: whatever sets `think_closed = true` — the model's own
  `think_end_id` token, or a host-forced injection at the budget boundary — is the single
  event the mask keys on.
- **Config plumbing needed.** `effective_think_mode` ([`ds4_agent.c:1022`](../../../external/ds4/ds4_agent.c))
  and `ds4_think_mode` ([`ds4.h:26-28`](../../../external/ds4/ds4.h), currently
  `NONE`/`HIGH`/`MAX`) have no ceiling concept. A `.bounded` mode needs a token-count field
  carried from `HandoffPacket.sampling.maxTokens` through `AgentSettings` → `AgentCommand.argv`
  → `agent_config` → `worker_run_turn`'s budget check, alongside the existing `max_tokens`
  the loop already tracks (so the boundary trigger is "budget reached," not a second
  independent counter).
- **One thing not yet checked:** whether `<think>` is tokenized as a single vocab id in
  every code path that matters, or whether the model could in principle spell the tag out
  via separate BPE pieces (`<`, `think`, `>`) that bypass a single-token logit mask. The
  `vocab_lookup(vocab, "<think>")` calls throughout `ds4.c` (37035, 37063, 37084) treat it
  as one id, which is the normal case for a special/control token, but this should be
  confirmed against Laguna's actual tokenizer before relying on the mask being unconditionally
  effective.
- **Verification plan.** Rerun the `-n 20000`-shape batch with the ban active. Success is
  either a completed write within budget, or a `budgetExceeded` that traces to genuine tool
  exploration (Flash's documented over-exploration pattern, already observed once Laguna
  acts at all) — not to renewed thinking. Both are progress; the second still needs the tool
  budget tuned per C1's Flash precedent, not a new failure to diagnose.

### C10.6 — second review corrects the reopening mechanism; C10.5's fix design is superseded

**Directionally right that bounded thinking is the next lever. Wrong about the mechanism,
and the "standing sampled-token ban" in C10.5 cannot work as designed.** Independently
verified against source below — every point held up.

**The reopening is host-forced, not model-sampled — this overturns C10.5's "empirical
proof."** `ds4_chat_append_assistant_prefix` is called unconditionally at the top of
*every* `tool_round` iteration ([`ds4_agent.c:13184-13185`](../../../external/ds4/ds4_agent.c)),
same function and same `think_mode` as true turn start. The renderer struct is rebuilt
fresh each round with `.in_think = ds4_think_mode_enabled(think_mode)`
([13252-13260](../../../external/ds4/ds4_agent.c)) — seeded `true` *before the model
generates anything*. So the `think` event C10.5 read as the model "walking back in" after
tool results is the **host re-inserting a `<think>` prefix into the prompt at the start of
every round**, prefilled ahead of sampling. It never passes through `ds4_session_sample`.
**A sampled-token logit mask — C10.5's entire proposed mechanism — cannot prevent a token
injected during prompt construction.** The fix has to change the prefix policy itself, not
the sampler.

**The budget is per-round, not per-turn — this corrects C11 too.** `int generated = 0;`
and `int max_tokens = cfg->gen.n_predict;` are both declared *inside* the `tool_round` loop
body ([`ds4_agent.c:~13239-13270`](../../../external/ds4/ds4_agent.c)), reset every round.
So `AGENTTEST_MAX_TOKENS=20000` was never a turn-total budget: round 0 spent ~2,037 tokens
(thinking + brief exploration, ending naturally at the tool calls) and completed; round 1
then received its *own fresh* 20,000-token allowance and spent all of it on forced-then-
unescaped thinking. C11's "hit the 20,000 token cap" should read as **round 1 alone burning
a full independent 20,000-token budget**, not a turn-wide total — true tokens generated
across the run were closer to 22,000.

**A second bypass, lower priority but real.** `speculative_argmax` mode
(`ds4_session_eval_speculative_argmax` → `ds4_session_eval_dflash_speculative_argmax` for
Laguna, [`ds4.c:68910`](../../../external/ds4/ds4.c)) can emit multiple draft tokens in one
batch, outside the single-token `ds4_session_sample` call a mask would gate. Any fix must
also cover this path or disable speculative decoding once a forced-closed state is active.

**Corrected design.** Each `tool_round` legitimately *may* still open with `<think>` — that
preserves reasoning over freshly-returned tool output, which is exactly what the repair role
needs and what C1's Flash control shows already works (4,353 think events across many
rounds, alongside 63 real `tool_request`s). The fix is not to forbid the reopen; it is to
give thinking its **own smaller ceiling, separate from the round's total generation budget**:

1. Track tokens generated while `in_think` is true, *within the current round*, against a
   ceiling smaller than `max_tokens` (the round's existing total cap, kept as-is for action).
2. When that smaller ceiling is hit, **force `</think>` mid-stream** — override the next
   sampled token with `think_end_id` directly rather than letting the model choose it. This
   is a different mechanism than prefix injection: it happens inside the per-token loop, at
   the point the ceiling triggers, not at round start.
3. **C10.5's standing ban is still correct, but only for this narrower scope**: after a
   mid-round forced closure, mask `think_start_id` in `ds4_session_sample` for the
   *remainder of that round* — this is the one place a sampled-token ban is architecturally
   valid, since resampling `<think>` after a mid-round forced close genuinely would go
   through the sampler. It does not apply across rounds, where the reopen is legitimate and
   prefix-governed, not sampler-governed.
4. Cover the speculative-decoding path — either extend the ceiling check to run per
   accepted draft token, or force `speculative_argmax` off once a round's thinking has been
   force-closed.

No files changed for this correction (review-only). C10.5's `worker_run_turn`
loop-structure finding (tool rounds and token sampling share one stack frame, so per-round
state can be an ordinary local variable) still holds and is reused here — only the trigger
condition and the injection mechanism change.

**Light-reviewed (Fable) — sound, no blockers, one real gap folded in.**

- **Step 2 is not new mechanism, it's reuse.** The edit-old auto-`[upto]` forcer
  ([`ds4_agent.c:13318-13328`](../../../external/ds4/ds4_agent.c)) already samples a token,
  discards it, and substitutes forced text via `worker_force_generated_text` →
  `worker_accept_generated_token` ([12944](../../../external/ds4/ds4_agent.c)) — transcript,
  renderer, and KV eval all handled consistently. `ds4_session_sample` is pure (no side
  effects beyond the RNG), so discard-and-substitute is safe. The forced `</think>` should
  be a single `worker_accept_generated_token(w, think_end_id, ...)` call through this
  existing path, not new machinery.
- **Real gap: speculative decoding must be covered for the *counting*, not just the
  post-close mask.** `can_speculate` checks only `!stream.dsml_active` — no `in_think`
  condition — so in a greedy run most think tokens arrive in batches of up to 17
  ([`ds4_agent.c:13337-13380`](../../../external/ds4/ds4_agent.c)), and a ceiling check that
  only runs once per loop iteration would badly undercount. The per-draft `toks[]` scan
  already exists for stop-token detection; the think-ceiling check needs to run in the same
  place, not just gate speculation after force-close (step 4 as written only covered the
  after case).
- **Confirmed, not assumed:** think tokens are not stop tokens when thinking is enabled
  (`ds4_token_is_stop_for_think_mode`, [`ds4.c:37660`](../../../external/ds4/ds4.c)) — a
  sampled `<think>` genuinely flows through, so step 3's sampler-side ban is doing real
  work, not redundant with an existing stop check.
- **Flagged, correctly, as unverified rather than assumed:** forcing `</think>` does not
  force *action* — the model resumes from an abruptly truncated thought and could still
  ramble or hit EOS. Plausible given Flash's control run, but a thing to measure once built,
  not to assume.
- **Two minor implementation wrinkles:** `ds4_session_sample` has no mask parameter and
  `ds4_session` is opaque to `ds4_agent.c` — the ban needs either the existing
  `ds4_session_copy_logits`/`set_logits` pair (works, an extra vocab-sized copy per token) or
  a small new `ds4_session_ban_token` helper. And per-draft-token checking clearly beats
  disabling speculation on force-close: the latter sacrifices decode throughput exactly in
  the post-close action phase the fix exists to reach, and still doesn't solve the counting
  gap above — "a half-measure twice over."

### C11. The `-n 20000` run — "indefinitely" is wrong, but so is "just needs a bigger budget"

`AGENTTEST_MAX_TOKENS` added as a harness env var (`main.swift`, following the
`AGENTTEST_TOOL_BUDGET`/`AGENTTEST_THINK` convention) since `maxTokens` was hardcoded to
8192 in two places. One phase-1-only run, Laguna Q2_K, hard spec, `AGENTTEST_THINK=1`,
`AGENTTEST_MAX_TOKENS=20000`. Capture:
`captures/agenttest/20260824-110645-roadmap-user-story`.

**Result: `receipt noChanges`, generated exactly 20,000 (cap), ctx 27,888/32,768. Still no
files written.** But the wire is not a repeat of the three `-n 8192` runs — it is a
different and more informative shape.

**The model crossed `</think>` on its own, mid-run, with no forced injection.** At wire
line 949 (of 9,520) it emitted `text` announcing a plan ("I'll start by checking the
workspace structure... then write all files in one pass"), then four real `tool_request`
calls: `list /`, `list .`, `search` for `pyproject.toml`, `search` for `uv.lock`. This
falsifies C9/C10's "defers indefinitely, needs forced transition to ever act" as stated —
the model **can** self-emit the transition token.

**Then it reverted to thinking and never acted again.** Every event after wire line 1591
is a `think` event — all the way to the token cap. Of the run's 6,146 total think events,
the large majority came *after* the four tool calls, not before. So the shape is not
"stuck in thinking, then acts once given room" — it is **thinking → brief, shallow action
(exploration only, no writes) → thinking again → cap**. A bigger budget did not convert
deliberation into completed work; it bought one more round-trip through the same loop.

**This complicates C10's recommended fix.** Forced `</think>` injection at a token budget
would reliably produce the *first* transition — but this run shows the model can already
produce that transition unforced, and the harder problem is that it **retreats back into
`<think>`** after acting rather than continuing to completion. Whether the engine allows
`<think>` to reopen after a forced `</think>` in the same turn is unknown and matters: if
forcing the exit token once is not sticky, forced injection alone reproduces this run's
outcome, not a fix for it. **Open question for whoever picks this up: does one forced
`</think>` injection, or does it need to gate against re-entering `<think>` for the rest of
the turn?**

**Also unresolved: the four tool calls were exploration, not the writes the packet
requested.** This is Flash's documented over-exploration pattern (35 tool calls at budget
30 on the hard spec), now observed in Laguna too, once it does act — a second failure mode
sitting behind the transition failure, not a competing explanation for it.

### C12. `--think-budget` implemented in `ds4_agent.c`

The C10.6 design (light-reviewed, no blockers) is now real code, in the `external/ds4`
submodule (uncommitted, detached HEAD at `8784fe6`). Four files:

- **`ds4.h`/`ds4.c`**: two token accessors mirroring the existing `ds4_token_eos` pattern
  (`ds4_token_think_start`, `ds4_token_think_end`), and `ds4_session_ban_token(s, token)` —
  masks one token's logit to `DS4_NEG_INF`, same idiom as the existing (previously unused)
  `ds4_session_argmax_excluding`. Both additions are ~5 lines each, no changes to existing
  functions.
- **`ds4_agent.c`**: a new `--think-budget N` flag (0 = disabled, the default — matches
  existing behavior exactly when unset) threaded into `agent_generation_options`. Inside
  `worker_run_turn`'s per-round scope: three new locals
  (`think_tokens_this_round`/`think_forced_closed_this_round`/`round_in_think`, reset every
  `tool_round` — confirmed safe as ordinary locals per C10.5's loop-structure finding). A
  check at the top of the per-token `while` loop forces `</think>` via
  `worker_accept_generated_token(w, ds4_token_think_end(...), ...)` once the budget is hit —
  reusing the exact discard/accept path Fable identified in the edit-`[upto]` forcer, not new
  machinery. After a forced close, `ds4_session_ban_token` masks `think_start_id` before
  every subsequent sample this round, and `can_speculate` is additionally gated on
  `!think_forced_closed_this_round` so the ban can't be bypassed by a speculative batch
  (the accepted throughput tradeoff C10.6/Fable both flagged — post-close generation loses
  speculative decode for the rest of that round). Pre-close, the speculative batch's
  `toks[i]` loop is scanned for counting and start/end toggling (Fable's finding 2), so the
  ceiling isn't undercounted when most think-tokens arrive via speculation — overshoot is
  bounded to at most one batch (~16 tokens), matching what C10.6's review called acceptable.
- **`ds4_help.c`**: one-line help entry.

**Verified, not just written:**

- `make ds4_agent_test` (pure-logic unit suite, no GPU/model needed) — clean compile, all
  existing tests pass unchanged.
- `make ds4-agent` (the real binary swiftstar links against) — clean compile, zero warnings
  on any changed file.
- `./ds4-agent --help sampling` lists `--think-budget N` with the intended text.
- `make ds4_test` — completed, `ds4 tests: ok` (metal-tensor-equivalence, decode/prefill
  correctness, and the full suite all green; MTP/DSpark/SSD-streaming stages skipped, gated
  on env vars this run didn't set, not failures). B2's prior note that this binary aborts on
  a missing `ds4flash.gguf` was from a different environment/worktree; this one had what it
  needed, so that finding does not apply here — correcting the record rather than repeating
  a stale caveat.

**Not done — explicitly out of scope for this step, and the natural next one.** The flag is
implemented and default-off, but nothing calls it yet: `AgentSettings`/`AgentCommand.swift`
have no `thinkBudget` field, so the Swift harness cannot pass `--think-budget`, and
`HandoffPacket.sampling.maxTokens` still cannot reach the engine (the gap C10.5 already
named as "config plumbing needed"). **The mechanism has not been validated against the
actual Laguna pathology** (the `-n 20000` run's think→brief-explore→think-again→cap shape)
— that requires the Swift wiring plus a live rerun, which needs its own turn given the size
of what's already landed here.

---

## Section D — The merge pass: retire, consolidate, slot into the roadmap

**This is the pass Sections A/B/C were staged for.** A, B, and C are session
records — three parallel investigations that overlap, contradict each other in
places, and each carry their own live-looking direction list. Read as a set they
imply far more open work than actually exists. This section retires what is
dead, names the one document that becomes the source of truth, and sequences
what survives into roadmap actions.

**Rule applied throughout:** a direction is *retired* when its question is
answered (whatever the answer), *merged* when it survives only as part of a
larger settled finding, and *carried* when it is genuine open work. Retired does
not mean deleted — the evidence stays, the direction stops being live.

### D1. The single source of truth

**One new document replaces the live-findings role of eleven.**

`docs/superpowers/research/2026-08-24-local-model-agency.md` — *to be written as
the first roadmap action*, containing only what is settled and load-bearing:

1. **What each model can and cannot do**, as measured: Laguna's implement/repair
   competence and its thinking-transition failure; Mellum's zero tool-initiation
   and absent belief revision; Flash's terminate-and-act with over-exploration.
2. **The deployable configuration** — Q2_K, 49.59 GiB, nothink for
   implement/repair, native fit inside 55 GiB with no SSD dependency.
3. **The architecture doctrine** — host owns phase boundaries, budgets,
   permissions, validation, recovery; model supplies judgment and code.
   Deliberation happens once at decompose and is crystallized into packet facts,
   so implementers execute rather than re-derive.
4. **The measurement rules** that make any future number trustworthy (D3 below).

Everything else in Clusters 1–3 of A7 keeps its evidence value and stops being a
place to look for current truth. Each gets a one-line banner pointing here:
`> Superseded as a live finding by 2026-08-24-local-model-agency.md. Retained as
the evidence record for <what it uniquely holds>.`

**This consolidation document itself is retired on the same day it is merged.**
It is a staging area, not a reference; leaving it live recreates the problem it
exists to solve.

### D2. Retirement ledger

**Retired — question answered, stop working on it**

| direction | resolution |
|---|---|
| Quantization as the lever for Laguna agency | Same failure signature at Q2_K and Q4_K_M; only the odds move. ~70% established, and further quant hunting is poor value *now* — a matched Q4 control comes back only after steering is tested (C10.6/other-agent point 7). |
| Footprint / weight-size reduction (Section B's whole track) | Closed. Down stays Q8_0 (Q5_0 NaNs, MXFP4 ~5.5× KLD); no K-quant can reach a 896-wide contiguous dimension. Real memory ~10.3 GiB at 40k. |
| "Mellum passed the easy spec" / decomposer flips hard→pass | First is false; second is **untestable as run** (A2:110 — Laguna already passed the hard spec by then, so the result degraded to a cost measurement). Retired either way. |
| Convergence-based termination | Superseded before implementation — the model converges; termination was never the problem (C9). |
| `--raw-prompt` as a text-only mechanism | Structurally cannot deliver controlled thinking; never consults `think_mode` (C1). |
| Harvest-from-thinking as a primary lever | Demoted to `noChanges` fallback: cannot serve repair (model never sees the failure it must react to), and mechanical labeling is unreliable (C9). |
| "Host-controlled text mode" as an engine capability | It never existed; `-p` always injects tool schemas. The *principle* (host owns verification) survives and moves into the doctrine above. |
| SSD streaming as a Laguna-agency dependency | Q2_K fits natively. S21/XS21 port remains valuable for other models/contexts but is off this critical path. |

**Merged — survives only inside the source-of-truth document**

- Laguna revision capability (C1), the thinking-transition mechanism (C10.6),
  the Q2_K footprint numbers, Mellum's two hard limits, Flash's failure mode,
  and the `--nothink`-is-forced-transition insight. None of these needs its own
  live document.

**Carried — genuine open work, sequenced in D4**

- The three-role pipeline (decompose → implement → repair) with typed packets.
- Laguna decompose: never tested. The one untested link in an otherwise proven chain.
- `--think-budget`: built, unwired, never validated live.
- The `ds4.c:36895` admission contract — release-blocking silent-corruption bug,
  independent of everything else here.
- Q4_K expert-major prefill (0.21× penalty) — the only engine item a user feels.
- The subagent-pool cross-worker coalescing bug (already spun off).

### D3. Cross-cutting fixes that gate trust in any future measurement

These are cheap, and until they land every new number inherits the same doubts
this consolidation had to spend effort resolving.

1. **Stop citing grader verdicts.** The project's own record shows "good"
   returned for 7/13 code. Acceptance exit codes only.
2. **Persist acceptance evidence in the capture dir** (pytest exit + tail) — it
   is currently recoverable only because `code.md` happens to be dumped.
3. **Make captures self-describing** — write `packet.json` + run config into
   `captureDir`. A capture currently cannot tell you which model produced it.
4. **Pin the grading environment** into the repo. A dependency bump already
   flipped one 13/13 to 10/13.
5. **Tag every results table with a spec version.** "Hard spec" names at least
   three different documents across this corpus.

### D4. Roadmap slotting

Sequenced so each step's failure is cheap and informative.

**R1 — Land and consolidate (no model runs).** Commit both trees. Write the
source-of-truth document; banner the superseded ones; retire this document.
Apply D3's five measurement fixes. *Nothing below is trustworthy without R1.*

**R2 — Wire the packet contract into the real pipeline.** `thinkBudget` through
`AgentSettings`/`AgentCommand`; `HandoffPacket.sampling` actually driving worker
argv instead of being write-only. Small, mechanical, unblocks R3–R5.

**R3 — The proven pipeline, end to end.** Hand-authored packets → nothink
implement → nothink repair on pytest failure. Every component here is already
replicated; this is assembly and should mostly work. Success criterion: writes
and 13/13, not tool calls.

**R4 — Laguna decompose.** The untested link. Model-authored packet → schema
validation (microseconds, fails closed) → R3's proven chain. Failure is cheap
and diagnosable. If Laguna decomposes badly, branch: Mellum did this once, or
use a larger model for decompose only.

**R5 — Bounded thinking, where evidence demands it.** Validate `--think-budget`
live against the hard spec. Only now, and only for the roles R3/R4 show actually
need reasoning. Expect it to expose the *next* failure (shallow exploration, no
writes) rather than cure everything — the 20k run already showed transition
without productive action.

**R6 — Engine debt, independent of the above.** The admission contract
(release-blocking), then Q4_K prefill.

### D5. Mellum — explicitly parked, with re-entry criteria

**Parked, not abandoned.** Mellum has two measured hard limits — zero tool
initiation across both specs, and no in-context belief revision under
contradicting evidence (byte-identical re-emission shown its own error). Neither
is a tuning problem, and generic retry cannot fix fabricated validation.

**What stays live for Mellum regardless:** landing
`swiftstar-integration-mellum` (`cde6438`) and bumping the submodule pin — that
is the only step between here and Mellum being *loadable*, and it is worth doing
independent of whether Mellum is ever an agent.

**Re-entry criteria — return to Mellum investigation when any of these holds:**

1. The R3–R5 pipeline works with Laguna, and there is a *narrow, validated*
   packet role to test Mellum in — its failures are agency failures, not
   competence failures, so a sufficiently scoped role may be within reach.
2. The all-Mellum host-controlled build step is worth one run (Section A's own
   untested next step): Mellum's easy-spec failure was producing a complete,
   correct five-file solution as prose and never writing it. Cheap, and directly
   implied by the mode finding.
3. P12 needs a second variant for reasons other than agency (a "focused tasks"
   model rather than an autonomous coding agent — the framing A5 already
   recommends).

**Explicitly not a reason to return:** more quantization work on Mellum. That
track is closed by A2/B2.

### D6. Reconciliation with B8 — written after D1–D5, and it reorders them

**B8 landed after Sections C and D were written and falsifies a premise D5 rests
on.** Recording rather than quietly editing, per this document's convention.

**Mellum is no longer parked on the initiation finding.** D5 named "zero tool
initiation across both specs" as one of two measured hard limits. B8's middle
row is a clean one-variable ablation — relative deliverable paths swapped for
absolute, nothing else — and takes Mellum from 0 calls / 0-of-4 files to 6 calls
/ 4-of-4. That premise is gone. The second limit (no belief revision under
contradicting evidence) is *at risk but not falsified*: B8 observed Mellum
entering a genuine write → pytest → diagnose → fix loop and correctly
identifying a stray `</head>` from failure output. Different bug class and
different evidence shape than the byte-identical `ImportError` re-emission, so
these may not conflict — but "Mellum cannot revise" must be re-run under the
absolute-path prompt shape before being treated as settled.

**D5 is therefore superseded**: Mellum moves from "parked with re-entry
criteria" to **reopened, pending replication**. Its re-entry does not wait on
R3–R5. What has *not* changed: B8's own caveats are large (n=1 per cell,
self-graded single-test suites rather than the real acceptance suite, the
best run SIGTERM'd incomplete at 180s, Q8_0 only). B8 establishes that the
initiation finding was prompt-shaped; it does not establish that Mellum passes
AgentClinic.

**The confound is cross-cutting, and it reaches this session's headline result.**
The harness writable-note reads "All tool paths are relative to the workspace
root … never absolute paths"
([`main.swift:85`](../../../Sources/swiftstar-agenttest/main.swift)) — present in
**every** Laguna thinking-enabled run, including the 0/3 batch (C9) and the 20k
run (C11). That is precisely the prompt shape B8 shows suppresses initiation in
Mellum, and that C1 independently found correlated with initiation in Laguna
(tool use appeared only on the prompt carrying absolute paths in a traceback).

So **"Laguna Q2_K with thinking on does not act, 0/3" may be partly
prompt-shape, not purely the `</think>` transition mechanism.** The mechanism
finding still stands on its own evidence — the engine forces `<think>` per round
and the model must self-emit the closing token — but *why* it fails to emit may
be that the prompt gives it no concrete filesystem to believe in. These are
separable and both cheap to test. The 20k run is mild counter-evidence (it did
initiate, under relative paths) but produced exploration, not writes.

**The packet schema needs a distinction it currently lacks.** Validator rule 3
refuses absolute paths outright, and B8's point (3) reads that as conflicting
with the one shape now observed to trigger initiation in both models. On
inspection these are two different things and the fix is to separate them:

- **The grant** (`writableFiles`) stays workspace-relative. This is the security
  boundary the dispatcher revision-checks against; absolute entries there were
  never the initiation lever, and the 19:26 run's six refused writes are why the
  rule exists.
- **The presentation** (how deliverable paths appear in task text) is a separate
  concern the schema does not currently model, and is what B8 actually varied.
  A packet should be able to render its manifest as absolute paths for
  concreteness while still granting relative ones.

That is a small schema addition, not a retraction of rule 3 — but it must land
before any prompt-shape ablation, or the harness cannot express the treatment
arm.

**Reordering D4.** A prompt-shape ablation is now the cheapest high-information
experiment available and precedes bounded-thinking validation:

- **R2.5 (new, before R3)** — add path *presentation* to the packet schema,
  separate from the grant.
- **R3.5 (new)** — prompt-shape ablation, both models, against the **real
  acceptance suite** (B8's runs were self-graded, which C2 already established
  carries little weight): relative vs absolute presentation × thinking on/off,
  n=3. This is the single experiment that could most change the roadmap, because
  it bears on the 0/3 result, on Mellum's viability, and on whether
  `--think-budget` is solving a real problem or a prompt artifact.
- **R5 (bounded thinking) drops behind R3.5.** Validating `--think-budget`
  against a result that may be a prompt artifact would attribute a fix to the
  wrong cause.
