# Mellum 2.1: a reproducible gap between tool-call protocol compliance and agentic follow-through

> **Superseded as a live finding** by [`2026-08-25-local-model-agency.md`](../2026-08-25-local-model-agency.md). Retained as the evidence record for the two-mode-split data, the three correction-mechanism tests, and the reproduced hallucinated-import repair failure.

**Status:** internal finding, drafted for possible sharing with the Mellum team ahead of an RL training pass. Not yet sent anywhere. All data below comes from two independent test environments running the same model.

## Summary

Mellum 2.1 (JetBrains, "Thinking" release, 12B-A2.5B MoE, 2.5B active parameters) reliably executes tool calls on narrow, single-step, bounded instructions, but on open-ended multi-step coding tasks it defaults to narrating a complete, plausible solution as plain chat text and never emits tool-call syntax at all — even when explicitly told mid-turn that it produced nothing and asked to continue. The gap is not a protocol, tokenizer, or engine-integration problem; those were identified and fixed first, and the underlying behavior survived every subsequent variable we changed.

## Setup

- **Model:** Mellum 2.1 Thinking. Tested at both Q8_0 and a mixed Q4_K/Q8_0 quant (Q4_K on expert gate/up for 21 of 28 layers) — identical behavior at both, so this is not a quantization artifact.
- **Sampling:** JetBrains' own published defaults (temperature 0.6, top_p 0.95, top_k 20), confirmed correctly wired in the engine.
- **Tool-call format:** Mellum's chat template specifies Hermes-style calls — `<tool_call>` tags wrapping JSON `{"name": ..., "arguments": ...}`. Confirmed correctly wired and matches what the model actually emits when it does call a tool.
- **Two independent execution paths**, tested separately, same result on both: a standalone single-session agent process, and a pool-orchestrated multi-worker path where a host process executes tool calls rather than the model's own process. Ruling out one path's plumbing as the cause.

Three integration bugs were found and fixed before any of the results below were collected, specifically to make sure a negative result wasn't just our own wiring: a missing per-model branch in tool-syntax selection (Mellum was silently falling through to a different model family's incompatible call format), missing system-prompt framing around the tool declarations, and missing Mellum-specific sampling defaults (was running at temperature 1.0 instead of the recommended 0.6). All three are fixed in the current build; the results below are with all three fixes in place.

## The two-mode split

| Task shape | n | Tool calls | Outcome |
|---|---:|---:|---|
| Forced single-tool canary ("read this file, report its first line") | 20 | 18/20 executed successfully | Protocol compliance is solid |
| Open-ended multi-file build, detailed imperative spec | 1 | 0 | Narrated a complete, plausible 5-file solution as chat text; nothing written |
| Open-ended multi-file build, high-level user-story spec | 1 | 0 | Stated an implementation plan, then stopped |
| Same detailed-spec task, separate test environment, no correction | 1 | 0 | 0 of 4 files |
| Same detailed-spec task, separate test environment, one prior success case with a corrective nudge (below) | 1 | 8 | 2 of 4 files — but the code doesn't run (a hallucinated import, `from fastapi import RedirectResponse`, which is not a real symbol) |

The canary task requires deciding to call *one* tool, once, on direct instruction. The build tasks require deciding, unprompted, across multiple steps, that tool calls are the right response at all. That's the axis the failure sits on — not call-syntax correctness, not tool availability, not task legibility (the detailed spec is unambiguous and the model's own prose response gets every fact in it right).

## Direct correction doesn't change the behavior

An engine-side mechanism exists specifically for this failure mode: after a turn that executes zero tools, inject one deterministic correction ("continue the original request...") through the tool-result channel and let the model respond. Tested twice, independently:

- **Test 1 (standalone path, no thinking-mode change):** before correction, 0 tool calls / 0 files / 1 round. After two corrections, 8 tool calls / 2 of 4 files / 10 rounds — the one case where correction produced *something*, though the output had a real bug and never ran.
- **Test 2 (pool-orchestrated path, this session):** correction fired twice as configured. The model responded both times by re-narrating content nearly identical to its first, uncorrected answer — same file list, same structure, no tool-call syntax at any point across 3 rounds and ~3,300 tokens of generation.
- **Test 3 (thinking-mode isolation):** same task, same correction mechanism, thinking explicitly disabled. Identical result — 0 tool calls, 0 files, both corrections exhausted, the model narrating the same "I cannot directly access files" reasoning with thinking off that it gives with thinking on. This rules out chain-of-thought token budget as the explanation.

The model was told, unambiguously, that it had produced nothing and should act — twice, in two different environments — and both times it produced more of the same kind of text rather than switching modes. That's a stronger signal than a bare failure count: it suggests the model doesn't hold "emit a tool call now" as an available response to being corrected on this class of task, rather than simply not noticing the correction.

## Concrete failure feedback does not produce self-correction either

The corrections above are generic ("your turn executed nothing, continue"). A separate, later experiment tested the narrower and more concrete case: give the model an actual failing test's output, the specific file, and one bounded instruction to fix it. To remove tool-call initiation as a confound entirely, this ran in **host-controlled text mode** — the host runs the test, selects the implicated file, hands the model the file plus the verbatim traceback, and the model returns a corrected file as plain text. The host then validates and writes it and re-runs the real test. The model is never asked to initiate anything; it only has to produce correct content.

Two bug classes, both host-verified against real `pytest` exit codes and real file diffs, never the model's own claim of success:

- **A realistic single-line bug** — a dataclass field using a shared mutable default where a `default_factory` is required. **Fixed successfully**, in the second of three allowed rounds, and the result was byte-identical to the reference solution. This is the first host-verified correct code change the model produced in this project, and it establishes that concrete-failure repair is a mode where it can work.
- **A catastrophic bug** — an emptied source file. **Failed within budget.** Without spec context the model echoed the broken file back unchanged. With spec context it produced a genuine rewrite, but introduced a hallucinated import: `from fastapi import RedirectResponse`, where the symbol actually lives in `fastapi.responses`. When re-run and **shown the exact `ImportError` naming that exact symbol, the model reproduced the identical wrong import.**

That last result is the sharpest signal in this document. It is not a tool-use failure, not a formatting failure, and not an ambiguity failure: the evidence was machine-generated, unambiguous, and named the precise symbol that was wrong. The model was asked only to emit corrected text, and it emitted the same incorrect text again. Notably, this is the same hallucinated import recorded in the earlier nudge-forced run, reproduced independently under a different mechanism — so it is a stable failure, not a sampling accident.

Read alongside the 18/20 forced-canary result and the single-line-bug success, the boundary looks like this: the model handles narrow, well-posed transformations where the correct output is close to what it was given, and does not reliably use evidence to revise a belief it has already committed to — whether that belief is "I have completed this task" (narration instead of action) or "this import is correct" (repeated after being shown the error).

## A related, independently-run finding

A separate probe (recursive sub-query pattern, unrelated infrastructure) found the same model, across five different configurations, terminating an exploration task without actually exploring — and twice emitting a confident final answer built on fabricated content rather than on anything it had verified. Different task, same shape of failure: the model produces something that *reads* as complete and grounded without the underlying action or verification that would make it actually true.

Taken together, the two findings point at the same underlying gap: the model is fluent at producing text that has the *shape* of correct, grounded, complete work, without a reliable internal signal that distinguishes "I described doing this" from "I did this." That looks like a candidate target for RL with a verifiable reward (did a tool call actually fire, did a file actually change, does a stated conclusion match ground truth) rather than a data-coverage problem — the model isn't unfamiliar with tool syntax or file operations; the forced canary proves it can execute them correctly when the task is narrow enough that "should I act" isn't in question.

## What we are not claiming

- Small sample size on the multi-step tasks (n=1 per condition, not n=20 like the canary) — the *direction* and *consistency* across two independent environments and three isolation checks is the evidence, not statistical power on any one number.
- No comparison against other models of similar active-parameter count, so we can't say whether this is specific to Mellum's training or a more general small-MoE-model characteristic. That's an open question worth asking rather than an answer we have.
- The repair results above are n=1 per bug class. The single-line-bug success and the catastrophic-bug failure are each one case, chosen to bracket the range rather than to sample it. The repeated-identical-wrong-import result was reproduced across two independent mechanisms, which is why we weight it more heavily than the rest.
- The repair experiment used a host-selected file, chosen by a simple traceback-substring heuristic. That heuristic is weak and in some rounds pointed at a file that was not the broken one, which consumed attempts. A better selector might improve the catastrophic-bug numbers; it would not affect the repeated-wrong-import result, where the correct file was supplied directly.

## Reproduction

Model and quantization: as above. Forced canary: a single fixed-instruction turn with one available tool, `n=20`, sampled independently. Multi-step task: a 3-phase web-app build spec (FastAPI + templates + a data model), run both as a fully detailed imperative version and as a high-level user-story version of the identical requirements, through an agent loop with tool access and no additional scaffolding. Correction mechanism: an engine flag that injects one bounded "continue" message through the tool-result channel after any turn with zero tool executions, capped at a fixed number of uses per turn. Exact commands, fixture files, and raw wire-protocol captures are retained and available on request.
