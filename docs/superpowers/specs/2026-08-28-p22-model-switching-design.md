# SwiftStar P22 design: model switching ("Apply this model")

**Date:** 2026-08-28
**Status:** proposed
**Phase:** P22 — More models: Laguna XS + model switching (model-switching arm)

This spec is the authority on P22's model-switching forward item: the "Apply
this model" action that stops and re-spawns the agent with a newly selected
model, feasibility-/VariantGate-admitted **before** the stop. It implements
the binding rules already fixed in the ROADMAP P22 row; nothing here re-opens
them.

**Branch check (2026-08-28, per the handoff brief):** the
`p13-laguna-xs-variant` branch's spec
(`docs/superpowers/specs/2026-08-26-p13-laguna-xs-variant-design.md`) covers
only the Laguna XS variant arm — the preset, the typed engine-flag wiring, the
acceptance run. It does **not** design model switching (its "Out" section does
not mention it). This is the first model-switching design in the repo.

P22's other two forward items — **XS golden recapture** and **SSD across the
Laguna line** — are separate work streams with their own evidence paths (both
need a live run on the pinned engine; user GPU OK required first). They are out
of scope here and stay recorded in the ROADMAP P22 row.

## Problem

The toolbar model menu (P19.1 D4) persists a model choice that applies at the
*next* spawn. The agent runs until "End session"; there is no Start button on
the main surface (P19.1 D4: "No Start/Stop Agent buttons; single 'End
session'; engine stops at quit"). So switching models today means: pick a new
model → End session → restart the app (or reach the Settings escape hatch) —
and nothing checks whether the new model can even load on this machine before
the working session is torn down.

What already exists (verified by direct read, 2026-08-28 — do not rebuild):

- **`ModelMenu`** (`Sources/SwiftStar/AgentView.swift`): the toolbar menu
  derives from `ModelChoice.list(variants: VariantRegistry.all)` (+ custom
  escape); persists `selectedVariantID`/`modelPath` via `@AppStorage`;
  `.disabled(isGenerating)`; idle help text "Model switching lands with P22".
- **`AgentController.restartAgent()`**: generic stop → wait for `.stopped` →
  start. `startAgent()` refreshes `settings` from
  `AgentDefaultSettings.resolve` (which resolves the staged model, clamps
  context to the selected variant's declared range, and carries the variant's
  `runtime` engine flags), then admits the resolved variant via
  `VariantGate.admit` before spawn (C1).
- **`VariantGate.admit(_:contextSize:availableBytes:wiredLimitAdvisoryBytes:)`**:
  the single admission entry point shared by the app and the harness
  (`swiftstar-agenttest`) — metadata read → contract verify → memory check.
  Pure; returns `VariantAdmission` (`.admitted` / `.contractMismatch` /
  `.infeasible`).
- **Transcript preservation** is existing behavior: `startAgent()` never
  resets `transcript` ("The transcript is deliberately kept (history, like
  EngineController)"). To be *verified*, not built.
- **Per-spawn provenance** (`provenance.md` in a timestamped
  `captures/live/<ts>` dir) and per-turn `TurnOutcome.model` both key off
  `settings.modelPath.lastPathComponent`; `settings` is refreshed at each
  `startAgent()`, so a re-spawn with a new model records the new model
  automatically. To be *verified*, not built.
- **Pool re-spawn** with the new model: the `--subagent-pool N` argv is built
  from the refreshed `settings` (`AgentCommand.argv`). Automatic. To be
  *verified*, not built.

What is missing: the apply action itself — the wiring (gate → refuse-if-
infeasible/mid-generation → stop → re-spawn) and a testable pure decision
function.

## Binding rules (ROADMAP P22 row; authoritative, not re-openable)

1. **Admission before stop** — `VariantGate.admit(targetVariant, contextSize,
   availableBytes)` runs before any stop; refuse with a readable reason if the
   target is infeasible. Never kill a working session to switch to an
   infeasible model.
2. **Refuse mid-generation** — a switch while generating is refused.
3. **Transcript preserved** — the conversation survives the re-spawn.
4. **Provenance per-spawn reflects the new model** — TurnOutcome/capture key
   off `settings.modelPath.lastPathComponent`.
5. **Pool re-spawns with the new model** — automatic via
   `settings.modelPath` in the spawn argv.

## Scope (strict)

**In:**

1. `ModelSwitchEvaluator` — the pure switch decision (SwiftStarKit; fast-tier
   tested).
2. `AgentController.applyModelSelection()` — the wiring: resolve staged
   selection → admission → decision → stop + re-spawn (or refuse / no-op).
3. The "Apply this model" action in the toolbar `ModelMenu` (visible when the
   agent is up; the menu stays disabled mid-generation) + updated idle help
   text.
4. Fast-tier tests for the pure decision (admission × not-generating ×
   model-changed).
5. Live validation: one real switch (Laguna S → XS) and one refused switch,
   with transcript + provenance + pool checked. **User GPU OK required before
   any live run.**

**Out (explicit):**

- XS golden recapture (separate forward item; needs a live run on the pinned
  engine).
- SSD across the Laguna line (separate forward item; engine patch `2613723` →
  divergence row → recapture → `laguna-s-2.1` variant).
- 16 GB hardware acceptance (skipped by decision 2026-08-27; never scheduled).
- Changing context/workspace/shell mid-session (Settings changes still apply
  at next start — P19.1 D3's defaults-vs-active split is unchanged).
- Any auto-apply-on-pick behavior (rejected in D3).

## Design decisions

**D1 — The decision is a pure function in SwiftStarKit.**
`ModelSwitchEvaluator.decide(isGenerating:runningModelFile:targetModelFile:admission:)`
returns a `ModelSwitchDecision` (`.apply` / `.noChange` / `.refused(reason)`).
It takes the *admission result*, not raw memory bytes, so tests feed synthetic
admissions without touching Metal; the live bytes come from the existing
`VariantAdmissionSource` seam (`availableBytes()` /
`wiredLimitAdvisoryBytes()`, P25 Cycle 4b). Check order — generating →
same-model → admission — is documented and pinned by tests.

**D2 — The target is resolved exactly as the next spawn would resolve it.**
`applyModelSelection()` calls `AgentDefaultSettings.resolve` — the same call
`startAgent()`'s `defaultSettings()` makes — so the gate sees the context the
re-spawn will actually run (clamped to the target variant's declared range)
and the variant's `runtime` flags travel with it. One resolution path, no
second copy that could disagree (the failure mode P19.1 D4's own comment warns
about: a stale `selectedVariantID` used to fall to a hardcoded "Laguna S"
while the session launched something else entirely).

**D3 — "Apply this model" is an explicit menu item; pick ≠ apply.** Picking a
model keeps today's semantics (persist → applies at next spawn); the Apply
item commits the staged choice now. Rejected alternative — selection = apply
when idle — because an admission refusal after a pick would require reverting
the persisted selection, and an accidental pick would kill a working session
for no reason. With an explicit action, a refusal leaves the selection staged
and visible, and the same gate governs the next manual start.

**D4 — The menu item is visible whenever the agent is up; the decision
function is the single source of truth.** The item always reads "Apply this
model" — no staged-vs-running pre-check in the view, because hiding the item
would add a second resolution path that can disagree with the decision
function. `.noChange` and `.refused` surface as transcript system rows (the
same channel `/orchestrate` refusals use).

**D5 — Custom-file targets skip the gate, matching the fresh-launch
contract.** The Settings caption: "A selected variant is verified before
launch; a custom file is not." `startAgent()` admits only resolved variants; a
custom `modelPath` is spawned unverified. The switch treats custom identically
(`admission` nil → apply) — the user's explicit choice, same trust level as a
fresh launch with that path. The mid-generation and same-model rules still
apply.

**D6 — The menu stays `.disabled(isGenerating)`; the pure rule is defense in
depth.** The UI cannot fire a switch mid-generation, but the decision function
still encodes the rule and the tests pin it — a future caller cannot bypass
it.

## Components

### 1. `Sources/SwiftStarKit/ModelSwitchDecision.swift` (new)

```swift
import Foundation

/// The result of the model-switch decision (P22).
public enum ModelSwitchDecision: Equatable, Sendable {
    /// Stop the current session and re-spawn with the target model.
    case apply
    /// The target resolves to the model already running — nothing to do.
    case noChange
    /// Refuse the switch; the current session is untouched.
    case refused(String)
}

/// The pure switch decision (P22): admission × not-generating × model-changed.
/// `admission` is nil for a custom/unverified model file — treated like the
/// fresh-launch path, which also skips the gate (Settings contract: "a
/// selected variant is verified before launch; a custom file is not").
public enum ModelSwitchEvaluator {
    public static func decide(
        isGenerating: Bool,
        runningModelFile: URL,
        targetModelFile: URL,
        admission: VariantAdmission?
    ) -> ModelSwitchDecision {
        if isGenerating {
            return .refused("Model switching is refused while the agent is generating.")
        }
        if runningModelFile.standardizedFileURL == targetModelFile.standardizedFileURL {
            return .noChange
        }
        switch admission {
        case nil, .admitted:
            return .apply
        case .contractMismatch(let mismatches):
            return .refused(mismatches.map(\.message).joined(separator: "\n"))
        case .infeasible(let reason):
            return .refused(reason.message)
        }
    }
}
```

### 2. `AgentController.applyModelSelection()` + `admitStagedVariant(contextSize:)` (SwiftStar target, near `restartAgent`)

A private static helper shares the resolve → `VariantGate.admit` block with
`startAgent()`'s pre-spawn admission — two near-copies of the same steps would
drift about which variant is in play or which live memory facts back the gate
(the failure mode `effectiveSelectedVariantID()`'s own doc warns about;
GLM 5.3 review finding, folded in 2026-08-28):

```swift
/// The admission result for the staged variant at the given context, or
/// nil when no variant is staged (a custom/unverified model path — like a
/// fresh launch, no gate exists for it). Shared by `startAgent()` and
/// `applyModelSelection()` so the two call sites cannot drift about which
/// variant is in play or which live memory facts back the gate (P22 D2;
/// the failure mode `effectiveSelectedVariantID`'s own doc warns about).
private static func admitStagedVariant(contextSize: Int) -> VariantAdmission? {
    guard let variant = VariantResolver.resolveVariant(
        selectedVariantID: AgentController.effectiveSelectedVariantID()) else { return nil }
    return VariantGate.admit(
        variant, contextSize: contextSize,
        availableBytes: VariantAdmissionSource.availableBytes(),
        wiredLimitAdvisoryBytes: VariantAdmissionSource.wiredLimitAdvisoryBytes())
}

/// P22 model switching — the "Apply this model" action. Resolves the staged
/// selection exactly as the next spawn would, runs the pure switch decision
/// (admission × generating × changed), and stops + re-spawns only when the
/// decision says apply. Refusals and no-ops surface as transcript system
/// rows; a working session is never killed for an infeasible target (the
/// admission gate runs before any stop).
func applyModelSelection() {
    let targetSettings = AgentDefaultSettings.resolve(
        defaults: .standard,
        environment: ProcessInfo.processInfo.environment,
        projectRoot: AgentController.projectRoot())
    switch ModelSwitchEvaluator.decide(
        isGenerating: isGenerating,
        runningModelFile: settings.modelPath,
        targetModelFile: targetSettings.modelPath,
        admission: AgentController.admitStagedVariant(contextSize: targetSettings.contextSize)
    ) {
    case .apply:
        restartAgent()
    case .noChange:
        transcript.appendSystem(
            "→ apply model: already running \(targetSettings.modelPath.lastPathComponent)")
    case .refused(let reason):
        transcript.appendSystem("→ apply model refused: \(reason)")
    }
}
```

`startAgent()`'s admission block reduces to the same helper (its refusals set
`.failed` state and log; `applyModelSelection()`'s surface as transcript rows —
the only divergence is the outcome handling, which the helper deliberately does
not share).

### 3. Toolbar `ModelMenu` (`Sources/SwiftStar/AgentView.swift`)

- New inputs: `isUp: Bool` (from `controller.isUp`) and
  `onApply: () -> Void` (`{ controller.applyModelSelection() }`); the menu
  keeps its existing `@AppStorage` selection state.
- Menu body: the existing choice buttons; when `isUp`, a `Divider()` then
  `Button("Apply this model") { onApply() }`.
- Idle help text changes from "Model switching lands with P22" to copy that
  describes the apply action (exact wording finalized at implementation; the
  mid-generation help string is unchanged).

## Surfacing

- `.refused` / `.noChange` → `transcript.appendSystem("→ apply model …")`
  (system rows render as small tertiary text — the established channel for
  `/orchestrate` refusals).
- `.apply` → `restartAgent()`. The toolbar's End-session semantics and the
  Settings Start/Restart escape hatch are untouched.

## Tests (fast tier, no model)

`Tests/SwiftStarKitTests/ModelSwitchDecisionTests.swift`:

1. `refusedWhileGeneratingEvenWhenAdmittedAndChanged`
2. `noChangeWhenSameModelFile` (admitted, not generating)
3. `noChangeWhenSameModelFileRegardlessOfAdmission` (an infeasible admission
   on the already-running model is still `.noChange` — nothing would change,
   and the refusal would claim the running session is unsafe)
4. `appliesWhenAdmittedChangedIdle`
5. `appliesForCustomPathWithNilAdmission` (documented trust level)
6. `refusedWithContractMismatchMessages` (messages joined with "\n")
7. `refusedWithFeasibilityMessage` (`reason.message`)
8. `sameFileDifferentPathSpellingIsNoChange` (`standardizedFileURL`)
9. `noChangeWhenSameModelFileRegardlessOfContractMismatch` (GLM 5.3 review
   gap, folded in 2026-08-28 — the analog of #3 for a mismatch admission)

## Live validation (closure evidence; GPU OK required first)

**One real switch, Laguna S → XS, on the pinned engine:**

1. Start the app; confirm the agent is ready on Laguna S — the spawn's
   `captures/live/<ts>/provenance.md` shows the Laguna S file name.
2. Hold a short conversation (≥2 user turns) so the transcript has content.
3. Toolbar → pick "Laguna XS 2.1" → "Apply this model".
4. Verify: the agent stops and re-spawns; the step-2 transcript rows are still
   present (rule 3); the new spawn's capture provenance shows
   `laguna-xs-2.1-RoutedQ3_K-biased.gguf` (rule 4); the memory ring's
   `lastPlannedModel` and the pool argv (`--subagent-pool`, XS model path)
   belong to the new spawn (rule 5); the next turn's `TurnOutcome.model` is
   the XS file name.

**One refused switch (the session survives):**

1. Stage a target whose admission refuses (deterministic lever pinned at
   execution — e.g., a context the target's budget/range refuses).
2. Apply; verify a readable refusal lands as a transcript system row and the
   running session is untouched (state stays `.ready`, transcript intact) —
   rule 1.

The fast tier has no model/network/subprocess; the live run is the only
real-engine step and is never in CI.

## Out of scope (descoped, recorded in ROADMAP)

- **XS golden recapture** and **SSD across the Laguna line** — the P22 row's
  items 2 and 3; their evidence paths and status live in the ROADMAP row and
  the [acceptance verdict](../research/2026-08-27-p22-laguna-xs-acceptance-verdict.md).
- The P25 dependency the handoff brief flagged **no longer exists**:
  `deepseek-v4-flash` landed with P25 (2026-08-28) and is a registry variant
  like any other, so switching to it rides this same path; its 91 GiB load is
  still gated by the same admission math.
