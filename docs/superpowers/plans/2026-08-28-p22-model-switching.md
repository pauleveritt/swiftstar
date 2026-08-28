# P22 Model Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the "Apply this model" action — a toolbar menu action that stops and re-spawns the agent with a newly selected model, VariantGate-admitted before the stop, with the pure switch decision fast-tier tested.

**Architecture:** A pure decision function (`ModelSwitchEvaluator.decide`) in SwiftStarKit (admission × not-generating × model-changed) is the single source of truth; `AgentController.applyModelSelection()` resolves the staged selection exactly as the next spawn would, feeds the decision, and calls the existing `restartAgent()` only on `.apply`; the toolbar `ModelMenu` gains an explicit "Apply this model" item visible while the agent is up. Refusals and no-ops surface as transcript system rows. Everything else (transcript preservation, per-spawn provenance, pool re-spawn) is existing behavior that the live validation *verifies*, not rebuilds.

**Tech Stack:** Swift 6.2, Swift Testing (`swift-testing`), SwiftUI (app target), SwiftPM (`swift-tools-version: 6.2`).

**Spec:** [docs/superpowers/specs/2026-08-28-p22-model-switching-design.md](../specs/2026-08-28-p22-model-switching-design.md) — the plan argues from the spec; executors read both.

## Global Constraints

- Binding rules from the ROADMAP P22 row (non-negotiable, from the spec):
  1. Admission before stop — never kill a working session for an infeasible target.
  2. Refuse mid-generation.
  3. Transcript preserved across the re-spawn.
  4. Provenance per-spawn reflects the new model.
  5. Pool re-spawns with the new model.
- Do **not** touch P25 files or their regions: `VariantRegistry.swift`, `Variant.swift`, `GGUFMetadataReader.swift`, `VariantGate.swift` (the `wiredLimitAdvisoryBytes` region), `VariantAdmissionSource.swift`, `MetalWorkingSet.swift`, `Tests/SwiftStarIntegrationTests/WiredLimitAdmissionIntegrationTests.swift`, `Tests/SwiftStarKitTests/VariantGateTests.swift` additions, `AgentController.swift`'s startAgent admission call (the `wiredLimitAdvisoryBytes:` line). Always reach variants through `VariantRegistry.all`/`resolve`, never a hardcoded list.
- Fast tier = `swift test` (SwiftStarKitTests only; integration suites are gated on `SWIFTSTAR_INTEGRATION=1`). No model/network/subprocess in the fast tier (FastTierGuard tripwire enforces).
- Live tier (real weights) is never in CI — get the user's OK before any GPU run.
- Every commit is atomic (one deliverable). House workflow: committed spec → plan → code per phase → verdict record + GLM review.
- `ROADMAP.md` currently has an uncommitted edit from another session — never stage/commit it.

---

### Task 1: The pure switch decision + fast-tier tests

**Files:**
- Create: `Sources/SwiftStarKit/ModelSwitchDecision.swift`
- Create: `Tests/SwiftStarKitTests/ModelSwitchDecisionTests.swift`

**Interfaces:**
- Consumes: `VariantAdmission` (SwiftStarKit, existing), `VariantMismatch.message`, `FeasibilityReason.message`.
- Produces: `ModelSwitchDecision` (`.apply` / `.noChange` / `.refused(String)`) and `ModelSwitchEvaluator.decide(isGenerating:runningModelFile:targetModelFile:admission:) -> ModelSwitchDecision`. Task 2 consumes these exact names/signatures.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/ModelSwitchDecisionTests.swift`:

```swift
import Foundation
import Testing
@testable import SwiftStarKit

struct ModelSwitchDecisionTests {
    private let running = URL(fileURLWithPath: "/models/laguna-s.gguf")
    private let target = URL(fileURLWithPath: "/models/laguna-xs.gguf")

    @Test func appliesWhenAdmittedChangedIdle() {
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: target,
            admission: .admitted) == .apply)
    }

    @Test func refusedWhileGeneratingEvenWhenAdmittedAndChanged() {
        let decision = ModelSwitchEvaluator.decide(
            isGenerating: true, runningModelFile: running, targetModelFile: target,
            admission: .admitted)
        guard case .refused(let message) = decision else {
            Issue.record("expected refusal, got \(decision)")
            return
        }
        #expect(message.contains("generating"))
    }

    @Test func noChangeWhenSameModelFile() {
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: running,
            admission: .admitted) == .noChange)
    }

    @Test func noChangeWhenSameModelFileRegardlessOfAdmission() {
        let reason = FeasibilityReason(
            message: "needs 12.0 GiB but only 6.0 GiB available",
            deficitBytes: 1, availableBytes: 1, plannedBytes: 2)
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: running,
            admission: .infeasible(reason)) == .noChange)
    }

    @Test func appliesForCustomPathWithNilAdmission() {
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: target,
            admission: nil) == .apply)
    }

    @Test func refusedWithContractMismatchMessages() {
        let mismatches: [VariantMismatch] = [
            .architecture(expected: "laguna", actual: "mellum"),
            .rope(expected: "scalingType=yarn freqBase=500000.0", actual: "scalingType=nope freqBase=1.0"),
        ]
        let decision = ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: target,
            admission: .contractMismatch(mismatches))
        guard case .refused(let message) = decision else {
            Issue.record("expected refusal, got \(decision)")
            return
        }
        #expect(message.contains("architecture mismatch"))
        #expect(message.contains("rope mismatch"))
    }

    @Test func refusedWithFeasibilityMessage() {
        let reason = FeasibilityReason(
            message: "needs 12.0 GiB but only 6.0 GiB available",
            deficitBytes: 1, availableBytes: 1, plannedBytes: 2)
        let decision = ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: target,
            admission: .infeasible(reason))
        #expect(decision == .refused("needs 12.0 GiB but only 6.0 GiB available"))
    }

    @Test func sameFileDifferentPathSpellingIsNoChange() {
        let spelled = URL(fileURLWithPath: "/models/../models/laguna-s.gguf")
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: spelled, targetModelFile: running,
            admission: .admitted) == .noChange)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ModelSwitchDecisionTests`
Expected: build failure — `cannot find 'ModelSwitchEvaluator' in scope` (the tests exist; the type does not). A compile failure is a valid red.

- [ ] **Step 3: Write the minimal implementation**

`Sources/SwiftStarKit/ModelSwitchDecision.swift` (exactly from the spec §Components.1):

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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ModelSwitchDecisionTests`
Expected: 8 tests, all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/ModelSwitchDecision.swift Tests/SwiftStarKitTests/ModelSwitchDecisionTests.swift
git commit -m "P22 model switching: pure switch decision + fast-tier tests"
```

---

### Task 2: The controller wiring — `applyModelSelection()`

**Files:**
- Modify: `Sources/SwiftStar/AgentController.swift` (add a method immediately after `restartAgent()`, around line ~1130; do not touch the `startAgent()` admission call at line ~303 — that region carries the other session's P25 4b line)

**Interfaces:**
- Consumes: `ModelSwitchEvaluator.decide` + `ModelSwitchDecision` (Task 1), `AgentDefaultSettings.resolve`, `VariantResolver.resolveVariant`, `VariantGate.admit(_:contextSize:availableBytes:wiredLimitAdvisoryBytes:)`, `VariantAdmissionSource.availableBytes()` / `.wiredLimitAdvisoryBytes()`, `AgentController.effectiveSelectedVariantID()`, `AgentController.projectRoot()`, `restartAgent()`, `transcript.appendSystem(_:)`.
- Produces: `AgentController.applyModelSelection()` — Task 3's `onApply` closure calls it.

- [ ] **Step 1: Add the method**

Insert after the closing brace of `restartAgent()` (and before `orchestrate(task:writableFiles:)`):

```swift
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
        let variant = VariantResolver.resolveVariant(
            selectedVariantID: AgentController.effectiveSelectedVariantID())
        let admission: VariantAdmission? = variant.map {
            VariantGate.admit(
                $0, contextSize: targetSettings.contextSize,
                availableBytes: VariantAdmissionSource.availableBytes(),
                wiredLimitAdvisoryBytes: VariantAdmissionSource.wiredLimitAdvisoryBytes())
        }
        switch ModelSwitchEvaluator.decide(
            isGenerating: isGenerating,
            runningModelFile: settings.modelPath,
            targetModelFile: targetSettings.modelPath,
            admission: admission
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

- [ ] **Step 2: Build the app target to verify it compiles**

Run: `swift build --target SwiftStar`
Expected: build succeeds, exit 0. (The app target has no test target — the decision logic is already pinned by Task 1's tests; this step verifies the thin wiring compiles.)

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftStar/AgentController.swift
git commit -m "P22 model switching: applyModelSelection wiring (gate → decision → restart)"
```

---

### Task 3: The toolbar "Apply this model" item

**Files:**
- Modify: `Sources/SwiftStar/AgentView.swift` — `AgentView`'s `ToolbarItem(id: "model")` call site and the `ModelMenu` struct at the bottom of the file

**Interfaces:**
- Consumes: `AgentController.isUp` (existing), `AgentController.applyModelSelection()` (Task 2).
- Produces: the menu's `isUp` + `onApply` inputs; nothing else consumes them.

- [ ] **Step 1: Wire the new inputs at the call site**

Change the toolbar item in `AgentView.body`:

```swift
            ToolbarItem(id: "model", placement: .automatic) {
                ModelMenu(isGenerating: controller.isGenerating)
            }
```

to:

```swift
            ToolbarItem(id: "model", placement: .automatic) {
                ModelMenu(
                    isGenerating: controller.isGenerating,
                    isUp: controller.isUp,
                    onApply: { controller.applyModelSelection() })
            }
```

- [ ] **Step 2: Extend `ModelMenu`**

Change the struct declaration and body:

```swift
struct ModelMenu: View {
    @AppStorage("selectedVariantID") private var selectedVariantID = ""
    @AppStorage("modelPath") private var modelPath = ""
    var isGenerating: Bool
    /// The agent is up (ready or generating) — a live session exists to switch.
    var isUp: Bool
    /// Runs `AgentController.applyModelSelection()`: the pure decision gates
    /// the stop; refusals/no-ops surface as transcript system rows.
    var onApply: () -> Void

    var body: some View {
        Menu {
            ForEach(ModelChoice.list(variants: VariantRegistry.all)) { choice in
                Button(choice.label) {
                    switch choice.id {
                    case ModelChoice.defaultID:
                        selectedVariantID = ""
                        modelPath = ""
                    case ModelChoice.customID:
                        selectedVariantID = ""
                    default:
                        selectedVariantID = choice.id
                    }
                }
            }
            if isUp {
                Divider()
                Button("Apply this model") { onApply() }
            }
        } label: {
            Label(currentLabel, systemImage: "cpu")
        }
        .disabled(isGenerating)
        .help(isGenerating
            ? "Model switching is disabled while generating"
            : "Pick a model for the next session, or choose Apply this model to switch the running session now.")
    }
```

(Leave `currentLabel` and the resolution logic untouched.)

- [ ] **Step 3: Build the app target to verify it compiles**

Run: `swift build --target SwiftStar`
Expected: build succeeds, exit 0.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftStar/AgentView.swift
git commit -m "P22 model switching: toolbar 'Apply this model' action"
```

---

### Task 4: Full fast-tier gate

**Files:** none (verification only).

- [ ] **Step 1: Run the full fast tier**

Run: `swift test`
Expected: all suites PASS (baseline was green at the P25 commits; the delta is the 8 new `ModelSwitchDecisionTests`). Note the count and record it.

- [ ] **Step 2: Confirm no tripwire hits and no P25-region clobbering**

Run: `git diff HEAD~3 --stat` and inspect the diff for the three commits; confirm no changes to `VariantRegistry.swift`, `Variant.swift`, `GGUFMetadataReader.swift`, `VariantGate.swift`, `VariantAdmissionSource.swift`, `MetalWorkingSet.swift`, or the `startAgent()` admission call.

- [ ] **Step 3: Commit any stragglers (there should be none)**

If `git status` shows only the other session's `ROADMAP.md` edit and the untracked findings doc, do nothing — never stage those.

---

### Task 5: Live validation (gated — user's GPU OK required)

**Files:** `docs/superpowers/research/2026-08-28-p22-model-switching-live-validation.md` (new, the evidence record)

> STOP before this task and get the user's explicit OK: this spawns real agents on the pinned engine with real weights (Laguna S ~46 GiB, Laguna XS ~15 GiB) on the user's GPU machine.

- [ ] **Step 1: The real switch (Laguna S → XS)**

1. Launch the app (or run the agent through the app's surface); confirm ready on Laguna S; verify `captures/live/<ts>/provenance.md` names the Laguna S file.
2. Hold a short conversation (≥2 user turns) so the transcript has content.
3. Toolbar → pick "Laguna XS 2.1" → "Apply this model".
4. Verify, and record in the evidence doc:
   - agent stops and re-spawns; state reaches `.ready`;
   - all pre-switch transcript rows still present (binding rule 3);
   - the new spawn's capture `provenance.md` shows `laguna-xs-2.1-RoutedQ3_K-biased.gguf` (rule 4);
   - the memory ring's `lastPlannedModel` is the XS file name, and the new spawn argv carries `--subagent-pool N` with the XS model path (rule 5);
   - one more turn; its `TurnOutcome.model` (outcomes.ndjson) is the XS file name.

- [ ] **Step 2: One refused switch (the session survives)**

1. Stage a target whose admission refuses (deterministic lever: e.g., context size set above the target variant's `maxContext` → `.contractMismatch(.unsupportedContext)`, or a variant whose budget exceeds the Metal ceiling → `.infeasible`).
2. Apply; verify a readable refusal lands as a transcript system row and the session is untouched: state still `.ready`, transcript intact, no stop (rule 1: never kill a working session for an infeasible target).

- [ ] **Step 3: Write the evidence record and commit**

Write `docs/superpowers/research/2026-08-28-p22-model-switching-live-validation.md` (house shape: date, what ran, per-check evidence with paths, verdict). Commit:

```bash
git add docs/superpowers/research/2026-08-28-p22-model-switching-live-validation.md
git commit -m "P22: model switching live validation record"
```

---

### Task 6: Close — verdict record + GLM review

**Files:**
- Create: `docs/superpowers/research/2026-08-28-p22-model-switching-verdict.md`
- Modify: `ROADMAP.md` P22 row (append the forward-item closure — this is the *one* authorized ROADMAP edit; merge around the other session's uncommitted edit without staging it wholesale: stage only the P22 row hunk)

- [ ] **Step 1: Write the verdict record**

House shape (see `2026-08-27-p20-closure-verdict.md`): date, what shipped (commits), binding-rule checklist (1–5, each with its evidence), test counts, live evidence paths, remaining open items (XS recapture, SSD line — unchanged), decision history.

- [ ] **Step 2: Update the ROADMAP P22 row**

Move "model switching" from the row's Forward list to the shipped text, pointing at the spec + verdict. Stage only the P22 row hunk (`git add -p ROADMAP.md`) so the other session's edits stay uncommitted.

- [ ] **Step 3: GLM 5.3 review**

Per `~/.pi/agent/AGENTS.md`: fill the `requesting-code-review` template (`code-reviewer.md`) with DESCRIPTION (the apply action + pure decision), the spec link, BASE_SHA (the commit before Task 1) and HEAD_SHA; write to `/tmp/review-prompt.md`; send via:

```bash
pi -p --no-session --no-extensions --no-skills -nc \
  --provider openrouter-curated --model z-ai/glm-5.3 \
  --thinking low --exclude-tools write,edit \
  "$(cat /tmp/review-prompt.md)"
```

Apply findings per the skill: Critical immediately, Important before proceeding, note Minor for later, push back with reasoning when wrong.

- [ ] **Step 4: Commit the verdict + ROADMAP + any review fixes**

```bash
git add docs/superpowers/research/2026-08-28-p22-model-switching-verdict.md
git add -p ROADMAP.md   # P22 row hunk only
git commit -m "P22: model switching closed (verdict + GLM review)"
```

---

## Self-review (run before handing off)

**Spec coverage:** every binding rule maps to a task — admission-before-stop (Task 2 wiring + Task 1 test 6/7 + Task 5 step 2), refuse-mid-generation (Task 1 test 2 + Task 3 `.disabled(isGenerating)`), transcript-preserved (Task 5 step 1 check 2), provenance-per-spawn (Task 5 step 1 check 3), pool-re-spawn (Task 5 step 1 check 4). Custom-path trust level (D5) → Task 1 test 5. Explicit action, not pick-implies-apply (D3) → Task 3.

**Placeholder scan:** no TBDs; every code step carries its exact source. Task 5's refusal lever is deliberately left open ("pinned at execution") because the *working* lever depends on live machine facts — the spec's live-validation section says the same, and Step 2 gives the two candidate levers.

**Type consistency:** `ModelSwitchDecision` / `ModelSwitchEvaluator.decide(isGenerating:runningModelFile:targetModelFile:admission:)` is spelled identically in Task 1's implementation, Task 2's wiring, and the spec. `applyModelSelection()` is produced in Task 2 and consumed in Task 3. `VariantAdmission?` (nil for custom) is consistent across all three.
