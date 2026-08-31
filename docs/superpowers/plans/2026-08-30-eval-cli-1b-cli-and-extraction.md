# `swiftstar-eval` 1b: the engine flag, the extraction, the CLI

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the tool set a real spawn axis in the engine, lift the app's
turn loop into a SwiftUI-free `AgentSession`, and build `swiftstar-eval` on
top of it — retiring `swiftstar-drive` and `swiftstar-analyze`.

**Architecture:** The extraction is the risk and is split three ways
(single-turn loop, pool loop, command routing) so a reviewer can reject one
without rejecting the others. Above it the CLI is thin: `run` drives one
`AgentSession`, `experiment` drives the interleaved order plan 1a computes,
each run in a fresh worktree.

**Tech Stack:** Swift 6 language mode, SwiftPM, swift-testing, macOS 26+, and
one C patch to the ds4 fork.

**Spec:**
[`2026-08-30-eval-cli-design.md`](../specs/2026-08-30-eval-cli-design.md)

**Depends on:** plan 1a
([`2026-08-30-eval-cli-1a-kit-types.md`](2026-08-30-eval-cli-1a-kit-types.md)),
landed and green.

## Global Constraints

- **Plan style is `docs/sdd.md`'s local rule**: files touched, signatures
  only, and the test that proves it. No pasted bodies.
- **Binding rules, from `BRIEF.md`:** (2) every new test is shown to fail
  before it passes; (3) no source-text assertions, ever; (4) every refusal
  test has a sibling success; (5) the capture is written before anything reads
  it; (7) the wire announces itself and a mismatch refuses loudly.
- **Every submodule bump owes a golden-fixture recapture** against the real
  binary. A rebase can apply cleanly and still be semantically wrong.
- `SwiftStarAppKit` has no `defaultIsolation`; the app target sets
  `MainActor` (`Package.swift:46`). `AgentSession`'s isolation is a decision,
  not an omission — see Task 2.

---

### Task 1: Engine — `--tools`, so the tool set is an argv axis

**Files:**
- Modify: `external/ds4/ds4_agent.c:1575` (`agent_schemas_for`) and its two
  call sites (`:1617`, `:1669`)
- Modify: `external/ds4/docs/fork-ledger.md` (a new divergence row)
- Modify: `Sources/SwiftStarKit/AgentCommand.swift:145-189` (pass `--tools`)

**Interfaces:**
- Produces: `--tools a,b,c` — a filter over the advertised schema list,
  applied after the existing `shell_allowed`/`host_tools` gating. Absent =
  today's behavior exactly, so every golden fixture is unchanged.
- Produces: `AgentSettings.tools: [String]?` and its argv rendering.

**Why this task exists:** the design's flagship experiment declared
`variable: "tools"` before anyone checked that a tool set is a thing a spawn
can vary. It is not — `agent_schemas_for(char *out, size_t outlen,
bool shell_allowed, bool host_tools)` takes two booleans and no list. Without
this flag the experiment cannot be run, and a `SpawnRecord.tools` that is only
a caller-supplied parameter repeats defect 1: a record claiming a treatment
the engine never applied.

- [ ] **Step 1: Write the failing integration test** —
  `advertisedSchemasHonorTheToolsFilter`: spawning with
  `--tools read,write,list` yields a handshake whose advertised schema names
  are exactly those three; the sibling `absentToolsFlagAdvertisesEverything`
  asserts the unfiltered set is unchanged.
- [ ] **Step 2: Run and watch both fail** (`just integration`).
- [ ] **Step 3: Patch the engine**, add the fork-ledger row (why it exists,
      what would retire it), and thread the flag through `AgentCommand`.
- [ ] **Step 4: `just engine && just integration`** green.
- [ ] **Step 5: Golden recapture** per `fixtures/agent/provenance.md`, confirm
      `bundledFixtureMatchesRepoFixture`, and copy to
      `Sources/SwiftStarAppKit/Resources/`.
- [ ] **Step 6: Break the filter so it ignores its argument, watch
      `advertisedSchemasHonorTheToolsFilter` fail, restore.**
- [ ] **Step 7: Commit** — `Engine: --tools filters the advertised schema set (divergence #19)`.

---

### Task 2: `AgentSession` (a) — spawn, one turn, the capture

**Files:**
- Create: `Sources/SwiftStarAppKit/AgentSession.swift`
- Modify: `Sources/SwiftStar/AgentController.swift` (`startAgent` `:338`,
  `consumeWire` `:568`, `consumeStderr` `:817`, `send` `:854`,
  `writeToolResult` `:775`, `interrupt` `:935`, `stopAgent` `:942`)
- Create: `Tests/SwiftStarIntegrationTests/AgentSessionTests.swift`

**Interfaces:**
- Consumes: `AgentCommand`, `AgentWireParser`, `ToolCallbackResponder`,
  `HostToolExecutor`, `CaptureWriter`, `SpawnRecord`
- Produces: `@MainActor public final class AgentSession` with
  `init(settings: AgentSettings, tools: [String], captureDirectory: URL)`,
  `func start() throws -> SpawnRecord`, `func send(_ prompt: String) -> Bool`,
  `func writeToolResult(_ response: ToolCallbackResponse)`,
  `func interrupt()`, `func stop()`
- Produces: the callback surface — `onEvent: ((AgentWireEvent) -> Void)?`
  (**parsed events, not raw lines**: the app must not re-parse the wire, which
  is the duplication this design exists to remove),
  `onOutcome: ((TurnOutcome) -> Void)?`,
  `onRefusal: ((String) -> Void)?`, `onStderrLine: ((String) -> Void)?`
- **Isolation decision:** `@MainActor`, because the loop's post-`await`
  `generation` guards (`AgentController.swift:723`) lean on MainActor
  serialization for correctness. Changing that is a concurrency
  re-architecture, not a move. The CLI therefore runs an async main and never
  blocks the main thread — unlike `drive` and `agenttest`, which block on FDs.

- [ ] **Step 1: Write the failing tests** —
  `sessionSpawnsAndCompletesOneTurn` (against the fake engine, `start()`
  returns a record whose argv equals `AgentCommand.argv(settings:)` and one
  `send` yields exactly one `TurnOutcome`); `toolCallbackRoundTripIsAnswered`
  (a `tool_request` is answered and the turn completes rather than
  deadlocking); `interruptEndsTheTurn`; `captureIsOnDiskBeforeTheReadback`
  (binding rule 5).
- [ ] **Step 2: Run them and watch each fail** (`just integration`).
- [ ] **Step 3: Move the single-turn loop.** `AgentController` keeps `state`,
      transcript rows, `appendOutcome`, memory polling and capture retention,
      and consumes `onEvent`.
- [ ] **Step 4: `just test && just integration`** green **except** the two
      source-text tests handled in Task 4 — do not edit them here.
- [ ] **Step 5: Break `onEvent` to drop `tool_request`, watch
      `toolCallbackRoundTripIsAnswered` fail, restore.**
- [ ] **Step 6: Commit** — `AgentSession: the app's single-turn loop, headless`.

---

### Task 3: `AgentSession` (b) — the pool loop

**Files:**
- Modify: `Sources/SwiftStar/AgentPoolTurnLoop.swift` (the worker loop and its
  transcript writes at `:125`, `:265`)
- Modify: `Sources/SwiftStarAppKit/AgentSession.swift`
- Modify: `Tests/SwiftStarIntegrationTests/AgentSessionTests.swift`

**Interfaces:**
- Produces: `AgentSession.dispatch(_ packet: HandoffPacket) -> Bool` and
  `onWorkerEvent: ((WorkerId, AgentWireEvent) -> Void)?`
- Produces: `ActiveWorkerTurn` and the watchdog stay app-side; the session
  exposes worker events and takes dispatch requests.

**Why this is its own task:** `consumeWire` calls `handleWorkerEvent`
(`AgentController.swift:576`) and `drainQueuedWorkers` (`:657`), and
`AgentPoolTurnLoop` writes to `transcript` directly while holding app-only
handles its own header says cannot leave the app target. Task 2 cannot move
`consumeWire` cleanly without this seam, and bundling them makes ~900 moved
lines unreviewable.

- [ ] **Step 1: Write the failing test** —
  `dispatchedWorkerEventsReachTheHost`: a pooled dispatch against the fake
  engine surfaces worker events tagged with the right `WorkerId`, and the
  parent turn completes.
- [ ] **Step 2: Run it and watch it fail.**
- [ ] **Step 3: Move the worker loop behind the seam.**
- [ ] **Step 4: `just test && just integration`** green.
- [ ] **Step 5: Break the worker tagging so every event carries worker 0,
      watch `dispatchedWorkerEventsReachTheHost` fail, restore.**
- [ ] **Step 6: Commit** — `AgentSession: the pool loop moves behind the seam`.

---

### Task 4: `AgentSession` (c) — command routing, and retiring two grep tests

**Files:**
- Modify: `Sources/SwiftStar/AgentController.swift` (`orchestrate` `:1039`,
  `quick` `:1088`, `consult` `:1126`)
- Modify: `Sources/SwiftStarAppKit/AgentSession.swift`
- Delete: `Tests/SwiftStarIntegrationTests/ThinkOverrideCapGateTests.swift`
- Delete: `Tests/SwiftStarIntegrationTests/PoolEngineArgvTests.swift`
- Create: `Tests/SwiftStarIntegrationTests/AgentSessionCommandTests.swift`

**Interfaces:**
- Produces: `AgentSession.run(_ command: Command) -> Bool`, routing
  `CommandRouter` output (`.chat`, `.quick`, `.orchestrate`).

**Why the deletions are a deliverable, not collateral:**
`ThinkOverrideCapGateTests.swift:25-57` and `PoolEngineArgvTests.swift:69-81`
grep `AgentController.swift` for literal source strings. Moving the loop moves
those strings, so **any correct extraction turns them red**. They are binding
rule 3 violations that exist because the module boundary was missing, and
`BRIEF.md` is explicit that the response is to move the logic, not to write
the assertion. The extraction supplies the boundary; these tests are replaced
with behavioral siblings against `AgentSession`. This is the one place in
these plans where deleting a test is correct, and it is named in advance so
nobody has to decide it under pressure.

- [ ] **Step 1: Write the failing behavioral tests** —
  `quickTurnSendsNoThinkAndChatDoesNot` (replaces the `/quick`-guard grep:
  asserts the argv/envelope the session actually emits per turn);
  `advertisedCapsComeFromTheParserNotADefault` (replaces the caps grep:
  asserts a wire without caps refuses per binding rule 7, sibling asserts one
  with caps is admitted); `pooledSpawnArgvCarriesSubagentPool` (replaces the
  `PoolEngine.argv(` grep: asserts the spawned argv, not its call site).
- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Move command routing; delete the two grep test files.**
- [ ] **Step 4: `just test && just integration`** green, with the deleted
      tests' behaviors now covered by the three above. Name the swap in the
      commit message.
- [ ] **Step 5: Break `run(_:)` so `.quick` falls through to `.chat`, watch
      `quickTurnSendsNoThinkAndChatDoesNot` fail, restore.**
- [ ] **Step 6: Commit** — `AgentSession: command routing; retire two source-text tests`.

---

### Task 5: `swiftstar-eval run`

**Files:**
- Create: `Sources/swiftstar-eval/main.swift`, `RunVerb.swift`
- Create: `Sources/SwiftStarKit/EvalArguments.swift`
- Create: `Tests/SwiftStarKitTests/EvalArgumentsTests.swift`
- Create: `Tests/SwiftStarIntegrationTests/RunVerbTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Produces: `public enum EvalArguments` with
  `public static func parse(_ argv: [String]) -> Result<EvalInvocation, String>`
- Produces: `public struct EvalInvocation: Equatable` with `verb`, `flags`,
  `positional`
- Produces: `swiftstar-eval run --prompt <text|@file> [--mode bare|chat|quick|
  orchestrate] [--variant ID] [--ctx N] [--power N] [--shell on|off]
  [--workspace PATH] [--host-tools] [--seed N] [--tools a,b,c] [--dry-run]`

- [ ] **Step 1: Write the failing tests** —
  `everyFormerCaptureEnvKnobHasAFlag` (each of `CAPTURE_GGUF`, `CAPTURE_CTX`,
  `CAPTURE_WORKSPACE`, `CAPTURE_SHELL`, `CAPTURE_HOST_TOOLS`, `CAPTURE_POWER`,
  `CAPTURE_PER_TURN_THINK`, `CAPTURE_PROMPTS_FILE` maps to a named flag);
  `rejectsAnUnknownFlag` with `acceptsTheDocumentedFlagSet` as its sibling;
  `dryRunSpawnsNothing` (prints the resolved record, creates no capture tree);
  and the behavioral `runWritesACaptureTreeAndProvenance` — the capture passes
  `CaptureValidity` and `provenance.md` carries the `power` line.
- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Implement `EvalArguments` and `run`** over `AgentSession`,
      writing provenance from `SpawnRecord`.
- [ ] **Step 4: `just test && just integration`** green.
- [ ] **Step 5: Break `--power` so it parses but is dropped from the record,
      watch `runWritesACaptureTreeAndProvenance` fail, restore.**
- [ ] **Step 6: Commit** — `swiftstar-eval run: an ad-hoc prompt down the app's spawn path`.

---

### Task 6: Move the analyzer verbs in; delete `swiftstar-analyze`

**Files:**
- Create: `Sources/swiftstar-eval/AnalyzeVerbs.swift` (from
  `Sources/swiftstar-analyze/main.swift`)
- Delete: `Sources/swiftstar-analyze/main.swift`
- Modify: `Package.swift`, `Justfile`

**Interfaces:**
- Produces: `list`, `summary`, `trace`, `diff`, `rereads`, `findings`,
  `taxonomy`, `validate`, `report`, `index` as `swiftstar-eval` verbs with
  **unchanged semantics and unchanged output**.

- [ ] **Step 1: Write the failing test** —
  `everyAnalyzeVerbIsReachable`: all ten verb names parse and `summarise` is
  rejected (sibling refusal).
- [ ] **Step 2: Run it and watch it fail.**
- [ ] **Step 3: Move the file**, changing only the dispatch entry point.
- [ ] **Step 4: `just test && just integration`** green, and `swiftstar-eval
      summary --latest` is byte-identical to the pre-move `swiftstar-analyze
      summary --latest` over a committed capture. Record it in the commit.
- [ ] **Step 5: Break the `diff` dispatch, watch
      `everyAnalyzeVerbIsReachable` fail, restore.**
- [ ] **Step 6: Commit** — `swiftstar-eval: absorb the analyzer verbs unchanged`.

---

### Task 7: `swiftstar-eval experiment`

**Files:**
- Create: `Sources/swiftstar-eval/ExperimentVerb.swift`
- Create: `Sources/SwiftStarAppKit/RunWorkspace.swift`
- Create: `Tests/SwiftStarIntegrationTests/ExperimentVerbTests.swift`

**Interfaces:**
- Consumes: `EvalExperiment`, `ArmDiff`, `PairBill`, `EvalReport`,
  `AgentSession`, `CaptureUsability.recordsWork`
- Produces: `swiftstar-eval experiment evals/<name>.json [--exploratory]
  [--dry-run]` and, as a **separate invocation**,
  `swiftstar-eval verdict <results-dir> --record claimSurvives|claimFalsified
  --evidence <path|line>`
- Produces: `RunWorkspace` — a fresh git worktree per run, its ref recorded in
  the `SpawnRecord`, removed after the capture is written
- Produces: the results layout
  `captures/eval/<name>/<timestamp>/{experiment.json, preregistration.md,
  arm-diff.txt, pair-N/<armID>/, report.md}`

- [ ] **Step 1: Write the failing tests**

  - `writesPreregistrationBeforeTheFirstSpawn` — `preregistration.md` and
    `arm-diff.txt` exist before any `wire.ndjson` does.
  - `refusesArmsThatDifferUndeclared` — exits non-zero, writes
    `arm-diff.txt`, and **spawns nothing** (no `pair-1/` directory).
  - `admitsTheDeclaredVariable` — the sibling success.
  - `refusesAnUncommittedExperimentFile` — a dirty or untracked experiment
    file is refused, which is what makes "pre-registered" a fact rather than a
    habit.
  - `eachRunGetsAFreshWorkspace` — run 2's workspace ref equals run 1's
    starting ref, so a change-and-verify prompt cannot find its own earlier
    edit. Without this every pair after the first is invalid and no refusal
    catches it.
  - `advertisedToolsAreVerifiedAgainstTheWire` — a handshake advertising a set
    that differs from the arm's declared `tools` aborts the run.
  - `verdictCannotBeRecordedOnTheRunInvocation` — passing `--record` to
    `experiment` is refused; the sibling records it afterward and exits zero.
  - `attemptNumberComesFromSiblingDirectories` — a second results directory
    renders "attempt 2".

- [ ] **Step 2: Run them and watch each fail.**
- [ ] **Step 3: Implement the verb and `RunWorkspace`.**
- [ ] **Step 4: `just test && just integration`** green.
- [ ] **Step 5: Break `RunWorkspace` to reuse one directory, watch
      `eachRunGetsAFreshWorkspace` fail, restore.**
- [ ] **Step 6: Commit** — `swiftstar-eval experiment: pre-register, diff, interleave, report`.

---

### Task 8: Delete `swiftstar-drive`; `just eval`

**Files:**
- Delete: `Sources/swiftstar-drive/main.swift`
- Modify: `Package.swift`, `Justfile`, `fixtures/agent/provenance.md`

**Interfaces:**
- Produces: `just eval ARGS` and `just capture` re-pointed at
  `swiftstar-eval run`, preserving the golden-recapture path.

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

- **Spec coverage (this plan):** the tool set as an argv axis and its
  post-handshake verification → Tasks 1, 7. The extraction → Tasks 2–4. Verbs
  and the env-knob retirement → Tasks 5, 6. Worktree per run, attempt
  counting, the committed-file check and the separated verdict → Task 7.
  Deletions → Tasks 6, 8.
- **Type consistency:** `AgentSession` (Tasks 2–4) is consumed by Tasks 5 and
  7. `EvalArguments` (Task 5) by Tasks 6, 7. Plan 1a's `SpawnRecord`,
  `ArmDiff`, `EvalExperiment`, `PairBill`, `EvalReport` are consumed here and
  defined there.
- **The riskiest ordering assumption:** Task 2 leaves the two source-text
  tests red until Task 4 deletes them. That window is deliberate and named, so
  a red suite between those tasks is expected rather than alarming — but the
  branch must not be merged mid-window.
- **`PoolOrchestrator` remains a second headless turn loop** until cycle 2, so
  "a divergence stops compiling" holds for the app-versus-eval seam and not
  yet for the whole system.
