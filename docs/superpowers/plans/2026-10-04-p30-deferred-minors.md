---
phase: P
cycle: P30-deferred-minors
lifecycle: active
---

# P30 deferred minors implementation plan

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** close P29.10's four Backlog items — loader timeout reaping, the
stderr-tail truncation bug, the catalog's once-per-path cache, and the
untested mid-turn restart path — all against the fake engine, no live
`ds4-dogfood` needed.

**Spec:** `docs/superpowers/specs/2026-10-04-p30-deferred-minors-design.md`

## Global constraints

- Swift 6; existing isolation annotations unchanged.
- No behavior change to the mid-turn restart decision itself (Task 3 adds a
  test, not a new confirmation step).
- The loader's SIGKILL pid-reuse window stays out of scope (spec's "Out of
  scope").
- Commit with the attribution line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.

## Review focus

1. **Timeout branch must not leave a dangling reader thread** → Task 1.
2. **Stderr tail must be the true last line past 4 KiB** → Task 1.
3. **Cache invalidation must trigger on mtime change with an unchanged path**
   → Task 2.
4. **Mid-turn pick must still end the turn and start the new session** → Task 3.

---

### Task 1: Loader robustness (AppKit)

**Files:**
- Modify: `Sources/SwiftStarAppKit/EngineModelCatalogLoader.swift` (timeout
  branch closes `errHandle` and calls `process.waitUntilExit()` before
  returning; `errBox.value.prefix(4096)` → `.suffix(4096)`)
- Modify: `fixtures/engine/fake-ds4-dogfood` (write `FAKE_ENGINE_PIDFILE`
  before the `models` mode branch, not after it, so `models` mode is covered
  too; add `FAKE_ENGINE_MODELS_HUGE_STDERR=1` — writes over 4 KiB of filler
  then a distinct final line, exit 2)
- Test: `Tests/SwiftStarIntegrationTests/EngineModelCatalogLoaderTests.swift`

**Interfaces:** no public signature changes.

- [ ] **Step 1: failing tests:**
  - `loaderReapsOnTimeout` — with `FAKE_ENGINE_PIDFILE`,
    `FAKE_ENGINE_MODELS_SLEEP_MS` past the loader's timeout, and
    `FAKE_ENGINE_IGNORE_SIGTERM`: after `load()` returns `.timedOut`, the
    pidfile's pid no longer exists (`kill(pid, 0) != 0`).
  - `loaderReportsStderrTailBeyond4KiB` — with
    `FAKE_ENGINE_MODELS_HUGE_STDERR=1`: the `.failed` error's message ends
    with the fixture's distinct final line, not a filler line.
- [ ] **Step 2:** red → implement → `swift test` and
  `SWIFTSTAR_INTEGRATION=1 swift test` green → commit.

### Task 2: Catalog cache keyed by path and modification date (Kit + app)

**Files:**
- New: a small, fast-testable type in `Sources/SwiftStarKit/` comparing two
  `(path: String, modifiedAt: Date?)` pairs for cache-validity (name at
  implementer's discretion, e.g. `CatalogCacheKey`)
- Modify: `Sources/SwiftStar/EngineController.swift`
  (`catalogExecutable: String?` → a `CatalogCacheKey?`; `loadCatalogIfNeeded`
  and `loadCatalog` compare the full key, reading the resolved path's
  modification date via `FileManager`)
- Test: a new fast-tier test file for the cache-key type;
  `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift` (see Task 3 —
  shares its test-target wiring)

**Interfaces (produces):** the cache-key type's equality; `EngineController`'s
existing `loadCatalogIfNeeded()`/`loadCatalog()` signatures unchanged.

- [ ] **Step 1: failing tests:**
  - `cacheKeySameePathSameMtimeIsValid` / `cacheKeyChangedMtimeInvalidates` /
    `cacheKeyChangedPathInvalidates` — fast tier, the pure key type only.
  - `catalogRefetchesWhenEngineUpgradedInPlace` (integration, depends on
    Task 3's test-target wiring) — copy the fake engine to a temp path, load
    once, touch the temp file's modification date, call
    `loadCatalogIfNeeded()` again, assert a second subprocess ran (e.g. via
    `FAKE_ENGINE_ARGV_LOG` or a call-count hook).
- [ ] **Step 2:** red → implement → both test tiers green → commit.

### Task 3: Mid-turn restart test (test-target wiring + app)

**Files:**
- Modify: `Package.swift` (add `"SwiftStar"` to `SwiftStarIntegrationTests`'s
  dependencies so `EngineController` is `@testable import`-able)
- New: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`

**Interfaces:** none new; exercises `EngineController.select(modelID:)` and
`restartIfRunning()` as already written.

- [ ] **Step 1: failing test:**
  - `selectingModelMidTurnEndsTurnAndRestarts` — start a session against the
    fake engine on a fixture that pauses mid-turn (e.g. `tool-read.ndjson` at
    its `tool_start`), call `select(modelID:)` with a different id, assert
    the running session quits and a new session starts with the new model
    (via `FAKE_ENGINE_ARGV_LOG` showing two spawns, the second with
    `--model-id` for the new value).
- [ ] **Step 2:** red → confirm it passes unmodified (this pins existing,
  intentional behavior — no production code change expected) → commit.

### Task 4: Close

- [ ] **Step 1:** ROADMAP P30 row → "done"; plan `## Result`,
  `lifecycle: closed`; `just lint-docs` green; commit.

## Result

_(filled at close)_
