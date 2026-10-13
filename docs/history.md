# History

Where SwiftStar's earlier record lives, after the 2026-10-13 docs slim.
`ROADMAP.md` keeps only current phases; this page keeps the way back.

## Two tags

- **`before-ds4-engine`** (`67109b6`): the code before P28 cut over to
  ds4-engine. It still has the forked C engine, the host-run tools, the
  subagent pool and both eval CLIs.
- **`docs-before-slim`**: every doc before the slim, including:
  - the P0–P27 specs, plans (with `plans/archive/`) and research
  - `docs/harvest/`, `laptop-ai.md`, `pathologies.md` and `remediations.md`
  - the Sphinx site
  - the full `ROADMAP.md`: the phase table, the P29 steps and the closed
    Backlog

To read one file, run `git show docs-before-slim:<path>`. To list them all,
run `git ls-tree -r --name-only docs-before-slim docs/`.

Links in the kept P28-onward specs and plans that point at a deleted doc
resolve at `docs-before-slim`.

## Phase P (P0–P32), closed 2026-10-04

**P0–P27** ran from 2026-08-21 to 2026-08-31. They built SwiftStar around
a forked C engine (`pauleveritt/ds4`). The work covered:
- launch, weights and the metrics tab
- capture and a diagnostics analyzer
- agent mode with host-run tools, skills, and a tool-callback wire
- worktree isolation, a subagent pool, and a reliable-agency harness
- a model ladder: Laguna S and XS, Mellum, DeepSeek V4 Flash
- host-controlled action mode and repair-limit experiments
- wire-level control and digested tools
- eval hygiene and an eval CLI

Verdicts that were later overturned are corrected next to the original
text, at the tag. One example: the P13 and P17 repair-depth reading was
overturned on 2026-08-29.

**P14, a docs site,** never ran. It was declined on 2026-10-13, when the
Sphinx site was removed.

**P28 removed that machinery.** The phases after it are the current app's
foundations:

| # | Phase | Closed | Record |
|---|---|---|---|
| P28 | Cut over to ds4-engine: one held `ds4-dogfood tui --ndjson` session | 2026-09-28 | [spec](superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md), plans [engine](superpowers/plans/2026-09-28-p28-ds4-engine-cutover.md) and [app](superpowers/plans/2026-09-28-p28-ds4-engine-cutover-app.md) |
| P29 | Make the front-end honest: session state, context gauge by fraction, dropped wire events, a quit that ends a turn, toolbar menus | 2026-10-04 | [review](superpowers/research/2026-09-28-p28-deep-review.md), [P29.1–4](superpowers/specs/2026-09-28-p29-1-4-honest-session-design.md), [P29.9](superpowers/specs/2026-09-28-p29-9-model-picker-design.md), [P29.10](superpowers/specs/2026-09-29-p29-10-toolbar-menus-design.md) |
| P30 | P29.10's deferred minors | 2026-10-04 | [plan](superpowers/plans/2026-10-04-p30-deferred-minors.md) |
| P31 | Fake-engine fidelity | 2026-10-04 | [plan](superpowers/plans/2026-10-04-p31-fake-engine-fidelity.md) |
| P32 | Structure and dead-code cleanup | 2026-10-04 | [plan](superpowers/plans/2026-10-04-p32-structure-cleanup.md) |

The finding behind BRIEF's first binding rule keeps its source in the tree:
[`harvest/telemetry-findings.md`](harvest/telemetry-findings.md).
