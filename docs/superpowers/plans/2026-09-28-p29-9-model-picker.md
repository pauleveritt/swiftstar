---
phase: P29
cycle: P29.9-model-picker
lifecycle: active
---

# P29.9 model picker implementation plan

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** choose the engine's model and context size from SwiftStar Settings,
passed as `--model-id`/`--context-size` to `ds4-dogfood tui`.

**Spec:** `docs/superpowers/specs/2026-09-28-p29-9-model-picker-design.md`

## Global constraints

- Swift 6; the `SwiftStar` target keeps `.defaultIsolation(MainActor.self)`.
- Empty settings → argv byte-identical to P28:
  `tui --ndjson --source <root> --commit HEAD`.
- Flags appended after the P28 argv, in this order: `--model-id <id>`,
  `--context-size <n>`.
- No model registry in SwiftStar; no dropdown.
- `@AppStorage` keys: `engineModelID` (String), `engineContextSize` (Int, 0 = unset).
- Commit with the attribution line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review focus

1. **Whitespace or empty model id** → no `--model-id` flag → Task 1.
2. **Zero or negative context size** → no `--context-size` flag → Task 1.
3. **Settings changed mid-session** → running session untouched; toolbar
   offers restart → Task 2.
4. **Engine refuses the model** → existing "refused to start: …" row → Task 2
   (live check in Task 3).
5. **Session event missing** (older engine) → toolbar shows no model, no crash → Task 1.

---

### Task 1: argv and loaded-session state (Kit)

**Files:**
- Modify: `Sources/SwiftStarKit/EngineCommand.swift` (`arguments`)
- Modify: `Sources/SwiftStarKit/EngineTranscript.swift` (keep `session`)
- Modify: `fixtures/engine/fake-ds4-dogfood` (`FAKE_ENGINE_ARGV_LOG`: write
  its argv, one per line, at start)
- Test: `Tests/SwiftStarKitTests/EngineCommandTests.swift`,
  `Tests/SwiftStarKitTests/EngineTranscriptTests.swift`,
  `Tests/SwiftStarIntegrationTests/EngineSessionTests.swift`

**Interfaces (produces):**
- `EngineCommand.arguments(source: URL, modelID: String? = nil,
  contextSize: Int? = nil) -> [String]` (existing callers unchanged).
- `EngineTranscript.session: EngineSessionInfo?` — set on `.session`,
  cleared on `.closed`.

- [ ] **Step 1: failing tests:**
  - `emptySettingsKeepP28Argv` — `arguments(source:, modelID: "", contextSize: 0)`
    == `["tui","--ndjson","--source","/tmp/r","--commit","HEAD"]`.
  - `modelIDAppended` — `"qwen3.8-flash-next"` → argv ends with
    `["--model-id","qwen3.8-flash-next"]`.
  - `contextAppended` — `20000` → ends with `["--context-size","20000"]`.
  - `bothInOrder` — ends with `["--model-id","m","--context-size","8192"]`.
  - `whitespaceIDAndNonPositiveContextIgnored` — `"  "`, `-1` → P28 argv.
  - `transcriptKeepsSessionInfo` — replaying `tool-read.ndjson`: after the
    `session` event, `session?.modelID == "laguna-xs-2.1"` and
    `contextSize == 20000`; after `.closed`, `session == nil`.
  - `fakeReceivesModelFlags` (integration) — the fake (which ignores its
    arguments otherwise) is started with the full
    `arguments(source:, modelID: "qwen3.8-flash-next", contextSize: 20000)`;
    its argv log contains `--model-id` followed by `qwen3.8-flash-next`,
    and `--context-size` followed by `20000`.
- [ ] **Step 2:** red → implement → `swift test` and
  `SWIFTSTAR_INTEGRATION=1 swift test` green → commit.

### Task 2: Settings fields, controller, toolbar (app)

**Files:**
- Modify: `Sources/SwiftStar/SettingsView.swift` (two fields in the Engine
  section, with help text naming `laguna-xs-2.1` and `qwen3.8-flash-next`
  as examples, "empty = engine default")
- Modify: `Sources/SwiftStar/EngineController.swift` (read both keys at
  `start()`, pass to `arguments`; `restartNeeded: Bool` comparing
  `transcript.session` with Settings; `func restart()` = quit then start)
- Modify: `Sources/SwiftStar/AgentView.swift` (toolbar: loaded model id and
  context size; a "Restart to use <model>" button when `restartNeeded`)

**Interfaces:**
- Consumes: Task 1.
- Produces: `EngineController.restartNeeded: Bool`, `EngineController.restart() async`.

Rules: `restartNeeded` is true only while a session runs and either the
Settings model id (trimmed, non-empty) differs from `session.modelID` or the
Settings context (> 0) differs from `session.contextSize`. Empty settings
never ask for a restart. Settings changes never touch a running session.

- [ ] **Step 1:** implement; `swift build`, `swift test`, `just app` green;
  commit.

### Task 3: Live check and close (controller)

- [ ] **Step 1:** Remove the P28-era wrapper setting
  (`defaults delete com.pauleveritt.SwiftStar engineExecutable` if it points
  at the wrapper). Set Model = `qwen3.8-flash-next` via
  `defaults write com.pauleveritt.SwiftStar engineModelID …`, launch
  `.build/SwiftStar.app`, confirm the spawned argv has `--model-id
  qwen3.8-flash-next` (`pgrep -fl`) and the session's `operator-events.jsonl`
  reports that model; set a bogus id, confirm exit 2 and the refusal text in
  the session's stderr path; quit, no orphan.
- [ ] **Step 2:** ROADMAP: P29.x placeholder → "P29.9 Model picker — done";
  Backlog gains "engine: `ds4-dogfood models --json` for a dropdown";
  plan `## Result`, `lifecycle: closed`; `just lint-docs` green; commit.
