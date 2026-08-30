# `swiftstar-eval` cycle 1a: the CLI

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** One CLI that runs an ad-hoc prompt, a `/chat`, or a `/quick` through
the app's own spawn path and refuses an experiment whose arms differ by
anything undeclared. Running the P24.3 bill is cycle 1b's plan
([`2026-08-30-eval-cli-p24-3-bill.md`](2026-08-30-eval-cli-p24-3-bill.md)) —
split out because one plan for both broke `docs/sdd.md`'s 400-line ceiling.

**Architecture:** Extract the app's turn loop into a SwiftUI-free
`AgentSession` in `SwiftStarAppKit` so an eval and the app cannot diverge
without failing to compile. Above it, three pure `SwiftStarKit` types —
`SpawnRecord`, `EvalExperiment`, `EvalReport` — carry the pre-registration,
the arm diff and the report. `swiftstar-eval` absorbs `swiftstar-drive` and
`swiftstar-analyze`; `swiftstar-agenttest` is cycle 2.

**Tech Stack:** Swift 6 language mode, SwiftPM, swift-testing, macOS 26+.

**Spec:**
[`2026-08-30-eval-cli-design.md`](../specs/2026-08-30-eval-cli-design.md)

## Global Constraints

- **Plan style is `docs/sdd.md`'s local rule**, overriding
  `superpowers:writing-plans`: files touched, signatures only, and the test
  that proves it (name + assertion, one line). No pasted bodies.
- **Binding rules, verbatim from `BRIEF.md`:** (2) every new test is shown to
  fail before it passes — break it, watch it fail, restore; (3) no
  source-text assertions, ever; (4) every refusal test has a sibling success
  test; (5) the capture is written to disk before anything reads it; (6) the
  arm diff names the fixture it admitted and the one it refused.
- Fast tier stays process-free and socket-free; the tripwire enforces it.
- Branch `eval-cli`, off `p24-3-run-digest-family`. Baseline: 906 tests green.

---

### Task 1: `SpawnRecord` — the complete resolved description of one spawn

**Files:**
- Create: `Sources/SwiftStarKit/SpawnRecord.swift`
- Create: `Tests/SwiftStarKitTests/SpawnRecordTests.swift`
- Modify: `Sources/SwiftStarKit/CaptureProvenance.swift` (render from a record)

**Interfaces:**
- Produces: `public struct SpawnRecord: Equatable, Sendable, Codable` with
  `argv: [String]`, `engineSHA: String`, `modelPath: String`,
  `modelBytes: Int`, `variantID: String?`, `sampler: String`, `power: String`,
  `thinkPolicy: String`, `tools: [String]`, `workspace: String`,
  `shellAllowed: Bool`, `hostTools: Bool`, `contextSize: Int`,
  `seed: UInt64`, `osBuild: String`, `wiredLimitBytes: Int`,
  `captureDirectory: String`, `startedAt: Date`, `runIndex: Int`
- Produces: `public static func from(settings: AgentSettings, engineSHA: String,
  tools: [String], osBuild: String, wiredLimitBytes: Int,
  captureDirectory: URL, startedAt: Date, runIndex: Int) -> SpawnRecord`
- Produces: `public var provenanceFacts: [CaptureProvenance.Fact]`
- Produces: `public static let mustDifferKeys: Set<String>` =
  `["captureDirectory", "startedAt", "runIndex"]`
- Produces: `public func differingKeys(from other: SpawnRecord) -> Set<String>`

- [ ] **Step 1: Write the failing tests**

  - `recordCarriesEveryArgvSetting` — a record built from an `AgentSettings`
    with `powerSavingEnabled: true` has `power` equal to
    `AgentCommand.powerRecord(settings:)`, asserting the throttle is in the
    record rather than lost as it was on 2026-08-30.
  - `differingKeysNamesOnlyWhatChanged` — two records identical but for
    `power` return exactly `["power"]`.
  - `differingKeysIgnoresNothingByDefault` — two records differing in
    `captureDirectory` return `["captureDirectory"]`; the must-differ
    allowlist is applied by the diff (Task 2), not hidden inside the record.
  - `provenanceFactsRoundTripThroughRender` — `CaptureProvenance.render` over
    `provenanceFacts` contains the `power` and `sampler` lines.

- [ ] **Step 2: Run them and watch each fail** (`just test`).
- [ ] **Step 3: Implement `SpawnRecord`**; rewire
      `AgentController.renderLiveProvenance` to build facts from a record.
- [ ] **Step 4: `just test`** — 906 + 4 green.
- [ ] **Step 5: Break `differingKeys` to return `[]`, watch
      `differingKeysNamesOnlyWhatChanged` fail, restore.**
- [ ] **Step 6: Commit** — `SpawnRecord: every spawn setting in one comparable record`.

---

### Task 2: The arm diff — a refusal, not a report

**Files:**
- Create: `Sources/SwiftStarKit/ArmDiff.swift`
- Create: `Tests/SwiftStarKitTests/ArmDiffTests.swift`

**Interfaces:**
- Consumes: `SpawnRecord.differingKeys(from:)`, `SpawnRecord.mustDifferKeys`
- Produces: `public enum ArmDiff` with
  `public static func admit(_ a: SpawnRecord, _ b: SpawnRecord, variable: String)
  -> Result<Set<String>, ArmDiffRefusal>`
- Produces: `public struct ArmDiffRefusal: Error, Equatable` with
  `undeclared: [String]`, `message: String`
- Produces: `public static let gitRefDownstreamKeys: Set<String>` =
  `["engineSHA", "argv"]`, admitted **only** when `variable == "gitRef"`

- [ ] **Step 1: Write the failing tests**

  - `admitsWhenOnlyTheDeclaredVariableDiffers` — arms differing only in
    `tools` with `variable: "tools"` return `.success(["tools"])`.
  - `refusesTheUndeclaredThrottle` — arms differing in `tools` **and** `power`
    with `variable: "tools"` refuse, and `undeclared == ["power"]`. This is
    the 2026-08-30 failure, asserted directly.
  - `admitsTheMustDifferAllowlist` — arms differing in `captureDirectory`,
    `startedAt` and `runIndex` alone are admitted.
  - `gitRefAdmitsEngineShaAndArgvOnlyForGitRef` — arms differing in `gitRef`,
    `engineSHA` and `argv` are admitted with `variable: "gitRef"`; the same
    pair with `variable: "tools"` refuses naming `engineSHA`.
  - `allowlistIsNotConfigurable` — `mustDifferKeys` is a `let`; a record
    differing in `ctx` is refused even when every other key matches.

- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Implement `ArmDiff`.**
- [ ] **Step 4: `just test`** green.
- [ ] **Step 5: Break `admit` to always succeed, watch
      `refusesTheUndeclaredThrottle` fail, restore.**
- [ ] **Step 6: Commit** — `ArmDiff: refuse an undeclared difference before spawning`.

---

### Task 3: `EvalExperiment` — the file, its validation, the run order

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
- Produces: `public static func parse(_ data: Data, exploratory: Bool) throws -> EvalExperiment`
- Produces: `public enum EvalExperimentError: Error, Equatable` with cases
  `multipleVariables([String])`, `tooFewPairs(Int)`, `unknownVariable(String)`,
  `unknownMode(String)`
- Produces: `public func runOrder() -> [(pair: Int, armID: String, seed: UInt64)]`
  emitting ABBA per pair, both arms of a pair sharing one seed
- Produces: `public var preregistration: String` (the `question` + `falsifier`
  block copied into the results directory)

- [ ] **Step 1: Write the failing tests**

  - `parsesTheCommittedFixture` — `eval-valid.json` parses with two arms and
    `variable == "tools"` (binding rule 6: this is the accepted fixture).
  - `refusesTwoVariables` — `eval-two-variables.json`, whose arms differ in
    both `tools` and `power`, throws `multipleVariables(["power","tools"])`
    (binding rule 6: the rejected fixture).
  - `refusesFewerThanThreePairs` — `eval-one-pair.json` throws
    `tooFewPairs(1)`.
  - `exploratoryAdmitsOnePair` — the same fixture with `exploratory: true`
    parses (the sibling success test for the refusal above).
  - `runOrderIsABBAAndSeedMatched` — for `pairs: 2` the order is
    `[c,t,t,c]` by arm id, and the two entries of pair 1 share a seed while
    pairs 1 and 2 do not.
  - `preregistrationCarriesQuestionAndFalsifier` — the rendered block contains
    both strings verbatim.

- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Implement `EvalExperiment`.**
- [ ] **Step 4: `just test`** green.
- [ ] **Step 5: Break `runOrder` to emit ABAB, watch
      `runOrderIsABBAAndSeedMatched` fail, restore.**
- [ ] **Step 6: Commit** — `EvalExperiment: pre-registration, one variable, interleaved order`.

---

### Task 4: `EvalReport` — deltas, spread, verdict, and no headline ratio

**Files:**
- Create: `Sources/SwiftStarKit/EvalReport.swift`
- Create: `Tests/SwiftStarKitTests/EvalReportTests.swift`

**Interfaces:**
- Consumes: `TurnSummary`, `EvalExperiment`
- Produces: `public struct PairResult: Equatable, Sendable` with
  `pair: Int`, `controlSuffix: Int`, `treatmentSuffix: Int`, `delta: Int`
- Produces: `public enum FalsifierVerdict: String, Codable { case unrecorded, held, refuted }`
- Produces: `public static func render(_ experiment: EvalExperiment,
  pairs: [PairResult], verdict: FalsifierVerdict, exploratory: Bool) -> String`
- Produces: `public static func exitCode(for verdict: FalsifierVerdict) -> Int32`
  (`unrecorded` → 2)

- [ ] **Step 1: Write the failing tests**

  - `reportsEveryPairAndTheSpread` — three pairs render three delta lines plus
    a min/max spread line.
  - `neverPrintsARatio` — a rendered report over pairs whose deltas would give
    2.2x contains no `x` ratio token and no `%` speedup figure. Pins the exact
    artifact misread twice on 2026-08-30.
  - `unrecordedVerdictExitsNonZero` — `exitCode(for: .unrecorded) == 2` and the
    report contains `VERDICT: unrecorded`.
  - `recordedVerdictExitsZero` — `exitCode(for: .held) == 0` (sibling success).
  - `exploratoryStampsEveryClaim` — with `exploratory: true` the report
    contains `NOT A CAUSAL CLAIM`.

- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Implement `EvalReport`.**
- [ ] **Step 4: `just test`** green.
- [ ] **Step 5: Break `render` to emit a ratio, watch `neverPrintsARatio`
      fail, restore.**
- [ ] **Step 6: Commit** — `EvalReport: paired deltas and a spread, never a headline ratio`.

---

### Task 5: Extract `AgentSession` from `AgentController`

**Files:**
- Create: `Sources/SwiftStarAppKit/AgentSession.swift`
- Modify: `Sources/SwiftStar/AgentController.swift:338-1163` (becomes a
  wrapper owning view state)
- Create: `Tests/SwiftStarIntegrationTests/AgentSessionTests.swift`

**Interfaces:**
- Consumes: `AgentCommand.argv/binaryPath/engineEnvironment`,
  `AgentWireParser`, `ToolCallbackResponder`, `HostToolExecutor`,
  `ToolRefusalTracker`, `ToolCallBudgetTracker`, `CaptureWriter`, `SpawnRecord`
- Produces: `public final class AgentSession` with
  `init(settings: AgentSettings, tools: [String], captureDirectory: URL)`,
  `func start() throws -> SpawnRecord`, `func send(_ prompt: String) -> Bool`,
  `func run(_ command: Command) -> Bool` (routes `CommandRouter` output:
  `.chat`, `.quick`, `.orchestrate`), `func interrupt()`, `func stop()`, and
  the callbacks `onOutcome: ((TurnOutcome) -> Void)?`,
  `onWireLine`/`onStderrLine: ((String) -> Void)?`. All `public`.
- Produces: nothing SwiftUI-shaped. Transcript rows, bubbles, tool cards and
  memory polling stay in `AgentController` and consume the callbacks.

- [ ] **Step 1: Write the failing test** —
  `sessionSpawnsTheFakeEngineAndCompletesOneTurn`: against the fake agent
  binary, `start()` returns a `SpawnRecord` whose `argv` equals
  `AgentCommand.argv(settings:)`, and one `send` produces exactly one
  `TurnOutcome` on `onOutcome`.
- [ ] **Step 2: Run it and watch it fail** (`just integration`; `AgentSession`
      does not exist).
- [ ] **Step 3: Move the loop** — `startAgent`, `consumeWire`, `consumeStderr`,
      `send`, `writeToolResult`, `interrupt`, `stopAgent`, `orchestrate`,
      `quick`, `consult` and the capture/provenance writing. `AgentController`
      keeps `state`, transcript rows, `appendOutcome`, memory polling and
      capture retention, and forwards.
- [ ] **Step 4: `just test && just integration`** — the app's existing tests
      are the extraction's proof and must stay green with **no test edited to
      accommodate the move**. A test that needs changing is a behavior change,
      not a refactor; stop and record it.
- [ ] **Step 5: Break the `run(_:)` routing so `.quick` falls through to
      `.chat`, watch a `TurnThinkPolicy` assertion fail, restore.**
- [ ] **Step 6: Commit** — `AgentSession: the app's turn loop, headless`.

---

### Task 6: `swiftstar-eval run` — one arm, the app's path

**Files:**
- Create: `Sources/swiftstar-eval/main.swift`
- Create: `Sources/swiftstar-eval/RunVerb.swift`
- Modify: `Package.swift` (add the `swiftstar-eval` executable target)
- Create: `Tests/SwiftStarKitTests/EvalArgumentsTests.swift`
- Create: `Sources/SwiftStarKit/EvalArguments.swift`

**Interfaces:**
- Consumes: `AgentSession` (Task 5), `CommandRouter`, `VariantRegistry`
- Produces: `public enum EvalArguments` with
  `public static func parse(_ argv: [String]) -> Result<EvalInvocation, String>`
- Produces: `public struct EvalInvocation: Equatable` with
  `verb: String`, `flags: [String: String]`, `positional: [String]`
- Produces: `swiftstar-eval run --prompt <text|@file> [--mode bare|chat|quick|
  orchestrate] [--variant ID] [--ctx N] [--power N] [--shell on|off]
  [--workspace PATH] [--host-tools] [--seed N] [--tools a,b,c]`

- [ ] **Step 1: Write the failing tests** —
  `parsesEveryFormerCaptureEnvKnobAsAFlag`: each of `CAPTURE_GGUF`,
  `CAPTURE_CTX`, `CAPTURE_WORKSPACE`, `CAPTURE_SHELL`, `CAPTURE_HOST_TOOLS`,
  `CAPTURE_POWER`, `CAPTURE_PER_TURN_THINK`, `CAPTURE_PROMPTS_FILE` has a
  named flag in the parsed invocation; and `rejectsAnUnknownFlag` returns a
  failure naming it (sibling: `acceptsTheDocumentedFlagSet`).
- [ ] **Step 2: Run them and watch them fail.**
- [ ] **Step 3: Implement `EvalArguments` and the `run` verb** over
      `AgentSession`, writing the capture tree and `provenance.md` from
      `SpawnRecord`.
- [ ] **Step 4: `just test`** green; `swift build` produces the executable.
- [ ] **Step 5: Break the `--power` flag so it is parsed but dropped, watch
      `parsesEveryFormerCaptureEnvKnobAsAFlag` fail, restore.**
- [ ] **Step 6: Commit** — `swiftstar-eval run: an ad-hoc prompt down the app's spawn path`.

---

### Task 7: Move the analyzer verbs in; delete `swiftstar-analyze`

**Files:**
- Create: `Sources/swiftstar-eval/AnalyzeVerbs.swift` (from
  `Sources/swiftstar-analyze/main.swift`)
- Delete: `Sources/swiftstar-analyze/main.swift`
- Modify: `Package.swift`, `justfile:99` (the `capture` recipe)

**Interfaces:**
- Produces: `list`, `summary`, `trace`, `diff`, `rereads`, `findings`,
  `taxonomy`, `validate`, `report`, `index` as `swiftstar-eval` verbs with
  **unchanged semantics and unchanged output**.

- [ ] **Step 1: Write the failing test** —
  `everyAnalyzeVerbIsReachableFromEval`: `EvalArguments.parse` accepts all ten
  verb names and rejects `summarise` (sibling refusal).
- [ ] **Step 2: Run it and watch it fail.**
- [ ] **Step 3: Move the file**, changing only the dispatch entry point.
- [ ] **Step 4: `just test && just integration`** green, and `swiftstar-eval
      summary --latest` is byte-identical to the pre-move `swiftstar-analyze
      summary --latest` over a committed capture. Record it in the commit.
- [ ] **Step 5: Break the `diff` verb's dispatch, watch
      `everyAnalyzeVerbIsReachableFromEval` fail, restore.**
- [ ] **Step 6: Commit** — `swiftstar-eval: absorb the analyzer verbs unchanged`.

---

### Task 8: `swiftstar-eval experiment` — the interleaved paired run

**Files:**
- Create: `Sources/swiftstar-eval/ExperimentVerb.swift`
- Create: `Tests/SwiftStarIntegrationTests/ExperimentVerbTests.swift`

**Interfaces:**
- Consumes: `EvalExperiment`, `ArmDiff`, `EvalReport`, `AgentSession`,
  `CaptureUsability.recordsWork`
- Produces: `swiftstar-eval experiment evals/<name>.json [--exploratory]
  [--record-verdict held|refuted]`
- Produces: the results layout
  `captures/eval/<name>/<timestamp>/{experiment.json, preregistration.md,
  arm-diff.txt, pair-N/<armID>/, report.md}`

- [ ] **Step 1: Write the failing tests**

  - `writesPreregistrationBeforeTheFirstSpawn` — against the fake engine, the
    results directory contains `preregistration.md` and `arm-diff.txt` before
    any `wire.ndjson` exists.
  - `refusesAnExperimentWhoseArmsDifferUndeclared` — an experiment whose arms
    differ in `power` exits non-zero, writes `arm-diff.txt`, and **spawns
    nothing** (asserted by the absence of any `pair-1/` directory).
  - `admitsTheDeclaredVariable` — the sibling: the same experiment with
    `variable: "power"` runs.
  - `refusesToOverwriteAnExistingResultsDirectory` — a second run against the
    same timestamped directory exits non-zero.
  - `unusableCapturesAreExcludedByRecordsWork` — a pair whose capture records
    no work is dropped from the report with a named reason, not silently.

- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Implement the verb.**
- [ ] **Step 4: `just test && just integration`** green.
- [ ] **Step 5: Break the ordering so `arm-diff.txt` is written after the
      first spawn, watch `writesPreregistrationBeforeTheFirstSpawn` fail,
      restore.**
- [ ] **Step 6: Commit** — `swiftstar-eval experiment: pre-register, diff, interleave, report`.

---

### Task 9: Delete `swiftstar-drive`; `just eval`

**Files:**
- Delete: `Sources/swiftstar-drive/main.swift`
- Modify: `Package.swift`, `justfile:99-102`
- Modify: `fixtures/agent/provenance.md` (the recapture rule now names
  `swiftstar-eval run`)

**Interfaces:**
- Produces: `just eval ARGS` and `just capture` re-pointed at
  `swiftstar-eval run`, preserving the golden-recapture path
  (`BRIEF.md`: fakes are generated from committed golden captures).

- [ ] **Step 1: Write the failing test** — do **not** assert that provenance
  spells the recapture command; that is a source-text assertion (rule 3).
  Instead: run `just capture` against the fake engine and assert the produced
  tree passes `CaptureValidity`.
- [ ] **Step 2: Run it and watch it fail** (the recipe calls a deleted binary).
- [ ] **Step 3: Re-point the recipes and delete the target.**
- [ ] **Step 4: `just test && just integration`** green.
- [ ] **Step 5: Break the recipe's `--host-tools` flag, watch the capture
      validity assertion fail, restore.**
- [ ] **Step 6: Commit** — `Retire swiftstar-drive; just eval is the one entry point`.

## Self-review notes

- **Spec coverage (this plan):** four components → Tasks 1, 3, 4, 5. Verbs →
  Tasks 6, 7, 8. Env knobs die → Task 6. Experiment file schema → Task 3. Arm
  diff → Task 2. Repeats/interleaving/claim strength → Tasks 3, 4. Results
  layout → Task 8. Cycle 1 deletions → Tasks 7, 9. The bill itself and the
  amendments are cycle 1b; cycle 2 (agenttest, `DeepSeekGrader`) gets its own.
- **Type consistency:** `SpawnRecord` (Task 1) is consumed verbatim by Tasks
  2, 5, 6. `ArmDiff.admit` (Task 2) by Task 8. `EvalExperiment.runOrder` and
  `EvalMode` (Task 3) by Tasks 6, 8. `EvalReport.render`/`exitCode` (Task 4)
  by Task 8. `AgentSession.run(_:)` (Task 5) by Tasks 6, 8.
- **Ordering:** Task 5 is the risk, gated on the app's existing tests staying
  green with no test edited. Tasks 1–4 are pure and land before it; 6–9 after.
- **Task 9 Step 1 deliberately refuses a source-text assertion** (rule 3).
