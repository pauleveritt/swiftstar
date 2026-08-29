# Superseded working documents

Three retirements live here.

## 2026-08-26: the 80-cell overnight ablation
All four covered the 80-cell overnight ablation of 2026-08-25→26 and are
**fully folded into**
[`../2026-08-26-overnight-80-cell-verdict.md`](../2026-08-26-overnight-80-cell-verdict.md),
which is the single authority for that night.

Kept only as a correction trail — each contains claims that were later measured
and found wrong, and the verdict record's "Retracted — do not reuse" table lists
them with the reason. **Do not cite anything from this directory.**

| file | what it was | why retired |
|---|---|---|
| `2026-08-26-mellum-whack-a-mole-repair-brief.md` | the opening brief that started the investigation | its premises (build wrote nothing, 2 rounds, one-traceback framing) were partly wrong |
| `2026-08-26-mellum-repair-harness-findings.md` | the harness investigation | counts taken from a still-running manifest (78 vs 80); missed two defects |
| `2026-08-26-r35-prompt-shape-ablation-verdict.md` | the prompt-shape ablation verdict | Mellum conclusions drawn from a harness-dominated pass rate |
| `2026-08-26-r35-prompt-shape-ablation-glm53-review.md` | GLM 5.3's adversarial review of the above | its findings are folded in; I3 turned out to be defect D3 |

## 2026-08-26: `/goal` v5, the repair-loop optimisation
`goal-ledger-v5.md` (see its **RETIRED** entry at the bottom for the reason),
plus its manifests and result files (`fixture-split.tsv`, `manifest-v5-dev.tsv`,
`results-v5-{baseline,int2,int3}.tsv`) and `stall-rate.py` (moved here from
`Tools/`). **Not** a finding that Mellum cannot repair — the dev screen it built
could not resolve an effect from engine noise at the `n` tried, and by the time
that was found, ROADMAP's `## Now` had already moved past the question this
loop existed to answer. Superseded by the `mellum-fixture` benchmark named in
`ROADMAP.md`.

## 2026-08-29: orphaned docs moved for hygiene, not because they were wrong

Moved during a ROADMAP/docs de-duplication pass (2026-08-29). Unlike the two
retirements above, these were not found to contain wrong claims — they were
moved because a repo-wide reference check found each one cited only from
`2026-08-24-overnight-consolidation.md` (itself moved here in the same pass,
still an unmerged staging document — see its own header), meaning nothing
outside this directory still depends on them. Kept for the record; not cited
by any current phase or verdict doc.

| file | what it was | why moved |
|---|---|---|
| `2026-08-24-overnight-consolidation.md` | staging area for several parallel Mellum/P11/engine-merge research threads, never merged or deduplicated | superseded as a live finding by `2026-08-25-local-model-agency.md`; only its own appendix docs still cited it |
| `2026-08-23-mellum-agentic-tool-use-finding.md` | early Mellum agentic tool-use finding | superseded as a live finding by `2026-08-25-local-model-agency.md` (see its own header note) |
| `2026-08-23-p11-agenttest-mellum-verification-record.md` | P11 agenttest verification record for the Mellum live run | superseded as a live finding by `2026-08-25-local-model-agency.md` (see its own header note) |
| `2026-08-23-p11-agenttest-telemetry-review.md` | GLM 5.2 telemetry critique of the P11 agenttest harness | superseded as a live finding by `2026-08-25-local-model-agency.md` (see its own header note) |
| `2026-08-24-handoff-packet-frontmatter-schema.md` | a handoff-packet frontmatter schema draft | orphaned — cited only from `2026-08-24-overnight-consolidation.md` |
| `2026-08-23-p11-kimi-k3-review.md` (67.8 KB) | Kimi K3's review pass over P11 work | orphaned, and mostly raw model chain-of-thought output rather than authored prose — see its own header note |
