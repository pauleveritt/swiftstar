---
phase: P27
cycle: eval-cli-1a-kit-types
lifecycle: active
---

# `swiftstar-eval` 1a: the pure types

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** The five `SwiftStarKit` value types the eval CLI is built from — the
spawn record, the arm diff that refuses an undeclared difference, the
experiment file, the capture-to-bill reduction, and the report. All pure, all
fast-tier, none of them spawning anything.

**Architecture:** Nothing here touches a process. `SpawnRecord` is the
complete resolved description of one spawn and the only thing the diff
compares; `ArmDiff` turns a difference into a refusal; `EvalExperiment` parses
the committed pre-registration; `PairBill` reduces two capture trees to one
paired delta; `EvalReport` renders. Plans 1b (the CLI and the extraction) and
1c (the bill) build on these.

**Tech Stack:** Swift 6 language mode, SwiftPM, swift-testing, macOS 26+.

**Spec:**
[`2026-08-30-eval-cli-design.md`](../specs/2026-08-30-eval-cli-design.md)

## Global Constraints

- **Plan style is `docs/sdd.md`'s local rule**, overriding
  `superpowers:writing-plans`: files touched, signatures only, and the test
  that proves it (name + assertion, one line). No pasted bodies.
- **Binding rules, from `BRIEF.md`:** (2) every new test is shown to fail
  before it passes — break it, watch it fail, restore; (3) no source-text
  assertions, ever; (4) every refusal test has a sibling success test; (6) the
  diff names the fixture it admitted and the one it refused.
- Fast tier stays process-free and socket-free; the tripwire enforces it.
- Branch `eval-cli`, off `p24-3-run-digest-family`. Baseline: 906 tests green.

---

### Task 1: `SpawnRecord` — every axis that can move

**Files:**
- Create: `Sources/SwiftStarKit/SpawnRecord.swift`
- Create: `Tests/SwiftStarKitTests/SpawnRecordTests.swift`
- Modify: `Sources/SwiftStarKit/CaptureProvenance.swift`

**Interfaces:**
- Produces: `public struct SpawnRecord: Equatable, Sendable, Codable` with, in
  four groups — *engine*: `engineSHA`, `engineDirty: Bool`,
  `engineBinaryHash`; *harness*: `swiftstarSHA`, `swiftstarDirty: Bool`,
  `harnessBinaryHash`; *argv-only settings, each its own field*: `maxTokens`,
  `thinkBudget`, `seed: UInt64`, `systemPromptHash`, `runtimeFlags: [String]`;
  *posture and machine*: `modelPath`, `modelBytes`, `modelHash`, `variantID`,
  `contextSize`, `sampler`, `power`, `thinkPolicy`, `tools: [String]`,
  `shellAllowed`, `hostTools`, `workspace`, `workspaceRef`, `osBuild`,
  `wiredLimitBytes`, `environment: [String: String]` (allowlisted),
  `userDefaults: [String: String]`; *must-differ*: `captureDirectory`,
  `startedAt`, `runIndex`
- Produces: `public static let environmentAllowlist: [String]` including
  `DS4_DIR` and `SUPERPOWERS_SKILLS_DIR`
- Produces: `public static let userDefaultsKeys: [String]` =
  `["dispatchDumb", "sessionCaptureEnabled", "subagentPoolSize"]`
- Produces: `public var provenanceFacts: [CaptureProvenance.Fact]`
- Produces: `public static let mustDifferKeys: Set<String>`
- Produces: `public func differingKeys(from other: SpawnRecord) -> Set<String>`
- Produces: `public func argvElementDiff(from other: SpawnRecord) -> [String]`

- [ ] **Step 1: Write the failing tests**

  - `recordCarriesTheThrottle` — a record from an `AgentSettings` with
    `powerSavingEnabled: true` has `power` equal to
    `AgentCommand.powerRecord(settings:)`. The 2026-08-30 defect, pinned.
  - `recordCarriesHarnessIdentity` — `swiftstarSHA` and `swiftstarDirty` are
    populated and are not the engine's. Without these the record cannot see
    an app-side A/B at all, which is what the motivating failure was.
  - `argvOnlySettingsAreTheirOwnFields` — two records differing only in
    `thinkBudget` return exactly `["thinkBudget"]` from `differingKeys`, not
    an opaque `argv` difference.
  - `differingKeysNamesOnlyWhatChanged` — records differing in `power` alone
    return `["power"]`.
  - `userDefaultsKeysAreRecorded` — a record built with `dispatchDumb: true`
    differs from one built `false`. `dispatchDumb` is read inside the wire
    loop and changes admission behavior, so it is an arm axis.
  - `provenanceFactsRenderPowerAndSampler` — `CaptureProvenance.render` over
    `provenanceFacts` contains both lines.

- [ ] **Step 2: Run them and watch each fail** (`just test`).
- [ ] **Step 3: Implement `SpawnRecord`**; rewire
      `AgentController.renderLiveProvenance` to build facts from a record.
- [ ] **Step 4: `just test`** — 906 + 6 green.
- [ ] **Step 5: Break `differingKeys` to return `[]`, watch
      `differingKeysNamesOnlyWhatChanged` fail, restore.**
- [ ] **Step 6: Commit** — `SpawnRecord: every spawn axis in one comparable record`.

---

### Task 2: `ArmDiff` — the refusal

**Files:**
- Create: `Sources/SwiftStarKit/ArmDiff.swift`
- Create: `Tests/SwiftStarKitTests/ArmDiffTests.swift`

**Interfaces:**
- Consumes: `SpawnRecord.differingKeys(from:)`, `argvElementDiff(from:)`
- Produces: `public enum ArmDiff` with
  `public static func admit(_ a: SpawnRecord, _ b: SpawnRecord,
  variable: String, declaredRefs: (String, String)?)
  -> Result<Set<String>, ArmDiffRefusal>`
- Produces: `public struct ArmDiffRefusal: Error, Equatable` with
  `undeclared: [String]`, `message: String`
- Produces: `public static let engineBuildKeys: Set<String>` =
  `["engineSHA", "engineBinaryHash"]`, admitted **only** when
  `variable == "gitRef"` — and **never** `argv` wholesale

- [ ] **Step 1: Write the failing tests**

  - `admitsWhenOnlyTheDeclaredVariableDiffers` — arms differing only in
    `hostTools` with `variable: "hostTools"` return `.success(["hostTools"])`.
  - `refusesTheUndeclaredThrottle` — arms differing in `hostTools` **and**
    `power` refuse with `undeclared == ["power"]`. The 2026-08-30 failure,
    asserted directly.
  - `gitRefDoesNotAdmitArgvOnlySettings` — two `gitRef` arms differing in
    `engineSHA` **and** `thinkBudget` refuse naming `thinkBudget`. An early
    draft admitted this; the test exists so it cannot come back.
  - `gitRefAdmitsTheBuildKeys` — the sibling: the same pair differing only in
    `engineSHA` and `engineBinaryHash` is admitted.
  - `refusesWhenResolvedShaDoesNotMatchTheDeclaredRef` — an arm declaring ref
    `X` whose resolved `engineSHA` belongs to `Y` refuses.
  - `refusesAnAppSideGitRefExperiment` — arms differing in `swiftstarSHA`
    refuse with a message naming the reason: one harness binary cannot embody
    two harness refs.
  - `admitsTheMustDifferAllowlist` — records differing only in
    `captureDirectory`, `startedAt`, `runIndex` are admitted.
  - `refusesAnUndeclaredContextSize` — a `ctx` difference is refused even when
    every other key matches, showing the allowlist is fixed and not widened.

- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Implement `ArmDiff`.**
- [ ] **Step 4: `just test`** green.
- [ ] **Step 5: Break `admit` to allowlist `argv` wholesale under `gitRef`,
      watch `gitRefDoesNotAdmitArgvOnlySettings` fail, restore.**
- [ ] **Step 6: Commit** — `ArmDiff: refuse an undeclared difference before spawning`.

---

### Task 3: `EvalExperiment` — the committed pre-registration

**Files:**
- Create: `Sources/SwiftStarKit/EvalExperiment.swift`
- Create: `Tests/SwiftStarKitTests/EvalExperimentTests.swift`
- Create: `Tests/SwiftStarKitTests/Fixtures/eval-valid.json`
- Create: `Tests/SwiftStarKitTests/Fixtures/eval-two-variables.json`
- Create: `Tests/SwiftStarKitTests/Fixtures/eval-one-pair.json`

**Interfaces:**
- Produces: `public struct EvalExperiment: Codable, Equatable, Sendable` with
  `name`, `question`, `falsifier`, `variable: String`, `pairs: Int`,
  `mode: EvalMode`, `promptFile: String`, `captureSelection: String`,
  `arms: [Arm]`, `common: [String: EvalValue]`
- Produces: `public enum EvalMode: String, Codable { case bare, chat, quick, orchestrate }`
- Produces: `public static let defaultPairs = 5`, `public static let minimumPairs = 3`
- Produces: `public static func parse(_ data: Data, exploratory: Bool) throws -> EvalExperiment`
- Produces: `public enum EvalExperimentError: Error, Equatable` with
  `multipleVariables([String])`, `tooFewPairs(Int)`, `unknownVariable(String)`,
  `unknownMode(String)`, `seedIsNotAnAxis`
- Produces: `public func runOrder() -> [(pair: Int, armID: String, seed: UInt64)]`
  — ABBA per pair, both arms of a pair sharing one seed, seeds derived
  **deterministically from `name` and the pair index** so the committed file
  fully determines them
- Produces: `public var preregistration: String`

- [ ] **Step 1: Write the failing tests**

  - `parsesTheCommittedFixture` — `eval-valid.json` parses with two arms
    (binding rule 6: the accepted fixture).
  - `refusesTwoVariables` — `eval-two-variables.json` throws
    `multipleVariables(["hostTools","power"])` (the rejected fixture).
  - `refusesFewerThanThreePairs` — `eval-one-pair.json` throws `tooFewPairs(1)`.
  - `exploratoryAdmitsOnePair` — the sibling success for that refusal.
  - `defaultsToFivePairs` — a file omitting `pairs` yields 5.
  - `refusesSeedAsTheVariable` — `seed` cannot be an axis; `runOrder` owns it,
    and letting both set it makes the run order depend on something the file
    also overrides.
  - `runOrderIsABBAAndSeedMatched` — for `pairs: 2` the order is `[c,t,t,c]`
    and pair 1's two entries share a seed while pairs 1 and 2 differ.
  - `runOrderIsDeterministicFromTheFile` — parsing and ordering the same bytes
    twice yields identical seeds.
  - `preregistrationCarriesQuestionAndFalsifier` — both strings appear verbatim.

- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Implement `EvalExperiment`.**
- [ ] **Step 4: `just test`** green.
- [ ] **Step 5: Break `runOrder` to emit ABAB, watch
      `runOrderIsABBAAndSeedMatched` fail, restore.**
- [ ] **Step 6: Commit** — `EvalExperiment: one variable, five pairs, a deterministic order`.

---

### Task 4: `PairBill` — two capture trees to one delta

**Files:**
- Create: `Sources/SwiftStarKit/PairBill.swift`
- Create: `Tests/SwiftStarKitTests/PairBillTests.swift`
- Modify: `Sources/swiftstar-analyze/main.swift:156-158` (the Σsuffix
  computation moves to `PairBill`; the verb calls it)

**Interfaces:**
- Consumes: `TraceParser`, `TurnSpan`, `CaptureUsability.recordsWork`
- Produces: `public struct PairResult: Equatable, Sendable` with `pair: Int`,
  `controlSuffix: Int`, `treatmentSuffix: Int`, `delta: Int`
- Produces: `public enum PairBill` with
  `public static func suffixTotal(trace: String) -> Int` and
  `public static func reduce(pair: Int, control: CaptureTree,
  treatment: CaptureTree) -> Result<PairResult, PairDrop>`
- Produces: `public enum PairDrop: Equatable` with
  `unusable(arm: String, reason: String)` — **a pair is dropped whole**

- [ ] **Step 1: Write the failing tests**

  - `suffixTotalMatchesTheAnalyzerOnACommittedTrace` — the moved computation
    returns the same number the analyzer verb printed before the move, over a
    committed fixture trace named in the test (binding rule 6).
  - `reduceProducesTheDelta` — two fixture trees with known suffix totals give
    `delta == treatment - control`.
  - `oneUnusableArmDropsTheWholePair` — a pair whose control records no work
    returns `.failure(.unusable(arm: "control", ...))` and **no**
    `PairResult`. Keeping the survivor would silently convert a paired design
    into an unpaired one.
  - `bothUsableIsKept` — the sibling success.

- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Move `suffixTotal` and implement `PairBill`.**
- [ ] **Step 4: `just test`** green, and the `diff` verb's output over a
      committed capture is byte-identical to before the move.
- [ ] **Step 5: Break `reduce` to keep the usable arm of a dropped pair, watch
      `oneUnusableArmDropsTheWholePair` fail, restore.**
- [ ] **Step 6: Commit** — `PairBill: the paired delta, computed once`.

---

### Task 5: `EvalReport` — deltas, spread, verdict, no ratio

**Files:**
- Create: `Sources/SwiftStarKit/EvalReport.swift`
- Create: `Tests/SwiftStarKitTests/EvalReportTests.swift`

**Interfaces:**
- Consumes: `EvalExperiment`, `PairResult`, `PairDrop`
- Produces: `public enum FalsifierVerdict: String, Codable
  { case unrecorded, claimSurvives, claimFalsified }` — named by outcome, not
  by whether the falsifier "held," which inverts the polarity of good news
- Produces: `public static func render(_ experiment: EvalExperiment,
  pairs: [PairResult], drops: [PairDrop], verdict: FalsifierVerdict,
  attempt: Int, exploratory: Bool) -> String`
- Produces: `public static func exitCode(for verdict: FalsifierVerdict) -> Int32`

- [ ] **Step 1: Write the failing tests**

  - `reportsEveryPairAndTheSpread` — five pairs render five delta lines plus a
    min/max spread line.
  - `neverPrintsARatio` — over pairs whose deltas would give 2.2x, the
    rendered text matches no `N.Nx` or `N%` formatted figure. Asserted as a
    formatted-number pattern, **not** as "contains no letter x" — `ctx`,
    `max` and hex would false-positive that and the test would be routed
    around rather than obeyed.
  - `statesTheChanceOfAllSameSign` — a report over `n` pairs states the
    one-in-2^(n-1) figure for same-sign deltas by chance, so the reader is not
    left to compute it.
  - `namesEveryDroppedPair` — a drop appears with its arm and reason.
  - `unrecordedVerdictExitsNonZero` — `exitCode(for: .unrecorded) == 2` and
    the report says `VERDICT: unrecorded`.
  - `recordedVerdictExitsZero` — `exitCode(for: .claimSurvives) == 0`.
  - `attemptNumberIsPrinted` — `attempt: 3` renders "attempt 3", so
    run-until-you-like-it leaves a number on the page.
  - `exploratoryStampsEveryClaim` — `NOT A CAUSAL CLAIM` appears.

- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Implement `EvalReport`.**
- [ ] **Step 4: `just test`** green.
- [ ] **Step 5: Break `render` to emit a ratio, watch `neverPrintsARatio`
      fail, restore.**
- [ ] **Step 6: Commit** — `EvalReport: paired deltas and a spread, never a headline ratio`.

## Self-review notes

- **Spec coverage (this plan):** `SpawnRecord`'s four field groups → Task 1.
  Element-wise argv, the `gitRef` build-key carve-out, the declared-ref check
  and the app-side refusal → Task 2. The experiment file, one variable, five
  pairs, deterministic seeds → Task 3. The capture-to-bill step the review
  found ownerless → Task 4. Claim strength, attempt counting, outcome-named
  verdicts → Task 5.
- **Type consistency:** `SpawnRecord` (Task 1) is consumed by Task 2 and by
  plan 1b. `PairResult`/`PairDrop` (Task 4) by Task 5. `EvalExperiment` and
  `FalsifierVerdict` by plan 1b's `experiment` verb.
- **Deliberately not here:** anything that spawns. The engine `--tools` flag,
  the `AgentSession` extraction, the verbs and the worktree-per-run machinery
  are plan 1b; the bill is plan 1c.
