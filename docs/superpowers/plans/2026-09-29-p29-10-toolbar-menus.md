---
phase: P29
cycle: P29.10-toolbar-menus
lifecycle: closed
---

# P29.10 toolbar menus implementation plan

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** folder, model and context menu buttons in the toolbar capsule, the
model list read from `ds4-dogfood models --json`.

**Spec:** `docs/superpowers/specs/2026-09-29-p29-10-toolbar-menus-design.md`

## Global constraints

- Swift 6; the `SwiftStar` target keeps `.defaultIsolation(MainActor.self)`.
- Menu contents are built by pure Kit functions with fast tests; views render them.
- `@AppStorage` keys unchanged: `agentWorkspace`, `engineModelID`,
  `engineContextSize`; new `recentWorkspaces` ([String], JSON-encoded or
  `@AppStorage`-compatible).
- The catalog runs off the main actor, 10 s timeout, never blocks launch.
- Commit with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review focus

1. **Engine without `models --json`** (today's engines) → fallback menus, one note → Tasks 1, 2.
2. **Model not on this Mac / doesn't fit** → disabled with a reason → Task 1.
3. **Choosing the current value** → no restart → Task 2.
4. **Choosing while quitting or starting** → ignored until running/ended → Task 2.
5. **Recent folder that no longer exists** → shown disabled or dropped → Task 1.

---

### Task 1: Kit catalog and menu builders

**Files:**
- Create: `Sources/SwiftStarKit/EngineModelCatalog.swift` (decode, `MenuItem`
  builders, recent folders)
- Create: `fixtures/engine/models.json` (a sample in the spec's shape: five
  models incl. one not on this Mac, one that doesn't fit, one not interactive)
- Test: `Tests/SwiftStarKitTests/EngineModelCatalogTests.swift`

**Interfaces (produces):**
- `public struct EngineModelList: Decodable, Equatable, Sendable` (+ `Model`);
  `static func decode(_ data: Data) -> Result<EngineModelList, CatalogError>`.
- `public struct MenuChoice<Value>: Equatable { title; value; isChecked; disabledReason: String? }`
  (or separate item types) — the implementer's choice, documented in the file.
- `ModelMenu.items(list: EngineModelList?, settingsID: String, loadedID: String?) -> [...]`
- `ContextMenu.items(list: EngineModelList?, modelID: String?, settingsContext: Int, loaded: Int?) -> [...]`
- `RecentWorkspaces.updated(_ list: [String], adding: String, cap: Int = 5) -> [String]`

- [ ] **Step 1: failing tests:** `decodesSampleList`, `ignoresUnknownKeys`,
  `wrongSchemaVersionFails`, `modelMenuTicksSettingsChoice`,
  `modelMenuDisablesWithReason` (three reasons), `modelMenuFallbackWithoutList`,
  `contextMenuListsMeasuredAndRoundSizes` (round sizes ≤ 2 × largest
  measured), `contextMenuFallbackRoundSizes`, `recentWorkspacesDedupesCapsOrders`.
- [ ] **Step 2:** red → implement → `swift test` green → commit.

### Task 2: Catalog loading and the toolbar

**Files:**
- Modify: `Sources/SwiftStarAppKit/` — add `EngineModelCatalogLoader.swift`
  (runs `<exe> models --json`, 10 s timeout, returns list or reason)
- Modify: `fixtures/engine/fake-ds4-dogfood` (`models --json` prints
  `FAKE_ENGINE_MODELS` file or fails when `FAKE_ENGINE_MODELS_FAIL=1`)
- Modify: `Sources/SwiftStar/EngineController.swift` (load catalog at launch
  and when the engine path changes; `select(workspace:)`,
  `select(modelID:)`, `select(contextSize:)` — write settings, restart if a
  session runs and the value changed; remove `restartNeeded`/`restart`
  button path; record recent workspaces)
- Modify: `Sources/SwiftStar/AgentView.swift` (three `Menu` buttons in the
  capsule; "Other…" and "Custom…" small sheets/alerts with a text field)
- Modify: `Sources/SwiftStar/SettingsView.swift` (remove Model and Context
  fields)
- Test: `Tests/SwiftStarIntegrationTests/EngineModelCatalogLoaderTests.swift`

- [ ] **Step 1: failing tests:** `loaderReadsFakeList`, `loaderFallsBackOnFailure`,
  `loaderFallsBackOnTimeout` (fake sleeps past a 0.5 s test timeout).
- [ ] **Step 2:** implement; `swift build`, both tiers, `just app` green; commit.

### Task 3: Live check and close (controller)

- [ ] **Step 1:** launch against today's engine → fallback menus, note row;
  choose a context from the menu → session restarts with the new
  `--context-size`; choose a folder → restarts there. When ds4-engine ships
  `models --json`, re-check the full list.
- [ ] **Step 2:** ROADMAP P29.10 row step + Backlog "model dropdown" entry
  resolved (engine side stays in "Engine requests" until shipped); plan
  `## Result`, `lifecycle: closed`; `just lint-docs` green; commit.

## Result

Closed 2026-09-29. Tasks 1–2 in one Sonnet dispatch; one code review and
five fix rounds, three of them from the owner's look at the running app.

- **Commits:** `5ed8a93` (T1), `2272f1f` (T2), `7d8739f` (loader SIGKILL and
  bounded read, path compare, load once, divergence cue), `5039583` (separate
  capsules via `ToolbarSpacer(.fixed)`, sidebar toggle trailing,
  `runs_in_tui`, real capture fixture), `ffe2e1b` (note once per engine path,
  actionable missing-command reason), `ab02a23` (label inset), `52b9325`
  (exit text drops the `Session artifacts:` line).
- **Diverged:** ds4-engine named the per-model key `runs_in_tui`, not
  `interactive`; its `default_model_id` falls back to Laguna XS when nothing
  is saved. `fixtures/engine/models-real.json` is a real capture (home paths
  anonymised) beside the hand-written `models.json`.
- **Live:** owner confirmed three separate menu buttons, the trailing sidebar
  toggle, and a model menu listing every engine model, against ds4-engine's
  `feat/models-json` worktree (TUI.33 `baeb297f`, linked with `lld`).
- **Deferred minors:** the select/restart logic in `EngineController` has no
  automated test; a grandchild holding the catalog pipe can leave the reader
  thread lingering; a `start()` during another path's in-flight load can
  claim the wrong note; stderr's "last line" is the last line of its first
  4 KiB.
