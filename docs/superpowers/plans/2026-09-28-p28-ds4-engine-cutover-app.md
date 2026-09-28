---
phase: P28
cycle: P28-ds4-engine-cutover-b
lifecycle: closed
---

# P28 ds4-engine cut-over, plan B: switch, remove, document

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** the app runs on `EngineSession` (plan A), and every trace of the
ds4 fork, host tools, pool, diagnostics and the two CLIs is gone.

**Spec:** `docs/superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md`
(its "Revisions" section supersedes the body). **Depends on:** plan A,
`2026-09-28-p28-ds4-engine-cutover.md`, Tasks 1–5.

## Global constraints

- As plan A. The `SwiftStar` target keeps `.defaultIsolation(MainActor.self)`.
- No Apply button, model chooser, session picker or host sampling.
- Removal is fixed only by deleting or rewriting against the new types —
  never by reintroducing old code.
- Commit with `git commit -- <paths>`; `git rm` stages globally, so the
  docs lane never commits without pathspecs.

## Review focus

1. **`ds4-dogfood` not found** (GUI `PATH`): a message listing every place
   searched → Task 6.
2. **Workspace is not a git repo**: the exit-2 refusal text in the
   transcript, prompt disabled → Task 6.
3. **Quit mid-turn**: no orphaned `ds4-dogfood` (`pgrep` empty) → Tasks 6, 9.
4. **Prompt while busy**: forwarded and shown once → Task 6 (via plan A's
   transcript rules).
5. **Docs build**: `just docs` green after deletions (no dangling source
   links) → Task 8.

## Execution lanes

**Code** (Tasks 6–7, sequential) runs in parallel with **docs** (Task 8,
Markdown, `docs/`, `.claude/`, `CLAUDE.md`, `pyproject.toml`/`uv.lock`
only — never `Justfile`, `Sources/`, `Tests/`). Task 9 joins them.

---

### Task 6: Switch the app to the engine

**Files:**
- Create: `Sources/SwiftStar/EngineController.swift`,
  `Sources/SwiftStar/GaugeFormatting.swift` (`Severity`,
  `contextSeverity(ctxUsed:)`, `fixedWidth(_:width:)` moved from
  `DialLogic`, app-target, `internal`)
- Rewrite: `Sources/SwiftStar/AgentView.swift` (transcript list over
  `TranscriptRow`, prompt field, Stop bound to `canStop`, workspace folder
  picker kept; no `ModelMenu`, no `AgentStatusText`/`StatusSnapshot`
  status bar), `AgentBubbles.swift` (no consulted/compaction/worker rows),
  `AgentToolCardView.swift` (over `EngineToolCard`: op, path, ok,
  duration, preview, truncated marker), `MetricsModel.swift` (holds
  `EngineMetricsState` only), `InspectorView.swift` (metrics from
  `EngineMetricsState`: prefill/generation tok/s, context gauge, GPU
  memory; no Diagnostics tab), `MainView.swift`, `SwiftStarApp.swift`,
  `SettingsView.swift` (one field: `ds4-dogfood` path, `@AppStorage
  ("engineExecutable")`, empty = search).
- Delete: `Sources/SwiftStar/AgentController.swift`, `AgentPoolTurnLoop.swift`,
  `ActiveWorkerTurn.swift`, `DiagnosticsModel.swift`, `DiagnosticsView.swift`,
  `MetricsView.swift` (already unreferenced).

**Interfaces:**
- Consumes: plan A's `EngineSession`, `EngineTranscript`, `TranscriptRow`,
  `EngineToolCard`, `EngineMetricsState`/`Reducer`, `EngineCommand`,
  `EngineExit`, `EngineResolution`; `ProjectRoot`.
- Produces: `@Observable final class EngineController` — `transcript`,
  `metrics`, `phase: Phase` (`.idle`, `.starting`, `.running`,
  `.ended(EngineExit)`, `.notFound([String])`), `workspace: URL?`,
  `sessionDirectory: URL?`; `func start()`, `func send(_ text: String)`
  (appends the user row, then forwards; enabled whenever `.running`),
  `func stop()` (only if `transcript.canStop`), `func quit() async`.

Behaviour: `start` resolves the executable (`PATH` from `ProcessInfo`),
finds the git root of `workspace` with `ProjectRoot`, spawns with
`EngineCommand.arguments(source:)`; `.notFound` shows the searched list.
On exit the transcript gains a system row with `EngineExit.message` and,
when known, the session directory and `EngineCommand.applyCommand`. The
app delegate's `applicationShouldTerminate` returns `.terminateLater`,
awaits `quit()`, then replies. Remove every comment in kept app files that
names `ds4-agent`, `external/ds4`, pools or host tools.

- [ ] **Step 1:** implement the above.
- [ ] **Step 2:** `swift build` and `swift test` green; `just app`
  builds. Grep: no file in `Sources/SwiftStar/` references `Agent`-wire
  types (`AgentEvent`, `AgentSession`, `AgentTranscript`, `StatusSnapshot`,
  `DialLogic`, `Variant`, `ModelChoice`, `Diagnostics`). Commit.

### Task 7: Remove everything else

**Delete:**
- `external/ds4` (`git rm`), `.gitmodules`.
- `Sources/swiftstar-eval/`, `Sources/swiftstar-agenttest/`.
- `Sources/SwiftStarAppKit/`: everything except `EngineSession.swift`
  (`SubprocessRunner` included, spec revision 6); `Resources/`.
- `Sources/SwiftStarKit/`: everything in the spec's "Removed" list, plus
  `AgentTranscript`, `AgentWireParser`, `WireEventParser`, `MetricsReducer`,
  `TurnOutcome`, `TurnSummary`, `DialLogic`, `AgentStatusText`, then every
  file no kept source or test references.
- Tests of every deleted unit; `FakeAgentHarness`, `FakeProcessHarness`,
  `GitFixtureRepo`, `PollingLineReader*`, `RangeFileServer` users, and
  `Tests/SwiftStarKitTests/Fixtures/eval-*`, each if nothing kept uses it.
- `fixtures/agent/`, `fixtures/agenttest/`, `fixtures/diagnostics/`.
- `Tools/`: all but `make-app.sh`, `make-icon.swift`, `record-engine-fixture.py`.

**Modify:** `Package.swift` (drop CLI targets, `IOReport` linker setting,
AppKit `resources:`); `Justfile` (drop `engine`, `eval`); `Tools/make-app.sh`
(drop removed resources, if bundled); `.gitignore` (drop `captures/`,
`.swiftstar/` if nothing writes them).

- [ ] **Step 1:** Delete in bulk; fix `swift build` only by deleting orphans.
- [ ] **Step 2:** Orphan sweep: every remaining `SwiftStarKit` and
  `SwiftStarAppKit` file has a public type referenced by kept code or
  tests; delete the rest.
- [ ] **Step 3:** Criterion 1: `git grep -il -e ds4-agent -e external/ds4
  -e submodule -- Sources Tests Package.swift Justfile` prints nothing;
  `.gitmodules` absent.
- [ ] **Step 4:** `swift test` and `SWIFTSTAR_INTEGRATION=1 swift test`
  green; `just app` builds; commit.

### Task 8: Docs (parallel lane)

**Files:**
- Modify: `BRIEF.md` ("What we are building", "Architecture, settled",
  "The fork" → "The engine", "Testing", "Practical environment", "Where to
  start"), `ROADMAP.md`, `README.md`, `docs/glossary.md`, `CLAUDE.md`
  (drop "Session telemetry"), `docs/index.md` (add `remediations` to the
  toctree — `just docs` is red before P28), any `docs/*.md` page that
  documents a removed CLI or the fork or links a deleted source file
  (e.g. `docs/2026-08-26-old-ui-element-inventory.md`).
- Modify: `pyproject.toml` and `uv.lock` — drop groups/`[tool.ruff]`
  entries that only served the removed host `lint` tool (`uv lock`).
- Delete: `.claude/skills/telemetry/` and any `.claude/skills/` entry that
  drives a removed CLI.

Rules: rewrite, don't annotate; BRIEF describes post-P28 SwiftStar, cites
the spec, and records the reopening in one dated sentence. ROADMAP: a P28
row (Status "in progress", caps 900/1,000), `## Now`, a one-line Status
note on each row whose machinery P28 removes, Backlog entries that assumed
the fork closed or re-homed. `docs/superpowers/` history is not edited.
Links to deleted source files become plain text naming the file and "(removed in P28)".

- [ ] **Step 1:** Edit; `just lint-docs` and `just docs` green; commit with
  pathspecs.

### Task 9: Live verification and close (joins both lanes)

- [ ] **Step 1:** `just app`; launch `.build/SwiftStar.app` with
  `ds4-dogfood` on the Settings path and Laguna XS present; workspace =
  this repo. Check spec criterion 3: a `read` card with preview, an
  answer, metrics after the pause, Stop mid-turn, `/help` shows a notice,
  quit leaves `pgrep -f ds4-dogfood` empty, and the session directory +
  apply command appear.
- [ ] **Step 2:** Whole-branch review and fixes; both plans get
  `## Result` and `lifecycle: closed`; ROADMAP P28 Status; `just lint-docs`
  green; commit.

## Result

Closed 2026-09-28.

- **Commits:** `aa6c1f9` + `730e5ff` (T6 + review fix), `94ac02a`, `7eeda74`
  (T7), `e27d0b2` + `a6a3a4a` (T8 + review fix), `1d0dadc` (final-review
  fixes).
- **Diverged:** Task 8 ran before Tasks 5–7 (docs lane); its Backlog
  collapse first closed non-fork entries, restored in `a6a3a4a`. Task 6
  kept the font slider in Settings, added a 10 s outer quit bound with a
  generation counter, and moved gauge helpers into `GaugeFormatting.swift`.
- **Task 9:** GUI click-through was not possible from the agent session (no
  screen or accessibility access). Verified instead: the built app spawns
  `tui --ndjson --source <root> --commit HEAD` and quits with no orphan; a
  throwaway live `EngineSession` probe against Laguna XS showed a `read`
  card with preview, an answer, per-pause metrics (≈776 / ≈146 tok/s, ctx
  1,956 / 65,536), `/help` as a notice, Stop mid-turn → interrupted, and
  quit → exit 0 with session directory and `ds4-dogfood apply <id>`.
- **Descoped:** nothing; the owner's GUI pass remains the last check.
- **Deferred minors** (final review triaged; none blocks merge): Quick Look
  resolves tool paths against the picked folder, not the git root
  (`AgentToolCardView`); status wording "Ended (exit -1)" / "code 15"
  (`terminationReason` ignored); no SIGKILL after SIGTERM; `/status` omits
  context size before the first prompt; the fake finishes a `quit` sent
  during a pause at once and emits no `stopping`; test gaps for unmatched
  `toolEnd`/`toolResult` and nil-overwrite metrics; new Python under
  `Tools/` and `fixtures/` is unlinted.
