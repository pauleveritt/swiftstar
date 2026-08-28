# P20 closure verdict — Delegation in one engine

**2026-08-27.** P20 closes: the two ship items (the `/orchestrate` coordination
loop and the dispatch-preference bootstrap rule) are landed and the loop is
live-validated end to end. Two forward items are descoped to the ROADMAP
(small-ctx workers → its own phase with P23; two-phase `/spike` → Backlog
behind P24). Spec:
[`2026-08-27-p20-orchestrate-loop-design.md`](../specs/2026-08-27-p20-orchestrate-loop-design.md).

## What shipped

1. **The `/orchestrate` loop, model-driven.** `OrchestrateDirective.build(task:
   writableFiles:)` (SwiftStarKit, pure/tested) is the prompt that turns the
   command into the loop; `AgentController.orchestrate(task:writableFiles:)`
   replaces `orchestrateStub()`; `AgentView` binds the parsed args. One-shot-
   first per P17: the model decomposes, dispatches, reads receipts, and does
   the remaining work itself — no host repair loop.
2. **The dispatch-preference rule, prompt-only.** `DispatchPreferenceRule.text`
   is appended to `-sys` at spawn (after the skills bootstrap), encoding the
   1809 capture's negative data point (never dispatch a watched interactive /
   open-ended turn).

Both are prompt text as specified (D3/D4), with 12 fast-tier tests
(`OrchestrateDirectiveTests`, `DispatchPreferenceRuleTests`).

## The finding that changed the spec

**D3 ("prompt-only, no engine patch") was falsified by measurement.** The first
live run fed the directive to the orchestrator and watched it do the whole task
itself: **34 tool calls, 0 dispatches** (18 bash, 7 write, 7 read, 1 edit, 1
list). Root cause, verified in source: `dispatch` is not in the shared
`agent_glm_tool_schemas` (11 tools, used by the GLM/Laguna/Mellum prompts
alike) — models call schema tools and ignore prose mentions of tools that are
not there. This is the "dispatch schema gap" first flagged in the P20 deep
review, now confirmed live.

**Fix: fork divergence #12** — `agent_schemas_for` appends a `dispatch` schema
line (`taskText`/`writableFiles`/`validationCommand`) iff `--host-tools` is
set, threaded through the three family builders and the system-prompt paths.
Committed on the engine's `p20-dispatch-schema` branch (parent gitlink updated).
A C unit test (`test_agent_schemas_gate_dispatch_when_host_tools_off`) pins the
gating. The wire is unchanged by the schema addition (it is model *input*, not
`--json-events` output), so no golden recapture is owed for this divergence.

## Live validation

One run, fixed seed 42, think budget 1500, `roadmap` spec, Laguna S:

```
orchestrator turn 1 ended (eos), dispatched 1 phase(s)
phase 1 — 4 mutation(s), validation failed (exit 1)
orchestrator turn 2 ended (eos), dispatched 0 phase(s)
PASS — 1 dispatch, 2 orchestrator turns, acceptance exit 0 (13/13), 695s
```

The pass bar (≥1 dispatch AND 13/13) is met. The shape is exactly the designed
one-shot-first loop: the orchestrator dispatched one phase, the worker produced
4 mutations whose phase-validation failed, the receipt folded back, and the
orchestrator integrated the work itself to 13/13 in the next turn — it did not
re-dispatch.

The comparison that matters: **0 dispatches in 34 tool calls without the schema
entry → 1 dispatch + 13/13 with it.** The schema, not the directive, was the
binding constraint.

## Caveats

- **n = 1.** This is a single validation run, not a rate. The model's dispatch
  behavior is seed-dependent (an unseeded run think-looped to the 8192-token
  limit with 0 tools). The claim is "the loop works," not "the model dispatches
  reliably" — the latter is P21's DumbImplementer eval territory.
- **The probe omits the skills bootstrap.** The headless driver does not stage
  skills or set the `-sys` skills index; it tests the directive + schema in
  isolation. The app's real spawn adds the skills index and the
  dispatch-preference rule.
- **Two pre-existing C test failures** (`[upto]` in the default edit prompt)
  are unrelated to this divergence and predate it at the pinned SHA.
- **The app's worker integration is worktree + candidate-ref**, while the probe
  uses a shared worktree (the dispatched worker writes the shared tree
  directly). The app-side candidate-apply step is the one follow-up this
  verdict does not ship — see the spec's integration note.

## Descoped (ROADMAP)

- **small-ctx workers** — its own phase, merged with P23's per-worker think
  control (fork divergence #13, golden recapture; depends on P22's XS
  recapture).
- **two-phase `/spike`** — Backlog behind P24 (phase 2 rides mediated bash).
