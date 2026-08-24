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
