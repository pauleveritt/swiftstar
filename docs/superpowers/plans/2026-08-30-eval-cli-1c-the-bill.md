# `swiftstar-eval` 1c: the P24.3 paired bill

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Answer P24.3 Task 12's pre-registered paired bill on the CLI built
by plans 1a and 1b, and record the two amendments the design owes — the DSML
reversal and the ROADMAP row.

**Architecture:** No new code. This plan commits an experiment file, runs it
live, records the verdict either way, and writes the decision record.

**Tech Stack:** the shipped `swiftstar-eval`; real engine, real weights, Metal.

**Spec:**
[`2026-08-30-eval-cli-design.md`](../specs/2026-08-30-eval-cli-design.md)

**Depends on:** plans
[1a](2026-08-30-eval-cli-1a-kit-types.md) and
[1b](2026-08-30-eval-cli-1b-cli-and-extraction.md), landed and green.

## Global Constraints

- **Pre-registration is enforced by commit order.** Task 1 commits the
  experiment file before Task 2 runs it; a reviewer checks that ordering in
  git, not in prose. The CLI additionally refuses an uncommitted or dirty
  experiment file.
- **Live tier only, never CI.** Minutes to ~25 minutes per run, and this is
  five interleaved pairs.
- **After-measurement discipline:** a post-hoc rewrite of the threshold is
  this repository's documented anti-pattern. The verdict is recorded either
  way, and the report exits non-zero until it is.

---

### Task 1: The experiment, committed before it is run

**Files:**
- Create: `evals/p24-3-run-digest-family.json`
- Create: `evals/p24-3-prompt.md`

**Interfaces:**
- Consumes: everything plans 1a and 1b ship.
- Produces: the pre-registered protocol — `variable: "tools"` (real now that
  the engine takes `--tools`), arms `control` (`read,write,list,search,bash`)
  and `treatment` (`+test,lint`), `pairs: 5`, falsifier "the digest drops
  something decision-relevant", `captureSelection: "recordsWork"`.

- [ ] **Step 1: Write the prompt** — a **change-and-verify** task on this
      repository that genuinely needs `test` and `lint`: make a small change
      and establish that it is correct. Not a code-reading Q&A. The
      2026-08-30 attempt failed partly because its prompt never exercised the
      treatment, so a treatment arm that never calls `test` is a failed run,
      not a null result.
- [ ] **Step 2: Write the experiment file**, `common` pinning variant,
      context, power, shell, host-tools and the workspace so that `tools` is
      the only axis the diff will admit.
- [ ] **Step 3: Dry-run** — `swiftstar-eval experiment
      evals/p24-3-run-digest-family.json --dry-run` prints the admitted arm
      diff and the ten-run order, spawning nothing. If the diff refuses,
      **fix the file, not the guard.**
- [ ] **Step 4: Commit before any live run** —
      `P24.3 Task 12: the pre-registered paired bill`.

---

### Task 2: Run it

**Files:**
- Create:
  `docs/superpowers/research/2026-08-30-p24-3-run-digest-after-measurement.md`

**Interfaces:**
- Produces: the close-gate evidence — the falsifier answered either way.

- [ ] **Step 1: Confirm the engine** — `just engine`, and confirm the
      submodule SHA the record will carry is the pushed one (divergence #18,
      the cross-family guard, and #19's `--tools`). All three must be on
      `origin`, or the artifact is unreproducible from a fresh clone.
- [ ] **Step 2: Run** `swiftstar-eval experiment
      evals/p24-3-run-digest-family.json`. Ten runs, five interleaved pairs,
      each in its own worktree.
- [ ] **Step 3: Read the report before forming a view** — per-pair deltas, the
      spread, the dropped pairs and their reasons, and the attempt number.
      A pair dropped for `recordsWork` is a fact about the run, not noise to
      be discarded quietly.
- [ ] **Step 4: Answer the falsifier** — did the model act correctly on the
      digest alone in the treatment captures? Record it with
      `swiftstar-eval verdict <results-dir> --record claimSurvives|claimFalsified
      --evidence <path>`, citing the capture and turn that decides it.
- [ ] **Step 5: Write the after-measurement note** — the per-pair deltas, the
      spread, the verdict, the attempt number, and **explicitly what five
      pairs cannot support**. If the deltas straddle zero, say the question is
      unanswered at this n; that is a result, not a failure.
- [ ] **Step 6: Commit** — `P24.3: paired-bill measurement (run+digest family)`.

---

### Task 3: The amendments and the close

**Files:**
- Modify: `docs/superpowers/plans/2026-08-30-p24-3-run-digest-family.md`
  (lines 25, 1398, 1405, the fork-ledger row 15, and 1550)
- Modify: `ROADMAP.md`

- [ ] **Step 1: Record the DSML reversal** beside each original, dated, per
      `docs/sdd.md`'s "kept as it was written" — never edited over. The
      substance: Task 10 recorded "the DSML/DeepSeek block is untouched (the
      `dispatch` precedent)" as a deliberate decision. Applying that precedent
      to `test`/`lint` — tools the model SwiftStar actually ships needs — is
      what made divergence #16 unreachable, and it is why the 2026-08-30
      treatment arm had no treatment. Engine `70400f5` (#18) and `2a86c86`
      (the cross-family guard) reversed it. A schema the shipped prompt never
      builds is not a schema.
- [ ] **Step 2: Record the relocation** of Task 12's
      `Tools/p24-3-measurement/` to `evals/` in that plan's `## Result`
      section — which also gives that plan the `## Result` section
      `docs/sdd.md` requires at close and no plan in this repository yet has.
- [ ] **Step 3: Update `ROADMAP.md`** — one row for the eval CLI; P24's item
      (4) and the Backlog's "eval-system consolidation" entry point at it
      rather than restating it; `## Now` reflects what is in flight.
- [ ] **Step 4: `just lint-docs`** — the rows this task touches must pass. The
      pre-existing violations in untouched closed-phase plans are being fixed
      separately; name that in the commit message rather than silently
      inheriting or silently fixing them.
- [ ] **Step 5: Commit** — `P24.3: record the DSML reversal; ROADMAP: the eval CLI row`.

## Self-review notes

- **Spec coverage (this plan):** the Task 12 bill → Tasks 1, 2. Amendments
  owed → Task 3.
- **Cycle 2 is not here.** Absorbing `swiftstar-agenttest` onto `AgentSession`
  — which is also what closes P24's cleanup item (4) — gets its own spec and
  plan once this cycle's evidence is in.
- **The one judgement call left to the runner** is Task 2 Step 4: the
  falsifier is a human verdict, and the tool deliberately cannot compute it.
  What the tool guarantees is that the verdict is recorded, evidenced, and
  attributable — not that it is correct.
