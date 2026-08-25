# Fable review of the P12.4 repair-role spec (2026-08-24)

**Status:** research note; external adversarial review captured as written, with
the accepted/rejected synthesis. Not a plan.
**Reviewer:** OpenRouter `anthropic/claude-fable-5` (temperature 0.2), the same
reviewer that did the three C-section reviews in the overnight consolidation.

The spec under review is
[`2026-08-24-p12-4-repair-role-design.md`](../specs/2026-08-24-p12-4-repair-role-design.md).
The review's verdict was **not ready to plan against**; the findings F1–F11 and
the dispositions below were evaluated against the codebase (session model,
`writableFiles` constancy, verdict order, machine RAM) before acceptance.

## Synthesis — accepted and folded into the spec

- **F1 (Critical) — live-path repair would die of session context exhaustion.**
  Verified: one pooled worker session (worker 1) accumulates all three implement
  phases (C13 died at `ctx_pos=23301/32768`); a full-surface repair round injects
  5–9k tokens; D8's guard only *recorded* the death. **Fix adopted:** spawn
  `--subagent-pool 3` and dispatch repair rounds on the unused worker 2 (repair
  needs nothing from the implement session — evidence is re-injected per round by
  design; one extra session ≈ 8 GB on a 128 GB dev machine; no second model load).
  Both repair rounds share worker 2 (round 2 starts ~10–12k, fits 32k).
- **F2 (Critical) — fixture tier blind to the context regime.** Accepted in part,
  *mooted by F1's fix*: once repair always starts on a fresh worker session, the
  fixture tier's session regime matches the live path by construction. Residual
  divergence documented instead: fixture failures are single-test/small-output;
  live failures can be multi-test (C16 run 3: 7 failed). `packetBuilder` inputs
  are identical in both modes (packets are worktree-independent).
- **F3 (Important) — the plausible-wrong-fix "diagnosis" claim overstates.** The
  reviewer is right that pytest output quotes the acceptance test's assert lines,
  and that the assert (`307 == 303`) hands the model the expected value. Evidence
  kept full rather than scrubbed: the suite is non-gameable (not writable, not
  present in the worktree), so its assertion expectations are legitimate machine
  evidence, and `tests/test_app.py` *is* writable — the model can write a
  regression test reproducing the failure and run it via the vetted self-test
  command. **Fix adopted:** reword what the fixture measures (evidence-following
  over convention-recall, not "diagnosis under redaction"); weaken D7's "never
  sees" to "never sees the file or runs the suite; failure output may quote its
  assertion lines."
- **F4 (Important) — a receipt round is a deterministic replay.** Accepted: a
  receipt produces no new candidate and no new evidence; only a candidate that
  re-fails grading yields new evidence. **Fix:** a receipt terminates the loop
  immediately (`.repairExhausted` carries the receipt); the 2-round bound counts
  candidate-producing rounds only.
- **F5 (Important) — circular data flow + D3/D9 composition contradiction.**
  Accepted: `prepare()` needs the packet's `writableFiles` for baselines, so the
  authored packet must be built first (main.swift's existing seed-packet pattern).
  **Fix:** build authored packet → prepare → validate → append evidence at the end
  of `taskText` under a "Failure evidence (machine output)" header; D3/D9
  reconciled to one order.
- **F6 (Important) — "same writableFiles" undefined.** Accepted as a wording fix:
  in this harness `writableFiles` is one constant shared by every phase, so the
  per-phase concern does not bite; the spec now states this explicitly.
- **F7 (Important) — open-loop repair unexamined.** Accepted as a caveat: the 3/3
  evidence ran with unsandboxed bash; open-loop transfer is unexamined. Stated in
  the spec; the writable-self-test avenue (from F3) is the model's only in-loop
  verification, and host-side re-grade stays the only authority (doctrine).
- **F8 (Important) — no per-round capture.** Accepted: per-round
  `repair-packet-N.json`, verdict/receipt, candidate ref, grade exit+digest,
  timings into the capture dir; run-config gains repair fields.
- **F9 (Minor) — repaired ref integration unspecified.** Accepted: `.passed`
  retains the passing round's worktree as `finalWorktree`; main.swift's code dump
  and DeepSeek grader run against the repaired tree.
- **F10 (Minor) — no evidence size policy.** Accepted: pytest output tail-capped
  (last ~8 KB — failures print the full HTML response body in asserts); per-file
  content cap; policy recorded in the round record.
- **F11 (Minor) — authored/machine boundary by convention.** Accepted: a
  `MachineEvidence` type constructible only from `GradeResult` + worktree reads; a
  non-fatal audit logs redact-hits in evidence (which usefully announces "the
  fixture's answer is present in the failure output").

## The review, as written

The full reviewer response follows verbatim (the first attempt hit the 8192-token
cap mid-F2 and was re-run at 32k; this is the complete second response).
# Review: SwiftStar P12.4 — The repair role

## F1 — Live-path repair is near-certainly doomed by session context exhaustion; D8 is a tombstone, not a guard
**Severity: Critical. Refs: D2, D3, D8, Data flow; settled facts (ctx_pos=23301/32768 at phase 3; session accumulates; contextFull bricks the pooled session).**

The repair rounds dispatch through `orch.runPhase` — i.e., the same pooled worker session (worker 1) whose context has already accumulated three implement phases. A completed 3-phase run lands in the neighborhood of the observed 23k of 32k. Now D2 injects the *complete content of every writable file* plus the pytest failure output into `taskText`, plus pinned facts, contract, and writable note (D3), plus the turn's own tool traffic — and edit/write tool calls echo file content back into context a second time. Conservatively, one repair round costs 6–10k tokens of prompt alone before the model generates anything. Round 1 starts at ~23k and races the 32k ceiling; round 2 — carrying round 1's full injection *still resident in the session* plus a *second* full injection of updated contents and new failure output — is arithmetically impossible in most runs.

D8's "guard" is: if the turn ends `contextFull`, stop the run. That is not recovery, it's a receipt for the funeral. The design's own motivating case — implement completes all phases, fails acceptance on one wrong import line — is exactly the case where the session is fullest. The feature will work in fixture mode (fresh session, see F2) and fail on the live path it was built for, and the failure will look like "repair didn't help" rather than "repair never had room to run."

**Fix (pick one, state it in the spec):**
1. **Fresh session for repair.** Repair is post-grade, host-owned, and needs none of the implement session's conversational state — everything it needs is in the packet by design (that's the whole point of D2/D3). Spawn a fresh worker (pool of 3, or re-spawn `ds4-agent` accepting the model-load cost, or a session-reset primitive if the engine has one). Reset again between rounds, since round 2 re-injects everything.
2. **Pre-flight context accounting.** `RepairLoop` estimates injected-token cost against remaining session budget before dispatch and returns a typed `Receipt.contextBudgetExceeded` *instead of* dispatching into a wall — a receipt is recoverable bookkeeping; a mid-turn `contextFull` bricks the session.

Option 1 is correct; option 2 is the minimum honesty bar. The spec currently has neither.

## F2 — The fixture tier does not exercise the binding constraint; the only test that would is "never CI"
**Severity: Critical. Refs: D10, Testing.**

`--fixture` mode skips the implement phases: the pooled worker session is **empty** when repair dispatches. Per F1, session occupancy is the dominant live-path risk, and the "primary test that the loop localizes and fixes" runs at the one point in configuration space where that risk is zero. Further divergences: fixture grade is a guaranteed single-failure 12/13 with small, pre-verified output; live grades from a broken handler or wrong lazy import can fail several of 13 tests with multi-KB pytest output (see F10). The fixture repo also has no implement history, so `packetBuilder`'s facts/contract inputs differ from the live call site — the spec doesn't say how they're reconciled. The live tier (`just capture`) is explicitly never CI, so the doomed configuration ships untested until someone burns a live run. **Fix:** add a fixture variant that pre-loads the worker session to a realistic occupancy (e.g., replay a captured implement transcript or pad with a scripted burn turn) before repair; make the fixture grade output size and failure count representative; specify what `packetBuilder` receives in fixture mode vs live.

## F3 — The `plausible-wrong-fix` L1 claim is wrong: the machine-evidence exemption hands the model the answer
**Severity: Important. Refs: D6, D10, fixture facts.**

The fixture's design intent is "tempting 302, correct 303, redact 303 so only genuine diagnosis lands it." But D6 exempts the pytest output, and the pytest output is `assert 307 == 303`. The model does not need to diagnose FastAPI redirect semantics or resist the 302 temptation; it needs to copy the right-hand side of an assert that was placed in its prompt. `AGENTTEST_REDACT=303` becomes theater: it guards the authored channel while the evidence channel delivers the redacted string verbatim. The fixture, run through this loop, measures assert-reading, not diagnosis. That may still be an acceptable bar for L1 — but then say so, and stop claiming it validates diagnosis under redaction.

Related erosion of D7: pytest tracebacks include **source lines of the failing acceptance test**. Over two rounds the model sees a nontrivial fraction of the acceptance test's logic. "The model never sees the acceptance suite" is no longer true; it sees exactly the parts that failed, which are exactly the parts it could overfit a patch to. **Fix:** decide the trade-off explicitly — e.g., `--tb=short`/`--tb=line` or a host-side scrubber for evidence, and rewrite the D10 success claims to match what the fixtures actually measure.

## F4 — Receipt-as-failed-round buys a deterministic replay of the same failure
**Severity: Important. Refs: D4; sampling = nothink, temp 0.**

A receipt round produces no new candidate ref and no new grade output, so round N+1 dispatches from the **same head** with the **same evidence** and the **same packet**, at temperature 0 with thinking off. The only source of variation is the accidental fact that the pooled session accumulated round N's turn — which is (a) not a mechanism you designed, (b) exactly what F1's fix (fresh session per round) removes. So under the corrected design, a receipt round makes round 2 a bit-identical retry: guaranteed waste of a round and of wall-clock. Only a *candidate that re-fails grading* produces new evidence and justifies another round. **Fix:** a receipt terminates the loop immediately with `.repairExhausted` (carrying the receipt); the 2-round bound applies to candidate-producing rounds only.

## F5 — The data flow is circular as written, and D3 contradicts D9 on packet composition
**Severity: Important. Refs: D3, D9, Data flow step 2.**

Step 2 calls `WorktreeDispatcher.prepare(packet, baseRef: head)` *before* building the packet — but building the packet requires reading file contents *from the prepared worktree*. Chicken and egg; as written it cannot execute. Separately, D3 says taskText is composed as facts → **directive (failure output + file contents)** → contract → writable note, i.e., evidence in the middle; D6/D9 say evidence is **appended after validation**, i.e., at the end, after the writable note. Both cannot hold. This matters: prompt position of a multi-thousand-token evidence blob relative to the contract and writable note is not cosmetic for a 32k-context Q2_K model. **Fix:** define the sequence as prepare(baseRef) → read contents → build authored packet → validate → inject evidence at a *specified* position → dispatch; reconcile D3 and D9 to one composition order.

## F6 — "Same `writableFiles`" is undefined — same as *which* phase's packet?
**Severity: Important. Refs: D2, D3.**

Implement packets are per-phase; their `writableFiles` differ. The live failure class (wrong import surfaced at acceptance) can live in a file from *any* phase. If the repair packet inherits phase 3's set, a phase-1 bug is unfixable by construction: the revision check will yield `.refusedTool` on the correct edit, which under D4 burns a round (and under F4's fix, ends the loop). **Fix:** the repair packet's `writableFiles` is the union across all phase packets, stated explicitly; note the D2 context-cost consequence (full content of the union is the largest possible injection — feeds F1).

## F7 — In-harness repair is open-loop, which is a condition the 3/3 evidence never tested
**Severity: Important. Refs: D3, D7, Out of scope; settled repair-evidence facts.**

The failing test lives only in the harness-owned suite, absent from the worktree; bash is limited to the two vetted commands; `selfTestCommand` runs workspace tests that (by construction of the failure) pass. So the repair turn **cannot reproduce the failure it must fix, and cannot verify its fix** — verification exists only at re-grade. The 3/3 evidence was gathered with *unsandboxed bash* via `repair.py`; whether the model exercised reproduce-and-verify there is unrecorded, so the transfer of that evidence to an open-loop regime is an unexamined assumption, on top of fixtures deliberately harder (misleading locus) than the measured bug class (traceback quotes the defective line). **Fix:** at minimum, state open-loop operation as a design consequence and an evidence caveat in the spec; consider whether a host-derived, vetted repro command (e.g., a request-level probe, not the test file) is worth adding, and if not, say why.

## F8 — `RepairLoop` records almost nothing; `.exhausted` discards the history that explains it
**Severity: Important. Refs: D9.**

`.exhausted(lastGrade, .repairExhausted)` drops: per-round packets (what did the assembled taskText actually contain, evidence included?), per-round verdicts/receipts, intermediate candidate refs (a wrong fix is a *diagnostic artifact* — you want that diff), grade output digests, timing, and run config (`AGENTTEST_REPAIR_THINK`, redacts). The doctrine says success is files-written-and-grades, never self-report — which obligates the harness to capture what it graded. Without per-round packet.json equivalents, the next evidence-gathering cycle (P12.6 bounded thinking) has nothing to compare against. **Fix:** `RepairLoop` returns/emits a per-round record: assembled packet digest + evidence, verdict, candidate ref or receipt, grade result, timings.

## F9 — The repaired ref's integration is unspecified
**Severity: Minor. Refs: D9, Data flow.**

Implement ends with `commitBack()` *then* grading. Repair's `.passed(ref, grade)` produces a candidate ref in a round worktree that the flow then… does what with? Nothing states the repaired ref is committed back or that the recorded final artifact is the repaired ref rather than the failed implement ref. **Fix:** specify `.passed` triggers the same commit-back path and that the run record points at the repaired ref.

## F10 — Evidence injection has no size policy
**Severity: Minor (Critical in combination with F1). Refs: D2, D6.**

Neither pytest output nor file contents are bounded. A multi-test failure with long tracebacks, or a large writable file, blows the injection budget silently. **Fix:** explicit truncation/summarization policy for evidence (per-file byte cap, `--tb=short`, failure-count cap), recorded in the round record (F8).

## F11 — The authored/machine boundary is enforced by convention, not by the validator or the types
**Severity: Minor. Refs: D6, D9.**

Post-validation appending means the one component that ever caught contamination (the validator, which caught a spec shipping its answer) is structurally blind to everything added after it runs. Today the only thing keeping authored content out of the evidence channel is that `RepairLoop`'s code happens to only put grade output and worktree reads there. **Fix:** type the evidence channel (e.g., `MachineEvidence` constructed only by `RepairLoop` from `GradeResult` + worktree reads, never from `packetBuilder` inputs), and have the validator run a *non-fatal audit* pass over evidence for redact hits, logged not enforced — so a future leak is at least visible.

---

## Verdict

**Not ready to plan against.** F1 and F2 are disqualifying together: as specified, the live path — the only path that matters, per the run data motivating P12.4 — dispatches full-surface repair into a session already at ~70% of context, with a "guard" that merely records the death, and the primary test tier is constructed to never observe this. F4, F5, and F6 are spec-level defects that would be discovered painfully during implementation (a circular data flow, a contradictory composition order, an undefined file set that can make the correct fix a `refusedTool`). Land F1's session strategy, F2's occupancy-realistic fixture, and the F4–F6 corrections before writing a line of `RepairLoop`. F3 doesn't block implementation but blocks the *claims*: rewrite what the fixtures measure before anyone cites `plausible-wrong-fix` as evidence of diagnosis under redaction.

What's genuinely sound: D1 (post-grade recovery, not a phase), D5 (fresh worktree per round), the D9 closure split for model-free testing, and the decision to kill the host-side file picker — the picker was the proven failure; removing it is right even though D2's "inject everything" implementation of that decision is what creates F1. Keep the decision, change the mechanism: no host picker can coexist with model-side localization via read tools against a fresh session, at a fraction of the injection cost.