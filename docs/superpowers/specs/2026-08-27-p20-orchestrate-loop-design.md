# SwiftStar P20 design: orchestrate loop + dispatch-preference

**Date:** 2026-08-27
**Status:** proposed
**Phase:** P20 — Delegation in one engine (closing)

This spec is the authority on the two items that close P20: the `/orchestrate`
coordination loop (model-driven) and the dispatch-preference bootstrap rule
(prompt-only). P20's other two forward items are **descoped** here and recorded
in the ROADMAP: **small-ctx workers** → its own phase, merged with P23's
per-worker think control (one engine patch, fork-ledger row #12, recapture);
**two-phase `/spike`** → Backlog behind P24 (phase 2 rides mediated bash).

Scope is strict: the directive and the rule are *prompt text* — no new wire
kind, no host-driven state machine. **Amended by live measurement (2026-08-27):**
the model-driven loop also required an engine patch — `dispatch` had to be
added to the advertised tool schema (fork divergence #12), because without it
the model made 0 dispatches in 34 tool calls. See D3 and the
[closure verdict](../research/2026-08-27-p20-closure-verdict.md). The loop is
*model-driven*: the model is the orchestrator; the host's existing machinery
(`dispatch` tool, pool, receipt injection, parent-side validation) is the
substrate it drives.

## Problem

`/orchestrate` is a stub. `AgentView` routes the command to
`controller.orchestrateStub()`, which appends a placeholder row
("→ orchestrate: the coordination loop lands with P20"). The machinery the
loop needs is already shipped and tested:

- the `dispatch` host-tool (model calls `dispatch(taskText, writableFiles,
  validationCommand)` → enqueued worker → receipt) rides the P9 wire
  (`AgentController`, the `toolRequest` `name == "dispatch"` branch);
- the pool runs the worker in the *same* engine (`--subagent-pool`), with
  parent-side validation and a typed `DispatchReceipt` folded back
  (`finishWorkerTurn` → `injectPendingReceipts`);
- decompose machinery exists and is pure/tested (`Decompose.swift`,
  `DecomposePacket`, `DecomposeDispatch`);
- `CommandRouter` already parses `/orchestrate <task> --files a,b`.

What is missing is the *orchestrate directive* — the prompt that tells the
model to run the loop — and the wiring that replaces the stub. The second
missing piece is a *dispatch-preference rule*: today nothing tells the model
*whether* to dispatch, and the measured behavior is that it doesn't (the
2026-08-26 spike ran 1,232 think events and "never dispatched to the pool
worker on its own"; the 2026-08-27 1809 capture's two exploration turns were
correctly *not* dispatched because they had no acceptance predicate).

## Scope (strict)

**In:**

1. The `/orchestrate` loop: a directive prompt + the `/orchestrate` wiring
   that replaces `orchestrateStub()`.
2. The dispatch-preference rule: an always-on system-prompt rule governing
   when the agent prefers `dispatch`.
3. Fast-tier tests for both prompt constants (they are pure text).
4. One live real-engine orchestrate run as the closure evidence.

**Out (explicit):**

- small-ctx workers (its own phase, merged with P23) — ROADMAP.
- two-phase `/spike` (Backlog behind P24) — ROADMAP.
- Any host-driven loop: the app does **not** decompose or dispatch on its own
  (`PoolOrchestrator` stays a headless-harness concern; no state machine in
  the app).
- Any automatic repair/retry loop (see D2).
- Model switching, SSD, new models (P22/P25).
- New UI beyond the existing transcript (receipts already render as system
  rows; consult answers already render as `.consulted` panels).

## Design decisions

- **D1 — the loop is model-driven.** The orchestrator is the app's main agent
  session. It decomposes, calls `dispatch`, reads receipts, validates, and
  writes files itself. The host supplies the substrate (dispatch tool, pool,
  receipt folding, validation) and nothing more. This matches the glossary
  ("orchestrator: writes the plan, builds each task's handoff packet,
  evaluates implementer results against validation. Writes files.") and reuses
  the already-shipped dispatch path instead of duplicating `PoolOrchestrator`
  in the app target.

- **D2 — one-shot-first, no automatic repair loop.** The directive instructs
  the model to dispatch each phase once, and on a refusal to do the work
  itself (or re-dispatch at most once with a corrected packet). This follows
  P17's verdict — "more rounds did not help editing"; Mellum edits 15/17
  one-shot once the false directive is removed — so the app never runs a
  host-side repair loop and the model is never told to loop.

- **D3 — the directive and the rule are standalone, testable Swift
  constants.** They live in `SwiftStarKit` (not the app target, which has no
  test target) as pure text, so the fast tier asserts the required clauses are
  present without any engine. **Amended 2026-08-27:** "no engine patch" did
  not survive measurement — the model ignores a prose-named tool that is not
  in the engine's advertised schema (0 dispatches in 34 tool calls), so
  `dispatch` was added to the schema under `--host-tools` as fork divergence
  #12 (see the [closure verdict](../research/2026-08-27-p20-closure-verdict.md)).
  The prompt-only parts of D3 stand for the *directive* and the *rule*; the
  loop's dispatch step needs the schema entry.

- **D4 — dispatch-preference is prompt-only.** No new app state, no Settings
  toggle, no wire field. The rule is text in the system prompt. (If P21's
  DumbImplementer eval later shows the rule misfiring, a toggle is the
  follow-up — not part of P20.)

- **D5 — `/orchestrate --files` is scope context, not enforcement.** The
  files flag names the intended writable scope and is embedded in the
  directive as context for decomposition. Enforcement stays where it already
  is: per-dispatch-packet `writableFiles`, revision-checked host-side
  (`ToolCallbackResponder` / `WorktreeDispatch.verdict`).

- **D6 — one turn, one user row.** `/orchestrate` sends the directive + task
  as a single user turn (the task is the user's intent; the directive is the
  "how"). A distinct `.orchestrate` transcript row kind for cleaner rendering
  is a possible later polish, not v1.

## The orchestrate directive

`OrchestrateDirective.build(task: String, writableFiles: [String]) -> String`
returns the full turn text. Requirements the text must satisfy (each is a test
assertion):

1. Names `dispatch` and its three parameters exactly (`taskText`,
   `writableFiles`, `validationCommand`).
2. Instructs decomposition into phases with machine-checkable acceptance.
3. States one-shot-first: dispatch each phase once; on a refusal, do the work
   yourself; re-dispatch at most once with a corrected packet.
4. Requires validating the integrated result (no success claim without the
   validation command exiting 0).
5. Forbids dispatching an open-ended exploration or a watched interactive turn
   with no acceptance predicate.
6. Embeds the task verbatim and the writable scope (the `--files` list, or
   "the whole workspace" when empty).

Directive text (the shipped constant):

> You are in orchestrate mode: run a multi-phase task end to end, then write
> the result.
>
> Work in this order:
> 1. Decompose the task into phases. Each phase is a bounded unit of work with
>    a machine-checkable acceptance criterion (a command whose exit status
>    decides pass/fail).
> 2. For each phase, dispatch it to a subagent with the `dispatch` tool, giving
>    exactly three parameters: `taskText` (the phase's objective),
>    `writableFiles` (a comma-separated list of the files that phase may
>    touch), and `validationCommand` (the command you will run to check the
>    phase).
> 3. A dispatch returns a receipt: a candidate ref on success, or a typed
>    refusal (refusedTool / budgetExceeded / validationFailed / noChanges).
>    Read the receipt.
> 4. One-shot-first: dispatch each phase once. If a phase's receipt is a
>    refusal, do the phase's work yourself in the workspace instead of
>    re-dispatching. Re-dispatch at most once, and only with a corrected
>    packet.
> 5. Integrate the phases and validate the whole result with the validation
>    command. Do not claim success unless the command exits 0.
> 6. Never dispatch an open-ended exploration or a watched interactive turn
>    that has no acceptance predicate — do that work yourself.
>
> Writable scope for this task: <list or "the whole workspace">.
>
> Task: <task>

## The dispatch-preference rule

`DispatchPreferenceRule.text` — an always-on rule appended to the agent's
system prompt (`-sys`), after the Superpowers skills bootstrap. Requirements:

1. Prefer `dispatch` when a piece of work has a machine-checkable acceptance
   predicate and an exact writable-file set.
2. Never dispatch a watched interactive turn or an open-ended exploration with
   no acceptance predicate — do that work yourself.
3. After a few rounds of exploration, stop exploring and either dispatch with a
   concrete acceptance contract or do it directly.

Rule text (the shipped constant):

> Dispatch preference: when a piece of work has a machine-checkable acceptance
> predicate and an exact writable-file set, prefer dispatching it to a
> subagent via the `dispatch` tool rather than doing it inline. Do not dispatch
> a watched interactive turn or an open-ended exploration with no acceptance
> predicate — do that work yourself. After a few rounds of exploration, stop
> exploring and either dispatch the work with a concrete acceptance contract
> or do it directly.

## Wiring

All changes are additive; nothing in `CommandRouter` or the pool path changes.

1. **`SwiftStarKit/OrchestrateDirective.swift`** (new): `OrchestrateDirective`
   (`build(task:writableFiles:)`) and `DispatchPreferenceRule` (`text`). Pure,
   `Sendable`, no imports beyond `Foundation`.

2. **`AgentCommand` / `AgentController.startAgent`** — append
   `DispatchPreferenceRule.text` to the `-sys` content at the same point the
   skills bootstrap is set (`AgentController.swift:397`):
   `settings.systemPrompt = bootstrap.indexPrompt + "\n\n" +
   DispatchPreferenceRule.text`. The rule is present for every agent spawn,
   so plain agent mode and `/orchestrate` both see it.

3. **`AgentController.orchestrate(task:writableFiles:)`** (new, replaces
   `orchestrateStub()`): trims the task, builds the directive via
   `OrchestrateDirective.build`, and sends it as a user turn through the
   existing `send(_:asUser:)` path (which already guards `canSend`, opens the
   outcome builder, and writes the `PoolPrompt` for worker 0). Remove
   `orchestrateStub()`.

4. **`AgentView`** — bind the associated values the router already parses:
   `case .orchestrate(let task, let writableFiles):` →
   `controller.orchestrate(task: task, writableFiles: writableFiles)`.
   (Today the case discards them and calls the stub.)

## Surfacing

No new UI. The loop is already visible through the existing transcript: the
`dispatch` tool call renders as a tool card; the worker receipt folds back as a
quiet system row (`injectPendingReceipts`); a `/chat` consult renders as a
`.consulted` panel. Orchestrate reuses all of it.

## Tests (fast tier, no model)

- `OrchestrateDirectiveTests`: `build` embeds the task verbatim; renders the
  writable scope (and "the whole workspace" when empty); the text contains
  each required clause (the `dispatch` tool name and its three parameter
  names, "one-shot", "acceptance predicate", "validation", "watched
  interactive").
- `DispatchPreferenceRuleTests`: the text contains "machine-checkable",
  "writable-file set", "watched interactive", "acceptance predicate".
- `CommandRouterTests` already covers `/orchestrate --files` parsing — no
  change.

## Live validation (the closure evidence)

One real-engine run, not a matrix: `/orchestrate` against a small multi-phase
task with a machine-checkable acceptance command (the agentclinic `roadmap`
fixture shape), on the pinned engine + Laguna S. Pass bar: the run
decomposes, dispatches at least one phase to a pool worker, a receipt folds
back, the integrated result validates 13/13, and the transcript shows the
dispatch tool card + receipt rows. Recorded as the P20 closure/verdict doc.
A run that does *not* dispatch is a failure of the directive, not a pass —
this is the behavior the 2026-08-26 spike showed must change.

## Out of scope (descoped, recorded in ROADMAP)

- **small-ctx workers** — its own phase, merged with P23's per-worker think
  control (one engine patch, fork-ledger row #12, golden recapture; depends on
  P22's XS golden recapture).
- **two-phase `/spike`** — Backlog behind P24 (phase 2 rides mediated bash).
