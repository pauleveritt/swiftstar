# `swiftstar-eval` cycle 1b: the P24.3 paired bill

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Answer P24.3 Task 12's pre-registered paired bill on the CLI built
by cycle 1a ([`2026-08-30-eval-cli-cycle-1.md`](2026-08-30-eval-cli-cycle-1.md)),
and record the DSML reversal and the ROADMAP row the design owes.

**Architecture:** Extract the app's turn loop into a SwiftUI-free
`AgentSession` in `SwiftStarAppKit` so an eval and the app cannot diverge
without failing to compile. Above it, three pure `SwiftStarKit` types —
`SpawnRecord`, `EvalExperiment`, `EvalReport` — carry the pre-registration,
the arm diff, and the report. `swiftstar-eval` absorbs `swiftstar-drive` and
`swiftstar-analyze`; `swiftstar-agenttest` is cycle 2.

**Tech Stack:** Swift 6 language mode, SwiftPM, swift-testing, macOS 26+.

**Spec:**
[`2026-08-30-eval-cli-design.md`](../specs/2026-08-30-eval-cli-design.md)

## Global Constraints

- **Plan style is `docs/sdd.md`'s local rule**, overriding
  `superpowers:writing-plans`: name files touched, interfaces (signatures
  only), and the test that proves it (test name + assertion, one line). No
  pasted bodies.
- **Binding rule 2:** every new test is shown to fail before it passes —
  break it, watch it fail, restore.
- **Binding rule 4:** every refusal test has a sibling success test.
- **Binding rule 5:** the capture is written to disk before anything reads it.
- **Binding rule 6:** the arm diff names the fixture it admitted and the one
  it refused.
- **No source-text assertions, ever** (binding rule 3).
- Fast tier must stay process-free and socket-free; the tripwire enforces it.
- Branch `eval-cli`, off `p24-3-run-digest-family`. Baseline at start: 906
  tests green.
- The submodule commit `2a86c86` is **not pushed**; it must be pushed before
  Task 11's artifact can be called reproducible.

---

**Depends on:** every task of cycle 1a, landed and green.

---

### Task 10: The P24.3 experiment, committed before it is run

**Files:**
- Create: `evals/p24-3-run-digest-family.json`
- Create: `evals/p24-3-prompt.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the pre-registered protocol — arms `control` (no `test`/`lint`)
  and `treatment`, `variable: "tools"`, `pairs: 3`, falsifier "the digest
  drops something decision-relevant", `captureSelection: "recordsWork"`.

- [ ] **Step 1: Write the prompt** — a **change-and-verify** task on this
      repository that genuinely needs `test` and `lint`, not a code-reading
      Q&A. The 2026-08-30 attempt failed partly because the prompt never
      exercised the treatment.
- [ ] **Step 2: Write the experiment file.**
- [ ] **Step 3: Dry-run** — `swiftstar-eval experiment --dry-run` prints the
      admitted arm diff and the run order, spawning nothing.
- [ ] **Step 4: Commit before any live run** —
      `P24.3 Task 12: the pre-registered paired bill`. The commit must precede
      Task 11's results commit in history; that ordering is the
      pre-registration.

---

### Task 11: Run the bill (live tier)

**Files:**
- Create:
  `docs/superpowers/research/2026-08-30-p24-3-run-digest-after-measurement.md`

**Interfaces:**
- Consumes: `evals/p24-3-run-digest-family.json`.
- Produces: the close-gate evidence — the falsifier answered either way.

- [ ] **Step 1: Push the submodule** — `2a86c86` and `70400f5` must reach the
      remote, or the treatment arm is unreproducible from a fresh clone.
- [ ] **Step 2: Build the engine** (`just engine`) and confirm the submodule
      SHA the record will carry.
- [ ] **Step 3: Run** `swiftstar-eval experiment evals/p24-3-run-digest-family.json`
      (minutes; never CI).
- [ ] **Step 4: Record the verdict** with `--record-verdict`, either way. A
      post-hoc rewrite of the threshold is this repository's documented
      anti-pattern; the report exits non-zero until the verdict is recorded,
      so there is no silent PASS.
- [ ] **Step 5: Write the after-measurement note** — per-pair deltas, the
      spread, the verdict, and explicitly what n=3 cannot support.
- [ ] **Step 6: Commit** — `P24.3: paired-bill measurement (run+digest family)`.

---

### Task 12: The amendments and the close

**Files:**
- Modify: `docs/superpowers/plans/2026-08-30-p24-3-run-digest-family.md`
  (lines 25, 1398, 1405, the fork-ledger row 15, and 1550)
- Modify: `ROADMAP.md` (a row for the eval CLI; P24 item (4) and the Backlog's
  "eval-system consolidation" point at it)

- [ ] **Step 1: Record the DSML reversal** beside each original, dated, per
      `docs/sdd.md`'s "kept as it was written" — never edited over. The
      substance: the `dispatch` precedent was applied to a tool the shipped
      model needs, which made divergence #16 unreachable for DeepSeek; #18 and
      the cross-family guard reversed it.
- [ ] **Step 2: Record the `Tools/p24-3-measurement/` → `evals/` relocation**
      in that plan's `## Result` section.
- [ ] **Step 3: Update `ROADMAP.md`** — the new row, `## Now`, and the two
      entries that now point at it rather than restating it.
- [ ] **Step 4: `just lint-docs`** — the new and modified rows must pass. The
      23 pre-existing violations in untouched closed-phase plans are **out of
      scope** (spec, "Out of scope") and are not to be silently fixed or
      silently ignored: name them in the commit message.
- [ ] **Step 5: Commit** — `P24.3: record the DSML reversal; ROADMAP: the eval CLI row`.

---

## Self-review notes

- **Spec coverage (this plan):** the Task 12 bill → Tasks 10, 11. Amendments
  owed (the DSML reversal, the `Tools/` → `evals/` relocation, the ROADMAP
  row) → Task 12.
- **Pre-registration is enforced by commit order:** Task 10 commits the
  experiment file before Task 11 runs it. A reviewer checks that ordering in
  git, not the prose.
- **Task 11 is the only live-tier work in either plan** and is never CI.
