# P24.2 Read-Guard Re-decision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the `.pool` `readCache` (unify reads on the windowed path), and make `swiftstar-analyze rereads` report same-window re-reads instead of the misleading same-path count — the two code changes behind the spec's verdict that the read-guard does not return.

**Architecture:** Two deletions-plus-one-addition, no live runs. Task 1 deletes the `readCache` policy field, its storage, and the `.pool` branch of `readResult`, so `.pool` and `.app` share one windowed read path. Task 2 extracts a pure `ReadRepeatCounter` into `SwiftStarKit` and re-points the `rereads` verb's counting at it. Task 3 records the decisions in the docs.

**Tech Stack:** Swift 6, `SwiftStarKit` + `SwiftStarAppKit` + `swiftstar-analyze`, Swift Testing (`import Testing`). No model, no network, no subprocess, no engine change, no recapture.

**Spec:**
[`2026-08-30-p24-2-read-guard-redecision-design.md`](../specs/2026-08-30-p24-2-read-guard-redecision-design.md)
(decisions D1–D3; this plan argues from the spec, so the spec travels with it — executors read both).

## Global Constraints

- **Zero engine/wire work.** No tool name, no wire field, no engine change, no
  golden recapture (spec binding rule 1). Swift sources, tests, docs only.
- **Red-first** (BRIEF.md rule 2): every changed or new test is shown failing
  before the fix lands. Where the first red is a compile failure (a new type
  that doesn't exist yet), that is the expected red.
- **A refusal test has a sibling success test** (rule 3).
- **No post-hoc numeric thresholds** (rule 4): `rereads` reports a count, never
  a pass/fail bar. Do not add one.
- **An instrument change is recorded, not hidden** (rule 5): Task 1 is an
  agenttest-instrument change; Task 3's ROADMAP edit says so explicitly.
- **Fast tier only** — both tasks' tests run under plain `swift test` (the
  `HostToolExecutorTests` suite is not `SWIFTSTAR_INTEGRATION`-gated; it is
  pure file I/O).
- The treatment/control capture dirs named below are committed and must not be
  regenerated.

---

### Task 1: Retire the `.pool` `readCache`

**Files:**
- Modify: `Sources/SwiftStarAppKit/HostToolExecutor.swift` (Policy struct, storage, `readResult`)
- Modify: `Sources/SwiftStarAppKit/PoolOrchestrator.swift` (one comment)
- Test: `Tests/SwiftStarIntegrationTests/HostToolExecutorTests.swift`

**Interfaces:**
- Consumes: `Policy` (`:47`), `readResult` (`:202`), test helpers `makeWorkspace()`/`request(_:_:workspace:path:)`/`param(_:_:)`/`writeLines(_:_:prefix:)` — all existing.
- Produces: `Policy` with **no** `readCache` member and a 5-argument `init` (no `readCache`); `Policy.app` and `Policy.pool(vettedCommands:)` unchanged in shape except the removed argument; `readResult` with a single windowed path and **no** `if policy.readCache` fork. `SHA256`/`CryptoKit` stay (still used by `writeResult` at `:407`).

- [ ] **Step 1: Update the three pool-read tests and add one, so they fail against the current code**

In `Tests/SwiftStarIntegrationTests/HostToolExecutorTests.swift`:

(a) Replace the `// MARK: - read/more: pool policy (per-turn cache, folded generic error)` section header comment with:

```swift
    // MARK: - read/more: pool policy (P24.2 — unified windowed path, no cache)
```

(b) Replace `poolPolicyReadCachesAnUnchangedFile` (body) with:

```swift
    @Test func poolPolicyReadHasNoCache() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "hello".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .pool(vettedCommands: []))
        let req = request("read", [], workspace: ws, path: "a.txt")

        let first = executor.execute(req)
        let second = executor.execute(req)
        // P24.2 (D2): the `.pool` hash cache is retired — reads unify on the
        // windowed path, so an unchanged re-read serves the window again, never
        // "(unchanged since last read)".
        #expect(first.text.hasSuffix(": lines 1-1 of 1\n1 hello\n"))
        #expect(second.text == first.text)
    }
```

(c) Delete `poolPolicyReadCacheInvalidatesOnChange` entirely (the "changed file serves new content" behavior is already pinned by the unified path's existing tests).

(d) Replace `poolPolicyReadMissingFileUsesGenericMessageWithNoPath` with:

```swift
    @Test func poolPolicyReadMissingFileNamesThePathInTheError() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let executor = HostToolExecutor(policy: .pool(vettedCommands: []))
        let result = executor.execute(request("read", [], workspace: ws, path: "missing.txt"))
        #expect(!result.ok)
        #expect(result.text.contains("missing.txt"))
    }
```

(e) Add (after (b)):

```swift
    @Test func poolPolicyReadHonorsWindows() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try writeLines(40, ws)
        let executor = HostToolExecutor(policy: .pool(vettedCommands: []))
        let r = executor.execute(request("read",
            [param("start_line", "10"), param("max_lines", "3")],
            workspace: ws, path: "big.txt"))
        #expect(r.ok)
        #expect(r.text.contains("lines 10-12 of 40; continue_offset=13;"))
        #expect(r.text.contains("10 l10\n11 l11\n12 l12\n"))
        #expect(!r.text.contains("13 l13"))
    }
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `swift test --filter HostToolExecutorTests`

Expected: FAIL — `poolPolicyReadHasNoCache` (the `.pool` read still returns the bare `"hello"`, not the windowed format), `poolPolicyReadHonorsWindows` (whole file returned, no `lines 10-12 of 40` header), and `poolPolicyReadMissingFileNamesThePathInTheError` (`"error: could not read"` contains no path). The deleted test no longer appears.

- [ ] **Step 3: Delete the cache from `HostToolExecutor.swift`**

Four edits:

(a) `Policy` struct — remove the field and init parameter:

```swift
    public struct Policy: Sendable {
        public var readCache: Bool
        public var searchSupportsCaseSensitiveParam: Bool
        public var searchIncludesCountHeader: Bool
        public var createParentDirectoriesOnWrite: Bool
        public var bash: BashPolicy
        public var explicitBashStatusStopRefusal: Bool

        public init(readCache: Bool, searchSupportsCaseSensitiveParam: Bool,
                    searchIncludesCountHeader: Bool, createParentDirectoriesOnWrite: Bool,
                    bash: BashPolicy, explicitBashStatusStopRefusal: Bool) {
            self.readCache = readCache
            self.searchSupportsCaseSensitiveParam = searchSupportsCaseSensitiveParam
```
becomes:

```swift
    public struct Policy: Sendable {
        public var searchSupportsCaseSensitiveParam: Bool
        public var searchIncludesCountHeader: Bool
        public var createParentDirectoriesOnWrite: Bool
        public var bash: BashPolicy
        public var explicitBashStatusStopRefusal: Bool

        public init(searchSupportsCaseSensitiveParam: Bool,
                    searchIncludesCountHeader: Bool, createParentDirectoriesOnWrite: Bool,
                    bash: BashPolicy, explicitBashStatusStopRefusal: Bool) {
            self.searchSupportsCaseSensitiveParam = searchSupportsCaseSensitiveParam
```
(keep the remaining `self.*` assignments and the closing brace unchanged).

(b) The `.app` and `.pool` factories — drop the `readCache:` argument:

```swift
        public static let app = Policy(
            readCache: false, searchSupportsCaseSensitiveParam: true,
            searchIncludesCountHeader: true, createParentDirectoriesOnWrite: false,
            bash: .allowAny, explicitBashStatusStopRefusal: true)
```
becomes:
```swift
        public static let app = Policy(
            searchSupportsCaseSensitiveParam: true,
            searchIncludesCountHeader: true, createParentDirectoriesOnWrite: false,
            bash: .allowAny, explicitBashStatusStopRefusal: true)
```

```swift
        /// `PoolOrchestrator`'s pool-worker policy for one phase. Construct a
        /// fresh instance per phase (like the old `readCache`/`vettedCommands`
        /// reset at the top of `runPhase`) — `vettedCommands` is the packet's
        /// validation/self-test commands for that phase only.
        public static func pool(vettedCommands: [String]) -> Policy {
            Policy(readCache: true, searchSupportsCaseSensitiveParam: false,
                  searchIncludesCountHeader: false, createParentDirectoriesOnWrite: true,
                  bash: .vettedOnly(vettedCommands), explicitBashStatusStopRefusal: false)
        }
```
becomes:
```swift
        /// `PoolOrchestrator`'s pool-worker policy for one phase. Construct a
        /// fresh instance per phase (resetting the vetted-commands allowlist and
        /// the read continuation map with the instance) — `vettedCommands` is
        /// the packet's validation/self-test commands for that phase only.
        public static func pool(vettedCommands: [String]) -> Policy {
            Policy(searchSupportsCaseSensitiveParam: false,
                  searchIncludesCountHeader: false, createParentDirectoriesOnWrite: true,
                  bash: .vettedOnly(vettedCommands), explicitBashStatusStopRefusal: false)
        }
```

(c) The storage property:

```swift
    private let policy: Policy
    private let lock = NSLock()
    private var readCacheStorage: [String: String] = [:]
```
becomes:
```swift
    private let policy: Policy
    private let lock = NSLock()
```

(d) The `readResult` branch — delete the whole `if policy.readCache { … }` block and its comment:

```swift
    private func readResult(_ request: ToolExecutionRequest) -> ToolExecutionResult {
        if policy.readCache {
            // The pool worker's shape: confinement and the read itself share
            // one guard and one generic message (no path named) — an
            // unchanged re-read answers "(unchanged since last read)" instead
            // of re-paying the context cost.
            guard let path = HostToolConfinement.realPath(request),
                  let data = FileManager.default.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8) else {
                return ToolExecutionResult(ok: false, text: "error: could not read")
            }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let unchanged: Bool = lock.withLock {
                if readCacheStorage[path] == hash { return true }
                readCacheStorage[path] = hash
                return false
            }
            if unchanged {
                return ToolExecutionResult(ok: true, text: "(unchanged since last read)")
            }
            return ToolExecutionResult(ok: true, text: text)
        }
        // P24.1: the app's shape — windowed, in the engine's format
        // (ds4_agent.c:8102-8174), byte-budgeted so the responder's condenser
        // never has to cut it (D2). Confinement and the read stay separate
        // guards, each with its own message (the read failure names the path).
```
becomes:
```swift
    private func readResult(_ request: ToolExecutionRequest) -> ToolExecutionResult {
        // P24.2 (D2): one read path for both policies — windowed, in the
        // engine's format (ds4_agent.c:8102-8174), byte-budgeted so the
        // responder's condenser never has to cut it (D2). The `.pool` hash
        // cache was retired: its whole-file delivery starved the model and its
        // "(unchanged since last read)" was dishonest once delivery is
        // partial. Confinement and the read stay separate guards, each with
        // its own message (the read failure names the path).
```

- [ ] **Step 4: Update the `PoolOrchestrator.swift` comment**

```swift
    /// Item 4 (P22 cleanup): the host-tool execution itself now lives once, in
    /// `HostToolExecutor`, shared with `AgentController` — a fresh instance
    /// per phase (the `.pool` policy's per-turn read cache and vetted-commands
    /// allowlist), mirroring the old `readCache.removeAll()` +
    /// `vettedCommands = [...]` reset at the top of `runPhase`.
    private var hostToolExecutor = HostToolExecutor(policy: .pool(vettedCommands: []))
```
becomes:
```swift
    /// Item 4 (P22 cleanup): the host-tool execution itself now lives once, in
    /// `HostToolExecutor`, shared with `AgentController` — a fresh instance
    /// per phase (resetting the `.pool` policy's vetted-commands allowlist and
    /// the read continuation map with the instance), mirroring the old
    /// `vettedCommands = [...]` reset at the top of `runPhase`.
    private var hostToolExecutor = HostToolExecutor(policy: .pool(vettedCommands: []))
```

- [ ] **Step 5: Run the suite to verify it passes**

Run: `swift test --filter HostToolExecutorTests`
Expected: PASS — the three new/updated tests pass; every pre-existing `.app` read test is unchanged and green.

- [ ] **Step 6: Run the full fast tier**

Run: `swift test`
Expected: all fast-tier suites green (no `SWIFTSTAR_INTEGRATION=1`). If any suite outside `HostToolExecutorTests` fails, it referenced `readCache` — grep for it and fix before committing.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftStarAppKit/HostToolExecutor.swift Sources/SwiftStarAppKit/PoolOrchestrator.swift Tests/SwiftStarIntegrationTests/HostToolExecutorTests.swift
git commit -m "P24.2: retire the .pool readCache (unify reads on the windowed path)"
```

---

### Task 2: `rereads` reports same-window repeats

**Files:**
- Create: `Sources/SwiftStarKit/ReadRepeatCounter.swift`
- Create: `Tests/SwiftStarKitTests/ReadRepeatCounterTests.swift`
- Modify: `Sources/swiftstar-analyze/main.swift` (`ReadRequest`, `readRequests`, `cmdRereads`)

**Interfaces:**
- Consumes: `ToolParam`, `WorkerId`, `PoolWireParser`, `AgentWireParser` (existing SwiftStarKit types); the capture dirs `captures/20260830-104542-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf` (treatment) and `captures/20260830-105947-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf` (control).
- Produces: `ReadWindowKey` (public struct: `startLine: Int?`, `maxLines: Int?`), `ReadRepeatReport` (+ nested `PathRow`, `RepeatedWindow`), `ReadRepeatCounter.summarize(_: [(path: String, window: ReadWindowKey)]) -> ReadRepeatReport`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiftStarKitTests/ReadRepeatCounterTests.swift`:

```swift
import Testing
@testable import SwiftStarKit

struct ReadRepeatCounterTests {
    @Test func identicalWindowReaskedCountsAsSameWindowReRead() {
        let reads = [
            (path: "a.swift", window: ReadWindowKey(startLine: 250, maxLines: 90)),
            (path: "a.swift", window: ReadWindowKey(startLine: 250, maxLines: 90)),
        ]
        let report = ReadRepeatCounter.summarize(reads)
        #expect(report.calls == 2)
        #expect(report.distinctPairs == 1)
        #expect(report.sameWindowRepeats == 1)
        #expect(report.paths.count == 1)
        #expect(report.paths[0].repeatedWindows == [
            ReadRepeatReport.RepeatedWindow(
                window: ReadWindowKey(startLine: 250, maxLines: 90), count: 2)
        ])
    }

    @Test func distinctWindowsOnOnePathAreNotRepeats() {
        // The 255/90 -> 257/90 walk-forward from the treatment capture: two
        // different windows of one file are healthy, not a same-window re-read.
        let reads = [
            (path: "a.swift", window: ReadWindowKey(startLine: 255, maxLines: 90)),
            (path: "a.swift", window: ReadWindowKey(startLine: 257, maxLines: 90)),
        ]
        let report = ReadRepeatCounter.summarize(reads)
        #expect(report.sameWindowRepeats == 0)
        #expect(report.distinctPairs == 2)
        #expect(report.paths[0].repeatedWindows.isEmpty)
    }

    @Test func bareReadIsItsOwnWindow() {
        // The control's "4x bare" signature: three whole-file re-asks are three
        // same-window re-reads; a windowed read of the same path is a distinct
        // window, not a repeat of the bare read.
        let reads = [
            (path: "a.swift", window: ReadWindowKey(startLine: nil, maxLines: nil)),
            (path: "a.swift", window: ReadWindowKey(startLine: nil, maxLines: nil)),
            (path: "a.swift", window: ReadWindowKey(startLine: nil, maxLines: nil)),
            (path: "a.swift", window: ReadWindowKey(startLine: 1, maxLines: 80)),
        ]
        let report = ReadRepeatCounter.summarize(reads)
        #expect(report.calls == 4)
        #expect(report.distinctPairs == 2)
        #expect(report.sameWindowRepeats == 2)
    }

    @Test func sameWindowOnDifferentPathsAreNotRepeats() {
        let reads = [
            (path: "a.swift", window: ReadWindowKey(startLine: 1, maxLines: 10)),
            (path: "b.swift", window: ReadWindowKey(startLine: 1, maxLines: 10)),
        ]
        let report = ReadRepeatCounter.summarize(reads)
        #expect(report.sameWindowRepeats == 0)
        #expect(report.distinctPairs == 2)
    }
}
```

- [ ] **Step 2: Run to verify the tests fail (compile error)**

Run: `swift test --filter ReadRepeatCounterTests`
Expected: FAIL — "cannot find type 'ReadWindowKey' in scope" (the new type does not exist yet). This is the expected first red.

- [ ] **Step 3: Create the pure counter**

Create `Sources/SwiftStarKit/ReadRepeatCounter.swift`:

```swift
import Foundation

/// The window identity of one `read` request, for same-window repeat counting.
/// A re-read is only redundant when the *same* window of the same path is asked
/// again; distinct windows on one path are a healthy walk, not waste.
public struct ReadWindowKey: Hashable, Sendable, CustomStringConvertible {
    public let startLine: Int?
    public let maxLines: Int?

    public init(startLine: Int?, maxLines: Int?) {
        self.startLine = startLine
        self.maxLines = maxLines
    }

    public var description: String {
        "\(startLine.map(String.init) ?? "-")/\(maxLines.map(String.init) ?? "-")"
    }
}

/// The same-window repeat count for a capture's `read` calls.
public struct ReadRepeatReport: Equatable, Sendable {
    public struct RepeatedWindow: Equatable, Sendable {
        public let window: ReadWindowKey
        public let count: Int
    }
    public struct PathRow: Equatable, Sendable {
        public let path: String
        public let calls: Int
        public let distinctWindows: Int
        public let repeatedWindows: [RepeatedWindow]
    }
    public let calls: Int
    public let distinctPairs: Int
    public let sameWindowRepeats: Int
    public let paths: [PathRow]
}

/// P24.2 (D3): the same-window repeat count, extracted pure so it is fast-tier
/// testable rather than buried in `swiftstar-analyze/main.swift`.
public enum ReadRepeatCounter {
    /// One `(path, window)` per `read` call (`more` is not passed here — a
    /// continuation is never a re-read). Returns the headline numbers and the
    /// per-path window table. Pure and deterministic.
    public static func summarize(
        _ reads: [(path: String, window: ReadWindowKey)]
    ) -> ReadRepeatReport {
        var seen = Set<String>()
        var byPath: [String: (calls: Int, windows: [ReadWindowKey: Int])] = [:]
        for (path, window) in reads {
            let start = window.startLine.map(String.init) ?? "-"
            let max = window.maxLines.map(String.init) ?? "-"
            seen.insert("\(path)\u{0}\(start)\u{0}\(max)")
            byPath[path, default: (0, [:])].calls += 1
            byPath[path, default: (0, [:])].windows[window, default: 0] += 1
        }
        let rows: [ReadRepeatReport.PathRow] = byPath
            .map { entry in
                let (path, data) = entry
                let repeated = data.windows
                    .filter { $0.value > 1 }
                    .map { ReadRepeatReport.RepeatedWindow(window: $0.key, count: $0.value) }
                    .sorted { ($0.window.startLine ?? 0, $0.window.maxLines ?? 0)
                              < ($1.window.startLine ?? 0, $1.window.maxLines ?? 0) }
                return ReadRepeatReport.PathRow(
                    path: path, calls: data.calls,
                    distinctWindows: data.windows.count,
                    repeatedWindows: repeated)
            }
            .sorted { $0.calls > $1.calls }
        return ReadRepeatReport(
            calls: reads.count,
            distinctPairs: seen.count,
            sameWindowRepeats: reads.count - seen.count,
            paths: rows)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ReadRepeatCounterTests`
Expected: PASS — 4/4.

- [ ] **Step 5: Rewire `main.swift`**

Three edits in `Sources/swiftstar-analyze/main.swift`:

(a) `ReadRequest` struct and its doc comment — replace `windowed: Bool` with the window identity:

```swift
/// A `read`/`more` tool_request reduced to what the measurement cares about:
/// the worker (which session read it), the path (what it read), and the window
/// identity for same-window repeat counting (P24.2, D3). A `more` has no window
/// — it is a continuation, never a re-read — so its `window` is `nil`.
struct ReadRequest {
    let worker: WorkerId
    let path: String
    let window: ReadWindowKey?
}
```

(b) `record` inside `readRequests` — parse `start_line`/`max_lines` into the key:

```swift
    func record(worker: WorkerId, name: String, params: [ToolParam]) {
        var path = ""
        var startLine: Int? = nil
        var maxLines: Int? = nil
        for p in params {
            if p.name == "path" { path = p.value }
            if p.name == "start_line" { startLine = Int(p.value) }
            if p.name == "max_lines" { maxLines = Int(p.value) }
        }
        if path.isEmpty { path = lastPath[worker] ?? "" }
        guard !path.isEmpty else { return }
        lastPath[worker] = path
        let window: ReadWindowKey? = (name == "more")
            ? nil
            : ReadWindowKey(startLine: startLine, maxLines: maxLines)
        out.append(ReadRequest(worker: worker, path: path, window: window))
    }
```

(c) `cmdRereads` and its doc comment — report the same-window count:

```swift
/// P24.2 (D3) read evidence: how many `read` calls each session made, how many
/// were same-window re-reads — the *same* `(path, start_line, max_lines)` asked
/// again — and the top offenders, with repeated windows listed per path.
///
/// Same-window is the number that decides the read-guard question; the old
/// same-path count (`calls - distinct paths`) labelled the model's healthy walk
/// across a file as redundant. `more` is attributed to a path but never counted
/// as a re-read (a continuation is not a repeat).
func cmdRereads(_ dir: URL) {
    let reads = readRequests(dir)
    guard !reads.isEmpty else {
        print("no read/more tool_requests in \(dir.lastPathComponent)")
        return
    }
    let workers = Set(reads.map { $0.worker }).sorted()
    for worker in workers {
        let mine = reads.filter { $0.worker == worker }
        let moreCount = mine.filter { $0.window == nil }.count
        let report = ReadRepeatCounter.summarize(
            mine.compactMap { r in r.window.map { (path: r.path, window: $0) } })
        let moreSuffix = moreCount > 0 ? " [\(moreCount) more call(s)]" : ""
        print("worker \(worker.rawValue): \(report.calls) read call(s), \(report.distinctPairs) distinct (path, window) pair(s) — \(report.sameWindowRepeats) same-window re-read(s)\(moreSuffix)")
        for row in report.paths where row.calls > 1 {
            print(String(format: "  %3d  %@  [%d distinct window(s)]",
                         row.calls, row.path, row.distinctWindows))
            for item in row.repeatedWindows {
                print("          \(item.count)x  start_line=\(item.window.startLine.map(String.init) ?? "-") max_lines=\(item.window.maxLines.map(String.init) ?? "-")")
            }
        }
    }
}
```

Also update the `readRequests` doc comment's last sentence — it still says reads are "flagged windowed". Replace that sentence with: *"Windowed reads carry their `(start_line, max_lines)` identity for same-window counting; `more` carries `nil`."*

- [ ] **Step 6: Verify against both committed captures**

Run: `swift run swiftstar-analyze rereads 20260830-104542-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`
Expected: `worker 0: 16 read call(s), 16 distinct (path, window) pair(s) — 0 same-window re-read(s)` — the treatment capture's 8 distinct `AgentView.swift` windows are no longer called "redundant".

Run: `swift run swiftstar-analyze rereads 20260830-105947-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`
Expected: `worker 0: 11 read call(s), 8 distinct (path, window) pair(s) — 3 same-window re-read(s) [1 more call(s)]` — the control's three bare whole-file re-asks are the same-window repeats.

- [ ] **Step 7: Run the full fast tier**

Run: `swift test`
Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiftStarKit/ReadRepeatCounter.swift Tests/SwiftStarKitTests/ReadRepeatCounterTests.swift Sources/swiftstar-analyze/main.swift
git commit -m "P24.2: rereads reports same-window re-reads, not same-path"
```

---

### Task 3: Record the decisions in the docs

**Files:**
- Modify: `ROADMAP.md` (P24 status cell)
- Modify: `docs/superpowers/specs/2026-08-30-p24-1-window-honoring-reads-design.md` (scope pointers)
- Modify: `docs/superpowers/specs/2026-08-30-p24-1-read-guard-design.md` (resolution pointer)

- [ ] **Step 1: ROADMAP P24 status cell**

Replace:

```
**P24.1 CLOSED 2026-08-30** (merged to main, 799 tests; paired control reproduced the loop; numeric falsifier post-hoc; protocol committed). **P24.2 + instrument-reconciliation cleanup cycle remain**
```

with:

```
**P24.1 CLOSED 2026-08-30** (merged to main, 799 tests; paired control reproduced the loop; numeric falsifier post-hoc; protocol committed). **P24.2 decided 2026-08-30** — the read-guard does not return (0 same-window re-reads post-windowing, 3 in the control; every benefit case empty or self-contradictory) and the `.pool` `readCache` is retired (reads unify on the windowed path — an agenttest-instrument change, recorded for the cleanup cycle's keep/drop/port table). See [`2026-08-30-p24-2-read-guard-redecision-design.md`](docs/superpowers/specs/2026-08-30-p24-2-read-guard-redecision-design.md). **Only the instrument-reconciliation cleanup cycle remains**
```

- [ ] **Step 2: Window-honoring spec — resolve the two deferred scope bullets**

In `docs/superpowers/specs/2026-08-30-p24-1-window-honoring-reads-design.md`, the **Out** section's two bullets end with "reopens as **P24.2**…" and "reopens with P24.2, which decides both together." Append to the end of each bullet:

```
(→ decided 2026-08-30 in
[`2026-08-30-p24-2-read-guard-redecision-design.md`](2026-08-30-p24-2-read-guard-redecision-design.md):
the guard does not return, and the `readCache` is retired.)
```

- [ ] **Step 3: Superseded read-guard spec — point at the resolution**

In `docs/superpowers/specs/2026-08-30-p24-1-read-guard-design.md`, the "Why this was withdrawn" paragraph ends with "The read guard is not cancelled — it moves to **P24.2**, to be re-decided against a measurement taken after windowing lands, together with the pool `readCache`, which has the same bug class." Append:

```
Resolved 2026-08-30: the re-decision
([`2026-08-30-p24-2-read-guard-redecision-design.md`](2026-08-30-p24-2-read-guard-redecision-design.md))
retired the guard (0 same-window re-reads post-windowing) and retired the
`readCache`.
```

- [ ] **Step 4: Commit**

```bash
git add ROADMAP.md docs/superpowers/specs/2026-08-30-p24-1-window-honoring-reads-design.md docs/superpowers/specs/2026-08-30-p24-1-read-guard-design.md
git commit -m "P24.2: record the re-decision (guard retired, readCache retired)"
```
