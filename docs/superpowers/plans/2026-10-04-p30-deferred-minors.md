---
phase: P
cycle: P30-deferred-minors
lifecycle: closed
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

- [x] **Step 1: failing tests:**
  - `loaderReapsOnTimeout` — with `FAKE_ENGINE_PIDFILE`,
    `FAKE_ENGINE_MODELS_SLEEP_MS` past the loader's timeout, and
    `FAKE_ENGINE_IGNORE_SIGTERM`: after `load()` returns `.timedOut`, the
    pidfile's pid no longer exists (`kill(pid, 0) != 0`).
  - `loaderReportsStderrTailBeyond4KiB` — with
    `FAKE_ENGINE_MODELS_HUGE_STDERR=1`: the `.failed` error's message ends
    with the fixture's distinct final line, not a filler line.
- [x] **Step 2:** red → implement → `swift test` and
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

- [x] **Step 1: failing tests:**
  - `cacheKeySameePathSameMtimeIsValid` / `cacheKeyChangedMtimeInvalidates` /
    `cacheKeyChangedPathInvalidates` — fast tier, the pure key type only.
  - `catalogRefetchesWhenEngineUpgradedInPlace` (integration, depends on
    Task 3's test-target wiring) — copy the fake engine to a temp path, load
    once, touch the temp file's modification date, call
    `loadCatalogIfNeeded()` again, assert a second subprocess ran (e.g. via
    `FAKE_ENGINE_ARGV_LOG` or a call-count hook).
- [x] **Step 2:** red → implement → both test tiers green → commit.

### Task 3: Mid-turn restart test (test-target wiring + app)

**Files:**
- Modify: `Package.swift` (add `"SwiftStar"` to `SwiftStarIntegrationTests`'s
  dependencies so `EngineController` is `@testable import`-able)
- New: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`

**Interfaces:** none new; exercises `EngineController.select(modelID:)` and
`restartIfRunning()` as already written.

- [x] **Step 1: failing test:**
  - `selectingModelMidTurnEndsTurnAndRestarts` — start a session against the
    fake engine on a fixture that pauses mid-turn (e.g. `tool-read.ndjson` at
    its `tool_start`), call `select(modelID:)` with a different id, assert
    the running session quits and a new session starts with the new model
    (via `FAKE_ENGINE_ARGV_LOG` showing two spawns, the second with
    `--model-id` for the new value).
- [x] **Step 2:** red → confirm it passes unmodified (this pins existing,
  intentional behavior — no production code change expected) → commit.

### Task 4: Close

- [x] **Step 1:** ROADMAP P30 row → "done"; plan `## Result`,
  `lifecycle: closed`; `just lint-docs` green; commit.

## Result

Closed 2026-10-04. All three fix tasks landed; scope narrowed once on one
sub-item, found two Foundation gotchas along the way.

- **Commits:** `60846ff` (Task 1), `bddf62d` (test-target wiring, pulled out
  ahead of Tasks 2/3 since both needed it), `51b007c` (Task 2), `f6cff6b`
  (Task 3).
- **Task 1, scaled back:** the stderr-tail fix (`.prefix(4096)` →
  `.suffix(4096)`) has a real failing-then-passing test. The reap-on-timeout
  fix (close `errHandle`, call `waitUntilExit()`) does not: the branch it
  touches is only reachable when a grandchild holds the pipe open (confirmed
  by tracing the timing — a single killed process always closes its pipe a
  full second before the read deadline, by design, per the code's own
  comment). The grandchild is invisible to our `Process` object, so the fix's
  only observable effect is unblocking a background GCD thread, which isn't
  black-box testable without new instrumentation. Applied the fix on
  inspection; did not write a test that would pass whether or not it was
  applied.
- **Found while testing (not in the original plan):** `EngineController` had
  zero test coverage before this cycle — it lives in the `SwiftStar` app
  target, which neither test target depended on. Fixed once, ahead of Tasks 2
  and 3, by adding `"SwiftStar"` to `SwiftStarIntegrationTests`'s
  dependencies (safe because it uses `@main`, not a top-level `main.swift`).
- **Two Foundation gotchas, both discovered empirically while red/green
  testing Tasks 2 and 3:**
  1. `Process.environment = nil` does not see `setenv()` calls made after the
     test process starts — it snapshots earlier (traced to the `Suite`'s
     `.enabled(if:)` trait reading `ProcessInfo.processInfo.environment`
     before the test body runs). `EngineController` never forwards an
     explicit environment to `EngineSession`/`EngineModelCatalogLoader`, so
     the env-var-driven fake pattern `EngineModelCatalogLoaderTests` uses
     doesn't carry over. Worked around with self-contained generated fake
     scripts (call-log and argv-log paths baked into the script text) instead
     of environment variables, for both new tests.
  2. `UserDefaults.standard` is the real, persistent domain in this test
     environment — not an isolated suite. An earlier failed run of the
     mid-turn restart test left `engineModelID` set to `"a-different-model"`,
     which silently no-op'd `select(modelID:)`'s `id != modelID` guard on the
     next run. Fixed by resetting touched keys to a known baseline before
     each test runs, not just restoring them after.
- **Confirmed red→green by hand** for both `catalogRefetchesWhenEngineUpgradedInPlace`
  (reverted `EngineController.swift` to its pre-fix path-only cache, watched
  it fail only on the post-upgrade assertion, restored) and
  `selectingModelWhileRunningEndsTurnAndRestarts` (broke `restartIfRunning`'s
  guard with `guard false else { return }`, watched it time out and fail,
  restored).
- **Descoped:** the loader's SIGKILL pid-reuse window (spec's "Out of
  scope", unchanged). The real-engine fixture recapture owed from P29.3 was
  already out of P30/P31's scope going in (Backlog, GPU-gated).
- Both test tiers green throughout: 135 fast, 26 integration.
