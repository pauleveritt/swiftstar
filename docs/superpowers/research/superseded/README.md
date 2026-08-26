# Superseded working documents

Two retirements live here.

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
