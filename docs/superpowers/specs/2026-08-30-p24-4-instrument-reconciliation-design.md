# SwiftStar P24.4 design: instrument reconciliation

**Date:** 2026-08-30  
**Status:** implemented  
**Phase:** P24 — Digested first-class tools (cleanup cycle)

## Goal

Make `swiftstar-agenttest` measure the same host behavior that the app
delivers. This is an instrument-fidelity cycle: no new model capability, no
new tool, and no live campaign until the parity checks pass.

## Inventory findings

The existing rationale names two divergences:

1. `PoolOrchestrator` applies `ToolRefusalTracker` after three identical
   refusals and appends a corrective hint. The product paths do not apply that
   tracker. A pooled model therefore receives recovery guidance that a user
   session never receives.
2. The rationale describes the app as checking `toolCallBudget` post-hoc.
   Current code disproves that description: `AgentController` enforces the
   orchestrator budget when each request arrives, `AgentPoolTurnLoop` admits
   worker requests through `ActiveWorkerTurn`, and `PoolOrchestrator` uses the
   same `ToolCallBudgetTracker` boundary during its turn.

The second item is therefore a documentation and parity-test defect, not yet
a confirmed runtime divergence.

## Decisions

### Refusal corrective: drop from the measurement instrument

Remove the `ToolRefusalTracker` application from both `PoolOrchestrator`
paths. Keep ordinary refusal responses unchanged: the model receives the
host's actual refusal, with no synthetic coaching. Retire the tracker and its
instrument-only tests if no product caller remains.

Rationale: porting the corrective into the app would change user-visible
behavior and introduce a new product policy without evidence that it belongs
there. Keeping it in the harness would continue to bias measurements toward a
model that receives help the product does not provide.

### Tool-call budget: keep mid-turn enforcement and prove parity

Keep the existing boundary: request numbers `1...N` are admitted and request
`N+1` is refused, including when `N` is zero. The refusal is written to the
wire immediately and recorded in the turn outcome. Do not move enforcement to
turn end.

Add parity tests covering the shared `ToolCallBudgetTracker` and each host
loop's boundary behavior. Correct the stale rationale and comments that call
the app post-hoc. Any future change to budget semantics must change the shared
tracker and both loop tests together.

## Acceptance gates

- No `PoolOrchestrator` path invokes `ToolRefusalTracker`.
- Product and harness both refuse the first request at budget zero and the
  `(N+1)`th request at budget `N`, while admitting the first `N` requests.
- A budget refusal produces one `tool_result`, no host execution, and one
  host-verdict record in every loop.
- Existing refusal and budget tests remain green; no live model run is needed.
- The P24.4 measurement note records whether behavior changed. If the only
  change is removal of harness coaching, prior harness results are marked
  non-comparable rather than silently pooled.

## Out of scope

The deterministic tool ladder, `scout`, policy gating, model-asks-human,
validation-contract strength, and any model competence claim. Those remain
separate P24 work.

## Implementation shape

1. Red tests for the absence of corrective injection and the budget boundary
   matrix.
2. Remove the harness-only tracker calls and dead type if unreferenced.
3. Update comments and the P24 research trail to say budget parity is
   confirmed, not pending.
4. Run the fast and integration tiers; rebaseline only if a behavioral
   capture changes.
