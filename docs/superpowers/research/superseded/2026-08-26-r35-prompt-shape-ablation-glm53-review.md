# SwiftStar R3.5 — GLM 5.3 adversarial review

**Date:** 2026-08-26
**Reviewer:** `z-ai/glm-5.3` (OpenRouter), read-only, dispatched via `pi -p --no-session`.
**Reviewed:** `docs/superpowers/research/2026-08-26-r35-prompt-shape-ablation-verdict.md`.
**Disposition:** all findings verified against the captures before folding; two Criticals
were rebutted in part and the record corrected accordingly.

**Post-review:** a parallel session's
[`2026-08-26-mellum-repair-harness-findings.md`](2026-08-26-mellum-repair-harness-findings.md)
subsequently established that Mellum's 0/40 is harness-blocked (RepairLoop discard defect +
collection gate + context overflow + `turnDidNotEnd`), not model-measured. So this review's
Mellum-side findings (C3, I1–I6) were folded into a record whose Mellum conclusions were
then superseded; the review's value stands — it independently caught the implement-only
decomposition error (C2) and the quant confound (C3), and the `hello`-caps counting bug.

## Assessment

**Ready with fixes.** The core exit-code measurements (Laguna 39/40, Mellum 0/40) are
internally consistent, but the implement-only decomposition, the "path presentation is not
a lever" causal story, and the B8 non-replication language were overstated. Folded below.

## Critical

- **C1 — "40/40 Mellum hit a validation/import failure" vs 21/40 reached acceptance.**
  *Partly rebutted.* The reviewer conflated the phase-1 import check with the acceptance
  gate; all 40 Mellum runs do carry `validation-phase1` artifacts. The underlying point was
  valid: my wording was ambiguous and "reached acc" was misleading. Fixed — the record now
  defines "reached acc" as "survived to the acceptance step," explains that the harness
  writes its own `test_acceptance.py` and that exit 2 is collection failure on an empty tree,
  and states 0-tool-call Mellum runs end `stop_reason: eos`.

- **C2 — implement-only decomposition weaker than presented.** *Confirmed.* The 8 repair-
  artifact runs were re-examined per capture: **7 ended exit 0, 1 is the failure**
  (`relative/on` seed 1). So implement-only is **32/40 (80%)**, not 31/40; "rescued" is
  correlation, not causation; honest range 32–39/40. Fixed.

- **C3 — B8 non-replication did not test B8's conditions.** *Confirmed.* Mellum ran the
  Q4_K/Q8_0 selective build (`mellum-thinking-TARGET.gguf`, 9.33 GiB), not B8's Q8_0-only.
  Language softened to "not reproduced under a different quant, suite, and harness"; a
  Q8_0-matched control is named as the only thing that would reopen agentic Mellum. Fixed.

## Important

- **I1 — ceiling effect makes "path presentation is not a lever" untestable.** *Folded.*
  Finding 1 now states the falsifiable claim narrowly.
- **I2 — "cwd-fact ambiguity in disguise" is a causal story with no direct test.** *Folded.*
  Finding 2 now says "did not replicate," with the cwd-fact story labeled a hypothesis.
- **I3 — `mellum/relative/on` verdict inconsistency.** *Confirmed.* Seed 9 has `exit 2` but
  no `verdict.json`. Recorded as an unexplained data-quality gap in the caveats.
- **I4 — "zero tool calls" conflates refusal with early termination.** *Resolved by data.*
  All 40 Mellum runs end `stop_reason: eos`, so it is "narrates and stops," not a token wall.
  Stated in the record.
- **I5 — confidence interval understated.** *Folded.* Clopper-Pearson 39/40 ≈ 87–99.5% at
  95%; caveat 2 corrected.
- **I6 — cross-era comparability asserted only for the spec.** *Folded.* Caveat 1 now notes
  the engine and harness also changed since C18; the C18 3/9 comparison is qualified.

## Minor

Folded where applicable: seed design stated (same 10 seeds in every cell, independently
drawn); cell order stated as fixed/unrandomized (thermal caveat); "identical across all four
cells" reconciled against the 3/10 completion outlier; "still 0 calls" corrected (think-on
Mellum is 9/10 zero-call, not 10/10); the tool-counting correction is described as
re-applied to all 80 runs; the `google_search` call noted as a harness-exposed tool.
