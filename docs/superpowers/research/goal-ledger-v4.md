# Goal ledger v4 — P17 fixture-tier repair experiment

> **Answer the original question: is Mellum's multi-file repair failure a
> BUDGET limit, a FRAMING limit, or a DEPTH limit?**
>
> **Done when** every row of [`experiment-manifest.tsv`](experiment-manifest.tsv)
> (**24 cells** — 4 fixtures × 2 budgets × 3 seeds) has a recorded outcome,
> `harness-void` ≤ 4, and a dated verdict states the answer per arm with the
> numbers quoted.

Driven by [`.claude/commands/goal.md`](../../../.claude/commands/goal.md) v4.
Predecessors, both **closed records — no number from them enters this verdict**:
[`goal-ledger.md`](goal-ledger.md) (v1+v2, 13 iterations) and
[`goal-ledger-v3.md`](goal-ledger-v3.md) (v3, 8 iterations).

**Scope, stated up front and repeated in the verdict:** this measures repair
**in isolation from a pinned tree**, not repair in the pipeline. Pinning is what
makes the budget arm comparable at all — v2's budget comparison was worthless
because pipeline starting states were non-deterministic. The verdict must not
generalise to pipeline behaviour.

---

## 0 — 2026-08-26 — instrument (no GPU)

**did:** Built the multi-file fixture the 80-cell verdict named as the decisive
test on day one and that 21 iterations never built; generalised the fixture
runner to multi-file; pre-registered the 24-cell manifest.

**cells:** 0/24 recorded, 0 harness-void (quota 4), 0 disputed

**evidence:** baselines measured before any model touched them — the "red" for
the instrument:

```
=== plausible-wrong-fix   1 failed, 12 passed          FAILED test_post_complaint_redirects_to_complaints_board
=== depth-2               3 failed, 10 passed          FAILED test_home_html_element_declares_english_language
                                                       FAILED test_complaints_board_preserves_the_shared_layout
                                                       FAILED test_post_complaint_redirects_to_complaints_board
=== depth-3               4 failed,  9 passed          + FAILED test_complaint_model_contract_is_preserved
=== framing-2             1 error during collection    ModuleNotFoundError: No module named 'models'
```

**Design decisions, recorded because they shape every number that follows:**

- **"Depth" counts FILES THAT MUST CHANGE, not assertions.** depth-2 fails
  three assertions, not two: dropping `lang="en"` also trips
  `test_complaints_board_preserves_the_shared_layout`. Recorded rather than
  tuned away — forcing a 1:1 file:assertion mapping would have required a less
  natural defect.
- **The depth fixtures deliberately stay importable.** A defect in
  `models.complaints` aborts collection (`test_acceptance.py:26` reads it at
  module level) and *hides every other defect*. Building depth that way would
  have confounded depth with serialisation — the exact failure P16 exists to
  stop measuring.
- **framing-2 carries a stated confound.** It varies evidence-shape *and*
  defect-identity together (deleted `models.py` + an aliased import, vs
  depth-2's redirect + lang). A clean crossing was not achievable cheaply. Any
  framing claim must say this out loud.
- **24 cells, not "18–24".** Pre-registered means pinned. The framing arm gets
  its own fixture rather than displacing a depth level.

**Instrument changes:** `overlayTree` + `applyDeletions` in
`Sources/swiftstar-agenttest/main.swift` replace the hardcoded single-`app.py`
overlay (`copyItem` throws on an existing path, which is why the old tier
deleted `app.py` by hand first). A `.delete` manifest expresses defects that
consist of a file being *absent*. Single-file fixtures are unchanged — they are
the one-file case.

**next:** **run** — the depth arm at rounds=2, seeds {1,2,3}: 9 cells across
`plausible-wrong-fix`, `depth-2`, `depth-3`. Expect roughly 1–2 min/cell at
fixture tier. Row one is likely the first uncontested multi-file Mellum repair
number this project has produced.
