# Question queue — /goal v4

Decisions the loop took by policy instead of stopping. Each names the default
taken and which cells carry it. Answering one can flip flagged cells
retroactively from the kept captures, at **zero GPU cost**.

## 1 — Is `stop_reason=limit` a harness bound or a model property?

**Default taken:** model-behaviour observation, recorded on the row; the cell
contributes no pass/fail. **Cells:** `depth-2/2/3` (1 of 24).
Open since v2. `AGENTTEST_MAX_TOKENS` is 8192 and the run used ~1/3 of a 32768
context, so raising the output cap is available if you want it treated as a
harness bound instead. Would not change the P17 verdict at n=1.

## 2 — Is `contractNotFollowed` on a well-diagnosed turn a model or parser failure?

**Default taken:** model, flagged `disputed`. **Cells:** none in the final
recorded set — the affected cell (`depth-3/2/2`, superseded directive run) was
re-run and passed. Kept because the situation will recur: that turn diagnosed
all three defects correctly in prose, then emitted numbered prose with
unlabelled fences, so nothing was harvested.

## 3 — Should `framing-2` be replaced by a clean framing fixture?

**ANSWERED 2026-08-26** — `framing-2-edit` scored **5/6** against `depth-2`'s
**4/5**: with files-to-fix and task type held constant, evidence shape has no
measurable effect. The residual limit is authoring, as the verdict said. See the
verdict addendum. Original note follows.

**ADDRESSED 2026-08-26** — `fixtures/agenttest/repair/framing-2-edit` holds
files-to-fix (2) and task type (edit, no authoring) fixed against `depth-2` and
varies only the evidence shape. Pre-registered as 6 cells in
`experiment-manifest-framing.tsv`. The original default below stands for the
P17 verdict's own numbers, which are unaffected.

**Default taken:** kept, with the confound stated in the verdict rather than
silently carried. **Cells:** all 6 `framing-2` rows.
It varies evidence-shape, defect identity, and author-vs-edit together. A clean
crossing would hold the defects fixed and vary only whether the suite collects.
Building one would sharpen the residual finding; it was out of scope for a
pre-registered 24-cell manifest.

## 4 — The unnamed integration-tier flake

**Default taken:** not a stop condition under v4; loop continues. Four
occurrences, most recently fail-fail-pass-pass-pass. Reports
`failed with 1 issue` naming no test; `--xunit-output` did not produce a
parseable file. Affects no experiment number.
