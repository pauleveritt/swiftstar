# P24 direction, naming, and the read-guard's re-scoping

**Date:** 2026-08-30
**Status:** reference — extracted verbatim from `ROADMAP.md`'s P24 Direction
cell, which had grown to 6345 characters (cap 900) by carrying this phase's
full motivation and mid-phase re-scoping history inline. Nothing here is new;
this is the trail `docs/sdd.md` says to move to `research/` and link, not
delete, when a cell blows its cap.

## Motivation

P9's deferred condensation direction, now motivated by the measured enemy:
the sum of prefill tails, each taxed by depth (231→134 tok/s over 12k→27k
ctx; **sharpened 2026-08-27 by our own production capture** — one file
re-read 31× = 29 syncs at exactly 1,809 suffix tokens = 37% of Σsuffix, see
[`2026-08-27-1809-prefill-tail-findings.md`](2026-08-27-1809-prefill-tail-findings.md)).

Deterministic host-owned **tools** (no model, millisecond Swift) — the P24.3
ladder: `test` (pytest → ~2 clustered representatives, lossless-for-the-
decision, full output re-runnable), `scout` (index-backed locate), `lint`
(ruff/pyrefly digests), **mediated bash** (host-run, deterministically
digested, policy-gated, never raw), and **model-asks-human** for the novel;
retires the shell-on expedient (2026-08-26). The model-backed half (ANE only
phrases) stays in the ANE watcher tier Backlog entry, gated on the two AFM
falsifiers.

**Naming:** a **tool** is deterministic (no model); a **subagent** has a
model in the loop.

The other legs of the prefill-tail attack are already scheduled: small-ctx
workers (now its own phase, merged with P23) and P20's dispatch-preference
rule, plus P21's DumbImplementer eval (the measurement).

**Source:** JetBrains RTK token-savings benchmark (2026-07), now corroborated
by our own capture — the guardrail: a tool's self-reported savings are a
claim about its counterfactual, not about your bill; measure the paired bill
with `swiftstar-analyze diff`.

## The read-guard's falsification and re-scoping (2026-08-30)

**Re-scoped — the read-guard is no longer cycle 1.** Review of its spec
falsified the premise that the model holds a whole file after a read: every
host tool result is condensed at 8000 bytes (`ToolCallbackResponder.swift
:259,284`), so for every file the guard targeted the model held head+tail
and never the middle. The 55 "redundant re-reads" are a **starvation loop**
— 32 reads of `AgentView.swift` in 22 distinct windows nearly all centred on
lines 240–320, including `start_line 252/max_lines 20` — which is also why
the trace shows 30 prefill syncs at suffix *exactly* 1809: a fixed-size
result, not a file.

**P24.1 became window-honoring reads** (host honors `start_line`/`max_lines`
/`whole`/`raw` in the engine's own format, `ds4_agent.c:8102-8174`,
byte-budgeted so results fit under the condenser untouched):
[`2026-08-30-p24-1-window-honoring-reads-design.md`](../specs/2026-08-30-p24-1-window-honoring-reads-design.md);
the guard's original spec and plan are superseded.

**P24.2 decided 2026-08-30** — the re-decision retired the read-guard and
retired the pool worker's `readCache` (one bug class: a hash-keyed
"unchanged" answer is dishonest whenever delivery is partial). See the
ROADMAP P24 row's Status cell for the outcome.

## The cleanup cycle's rationale

**Last cycle: reconcile the agenttest instrument with the product.** Not
de-duplication — the app parses the wire async on `@MainActor`
(`AgentController.swift:94`) while `PoolOrchestrator` runs a blocking
`Darwin.poll` loop, and there is no clean shared driver across those
concurrency models. The only confirmed behavioral divergence was the
harness-only refusal-streak corrective after three identical refusals
(`PoolOrchestrator.swift`); P24.4 drops that coaching so the harness receives
the same refusal the product sends. The earlier claim that
`toolCallBudget` was post-hoc in the app was stale: `AgentController` and
`AgentPoolTurnLoop` enforce the same shared `ToolCallBudgetTracker` boundary
mid-turn. P24.4 pins that parity with tests and corrects the record.

*Filed here because this is the fourth instance of the harness-not-the-model
trap; sequenced last so it cannot perturb an open campaign arm mid-phase.*
