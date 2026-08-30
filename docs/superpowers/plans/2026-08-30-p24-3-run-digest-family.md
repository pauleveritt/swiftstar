# P24.3 run+digest family Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the deterministic run+digest family — `test`, `lint`, and digested `bash` — as pure digesters fed by a thin host-owned run/archive/assemble scaffold.

**Architecture:** Pure digesters in `SwiftStarKit` take a `CommandOutput` in and produce a `ToolDigest` (≤8000 bytes, so `ToolResultCondenser` is a no-op). A thin side-effecting `CommandToolRunner` in `SwiftStarAppKit` runs the host-derived command, writes the full output to `.swiftstar/runs/`, and assembles the `ToolExecutionResult`. `ToolCallbackResponder` admits `test`/`lint` via a new `deterministicTools` consent set (no shell toggle). One engine patch appends the two schemas under `--host-tools`, following the `dispatch` (divergence #12) precedent exactly.

**Tech Stack:** Swift 6 (Swift Testing, CryptoKit), the ds4 engine fork (C), uv/pytest/ruff, `swiftstar-analyze` for measurement.

**Spec:** [`docs/superpowers/specs/2026-08-30-p24-3-run-digest-family-design.md`](../specs/2026-08-30-p24-3-run-digest-family-design.md)

## Global Constraints

- **The model names no command string.** Every command is host-derived (`ProjectCommandResolver`); the model supplies at most a `test` `selector` (Evidence 1 of the spec).
- Every digest summary fits ≤8000 UTF-8 bytes — the condenser is a no-op.
- A digester is a **total function** over `CommandOutput` — never crashes; non-JSON stdout falls back to the text path / bounded summary.
- Selector is charset-validated to `[A-Za-z0-9_./:-]` (`:` is pytest's `::` node-id separator, shell-safe) before append; anything else is refused.
- `ok` for `test`/`lint` = "runner executed" (`!timedOut && exit != 127`); `bash` keeps `exit == 0 && !timedOut`. Failures live in the digest + `exitStatus`.
- Artifacts at `.swiftstar/runs/<tool>-<sha256-of-content>.log` (raw combined output); pruned to the last 20 per tool at write time.
- `outputDigest` = `sha256(stdout)`, `"sha256:"`-prefixed lowercase hex (matches `HostToolExecutor.bashResult`).
- Red-first TDD; every refusal-adjacent test gets a sibling success (rule 3).
- Capture selection uses `CaptureUsability.recordsWork`, never "completed turn".
- One fork-ledger row (#15); one golden recapture (standing rule).
- Engine schemas: `test`/`lint` appended in `agent_schemas_for` under `--host-tools` only; the DSML/DeepSeek block is untouched (the `dispatch` precedent).

## File Structure

**Create (pure, `SwiftStarKit`):**
- `Sources/SwiftStarKit/CommandOutput.swift` — the pure run result value.
- `Sources/SwiftStarKit/ToolDigest.swift` — the digester product + shared `sha256`.
- `Sources/SwiftStarKit/ProjectCommandResolver.swift` — host-owned command derivation + selector validation.
- `Sources/SwiftStarKit/TestDigest.swift` — XCTest + pytest parsers, one clustering core.
- `Sources/SwiftStarKit/RuffDigest.swift` — ruff JSON grouping.
- `Sources/SwiftStarKit/BashDigest.swift` — bounded summary, never raw.

**Create (side-effecting, `SwiftStarAppKit`):**
- `Sources/SwiftStarAppKit/CommandToolRunner.swift` — run/archive/assemble.

**Modify:**
- `Sources/SwiftStarKit/ToolCallbackResponder.swift` — add `deterministicTools` consent set + branch.
- `Sources/SwiftStarAppKit/HostToolExecutor.swift` — `test`/`lint` cases; `bashResult` → `assemble(kind: .bash)`.
- `pyproject.toml` — ruff dev dependency + minimal `[tool.ruff]` (Task 9).
- `external/ds4/ds4_agent.c` — schema constants, `agent_schemas_for` append, bash description tweak, C unit test (Task 10).
- `external/ds4/docs/fork-ledger.md` — row #15 (Task 10).
- `fixtures/agent/provenance.md` + `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}` — recapture (Task 11).

**Tests:**
- Fast: `Tests/SwiftStarKitTests/ToolDigestTests.swift`, `ProjectCommandResolverTests.swift`, `BashDigestTests.swift`, `TestDigestTests.swift`, `RuffDigestTests.swift`; modify `Tests/SwiftStarKitTests/ToolCallbackResponderTests.swift`.
- Integration: `Tests/SwiftStarIntegrationTests/CommandToolRunnerTests.swift` (new); modify `Tests/SwiftStarIntegrationTests/HostToolExecutorBashTests.swift`.

---

### Task 1: `CommandOutput` + `ToolDigest`

**Files:**
- Create: `Sources/SwiftStarKit/CommandOutput.swift`
- Create: `Sources/SwiftStarKit/ToolDigest.swift`
- Create: `Tests/SwiftStarKitTests/ToolDigestTests.swift`

**Interfaces:**
- Produces: `CommandOutput(stdout:stderr:exit:timedOut:)` and `ToolDigest(summary:command:artifactPath:outputDigest:)` + `static func ToolDigest.sha256(_ s: String) -> String`. Every later task consumes these exact signatures.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/ToolDigestTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct ToolDigestTests {
    @Test func commandOutputCarriesStreamsAndVerdict() {
        let out = CommandOutput(stdout: "o", stderr: "e", exit: 1, timedOut: false)
        #expect(out.stdout == "o")
        #expect(out.stderr == "e")
        #expect(out.exit == 1)
        #expect(!out.timedOut)
    }

    @Test func sha256IsDeterministicAndPrefixed() {
        let a = ToolDigest.sha256("hello")
        #expect(a == ToolDigest.sha256("hello"))
        #expect(a.hasPrefix("sha256:"))
        #expect(a != ToolDigest.sha256("world"))
        #expect(a.count == "sha256:".count + 64)
    }

    @Test func toolDigestCarriesAllFields() {
        let d = ToolDigest(summary: "s", command: "c", artifactPath: "p", outputDigest: "h")
        #expect(d.summary == "s")
        #expect(d.command == "c")
        #expect(d.artifactPath == "p")
        #expect(d.outputDigest == "h")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ToolDigestTests`
Expected: FAIL — "cannot find 'CommandOutput' in scope"

- [ ] **Step 3: Implement**

`Sources/SwiftStarKit/CommandOutput.swift`:

```swift
import Foundation

/// The pure shape of one completed command run, decoupled from
/// `SubprocessRunner.Result` (which lives in SwiftStarAppKit so the pure
/// digesters cannot depend on it). P24.3: the input to every digester.
public struct CommandOutput: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exit: Int32
    public let timedOut: Bool

    public init(stdout: String, stderr: String, exit: Int32, timedOut: Bool) {
        self.stdout = stdout
        self.stderr = stderr
        self.exit = exit
        self.timedOut = timedOut
    }
}
```

`Sources/SwiftStarKit/ToolDigest.swift`:

```swift
import Foundation
import CryptoKit

/// The product of one digest: the ≤8000-byte summary the model sees, the exact
/// command the host ran, the artifact path holding the full output, and a
/// deterministic digest of the stdout stream. Pure value; `sha256` is a pure
/// function of its input so digesters are testable byte-for-byte.
public struct ToolDigest: Equatable, Sendable {
    public let summary: String
    public let command: String
    public let artifactPath: String
    public let outputDigest: String

    public init(summary: String, command: String, artifactPath: String, outputDigest: String) {
        self.summary = summary
        self.command = command
        self.artifactPath = artifactPath
        self.outputDigest = outputDigest
    }

    /// sha256 of `s` as lowercase hex with a `sha256:` prefix, matching
    /// `HostToolExecutor.bashResult`'s digest format.
    public static func sha256(_ s: String) -> String {
        "sha256:" + SHA256.hash(data: Data(s.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ToolDigestTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/CommandOutput.swift Sources/SwiftStarKit/ToolDigest.swift Tests/SwiftStarKitTests/ToolDigestTests.swift
git commit -m "P24.3: CommandOutput + ToolDigest value types"
```

---

### Task 2: `ProjectCommandResolver`

**Files:**
- Create: `Sources/SwiftStarKit/ProjectCommandResolver.swift`
- Create: `Tests/SwiftStarKitTests/ProjectCommandResolverTests.swift`

**Interfaces:**
- Consumes: nothing (pure; `FileManager` only in the `in:` wrappers).
- Produces: `ProjectCommandResolver.kind(having: Set<String>) -> ProjectKind?`, `testCommand(in: URL) -> String?`, `lintCommand(in: URL) -> String?`, `isValidSelector(_ s: String) -> Bool`. Task 8 consumes `testCommand`/`lintCommand`/`isValidSelector`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/ProjectCommandResolverTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct ProjectCommandResolverTests {
    @Test func swiftMarkerResolvesSwift() {
        #expect(ProjectCommandResolver.kind(having: ["Package.swift"]) == .swift)
    }

    @Test func pythonMarkerResolvesPython() {
        #expect(ProjectCommandResolver.kind(having: ["pyproject.toml"]) == .python)
    }

    @Test func mixedRepoSwiftWins() {
        #expect(ProjectCommandResolver.kind(having: ["Package.swift", "pyproject.toml"]) == .swift)
    }

    @Test func noMarkerResolvesNil() {
        #expect(ProjectCommandResolver.kind(having: []) == nil)
    }

    @Test func selectorValidationRejectsShellMetacharacters() {
        #expect(ProjectCommandResolver.isValidSelector("tests/FooTests.swift"))
        #expect(ProjectCommandResolver.isValidSelector("FooTests::testBar"))
        #expect(!ProjectCommandResolver.isValidSelector("a; rm -rf /"))
        #expect(!ProjectCommandResolver.isValidSelector("$(touch /tmp/x)"))
        #expect(!ProjectCommandResolver.isValidSelector("`ls`"))
        #expect(!ProjectCommandResolver.isValidSelector("a b"))
        #expect(!ProjectCommandResolver.isValidSelector(""))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProjectCommandResolverTests`
Expected: FAIL — "cannot find 'ProjectCommandResolver' in scope"

- [ ] **Step 3: Implement**

`Sources/SwiftStarKit/ProjectCommandResolver.swift`:

```swift
import Foundation

/// Deterministic, host-owned derivation of the project's test and lint
/// commands from the workspace — the model never names a command (P24.3
/// evidence 1). Swift wins in mixed repos: a `Package.swift` is the app;
/// `pyproject.toml` may be tooling.
public enum ProjectCommandResolver {
    public enum ProjectKind: Equatable, Sendable {
        case swift
        case python
    }

    /// Pure core over the set of marker files present — fast-tier testable
    /// without filesystem I/O.
    public static func kind(having markers: Set<String>) -> ProjectKind? {
        if markers.contains("Package.swift") { return .swift }
        if markers.contains("pyproject.toml") { return .python }
        return nil
    }

    public static func kind(in workspace: URL) -> ProjectKind? {
        let fm = FileManager.default
        let present = ["Package.swift", "pyproject.toml"]
            .filter { fm.fileExists(atPath: workspace.appendingPathComponent($0).path) }
        return kind(having: Set(present))
    }

    public static func testCommand(in workspace: URL) -> String? {
        switch kind(in: workspace) {
        case .swift: return "swift test"
        case .python: return "uv run pytest"
        case nil: return nil
        }
    }

    /// `lint` targets Python (ruff) per the P24 row. A workspace with no ruff
    /// target resolves nil and the tool refuses deterministically.
    public static func lintCommand(in workspace: URL) -> String? {
        let fm = FileManager.default
        let hasRuffTarget = ["pyproject.toml", ".ruff.toml", "ruff.toml"]
            .contains { fm.fileExists(atPath: workspace.appendingPathComponent($0).path) }
        guard hasRuffTarget else { return nil }
        return "uv run ruff check --output-format=json"
    }

    /// The `test` selector is a typed filter, never a command: only the
    /// charset `[A-Za-z0-9_./-]` is admitted (safe to append to a shell
    /// command); anything else is refused, not executed.
    public static func isValidSelector(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy {
            $0.isASCII && "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-".contains($0)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ProjectCommandResolverTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/ProjectCommandResolver.swift Tests/SwiftStarKitTests/ProjectCommandResolverTests.swift
git commit -m "P24.3: ProjectCommandResolver — host-owned test/lint commands + selector validation"
```

---

### Task 3: `BashDigest`

**Files:**
- Create: `Sources/SwiftStarKit/BashDigest.swift`
- Create: `Tests/SwiftStarKitTests/BashDigestTests.swift`

**Interfaces:**
- Consumes: `CommandOutput`, `ToolDigest`, `ToolResultCondenser.condense(_:limit:)` (existing).
- Produces: `BashDigest.digest(_ out: CommandOutput, command: String, artifactPath: String) -> ToolDigest`. Task 8 consumes it for `kind: .bash`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/BashDigestTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct BashDigestTests {
    @Test func smallOutputShownWhole() {
        let out = CommandOutput(stdout: "hello\n", stderr: "", exit: 0, timedOut: false)
        let d = BashDigest.digest(out, command: "echo hello", artifactPath: "/runs/bash-x.log")
        #expect(d.summary.hasPrefix("bash: exit 0 (Ran: echo hello)"))
        #expect(d.summary.contains("hello"))
        #expect(d.outputDigest == ToolDigest.sha256("hello\n"))
    }

    @Test func largeOutputIsBoundedAndCarriesArtifactPointer() {
        let big = String(repeating: "y", count: 10_000)
        let out = CommandOutput(stdout: big, stderr: "", exit: 0, timedOut: false)
        let d = BashDigest.digest(out, command: "yes", artifactPath: "/runs/bash-z.log")
        #expect(d.summary.utf8.count <= 8000)
        #expect(d.summary.contains("full output: /runs/bash-z.log"))
        #expect(d.summary.contains("[truncated:"))
    }

    @Test func timedOutReported() {
        let out = CommandOutput(stdout: "", stderr: "", exit: 0, timedOut: true)
        let d = BashDigest.digest(out, command: "sleep 999", artifactPath: "/runs/bash-t.log")
        #expect(d.summary.hasPrefix("bash: timed out"))
    }

    @Test func deterministicGivenSameInput() {
        let out = CommandOutput(stdout: "same", stderr: "", exit: 3, timedOut: false)
        let a = BashDigest.digest(out, command: "cmd", artifactPath: "/runs/a.log")
        let b = BashDigest.digest(out, command: "cmd", artifactPath: "/runs/a.log")
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter BashDigestTests`
Expected: FAIL — "cannot find 'BashDigest' in scope"

- [ ] **Step 3: Implement**

`Sources/SwiftStarKit/BashDigest.swift`:

```swift
import Foundation

/// Digests arbitrary shell output. "Never raw" means never an unbounded dump:
/// output that fits `inlineLimit` is shown whole (it is small, so showing it
/// is honest); larger output becomes a condenser-style head/tail plus the
/// artifact pointer. Total over `CommandOutput`.
public enum BashDigest {
    /// Combined output (UTF-8 bytes) shown inline before the artifact pointer
    /// takes over.
    static let inlineLimit = 4000

    public static func digest(_ out: CommandOutput, command: String, artifactPath: String) -> ToolDigest {
        let status = out.timedOut ? "bash: timed out" : "bash: exit \(out.exit)"
        let combined = out.stdout + out.stderr
        let body: String
        if combined.utf8.count <= inlineLimit {
            body = combined
        } else {
            body = ToolResultCondenser.condense(combined, limit: 6000)
                + "\nfull output: \(artifactPath)"
        }
        let summary = "\(status) (Ran: \(command))\n\(body)"
        return ToolDigest(summary: summary, command: command,
                          artifactPath: artifactPath,
                          outputDigest: ToolDigest.sha256(out.stdout))
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter BashDigestTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/BashDigest.swift Tests/SwiftStarKitTests/BashDigestTests.swift
git commit -m "P24.3: BashDigest — bounded structured summary, never raw"
```

---

### Task 4: `TestDigest` — clustering core + XCTest text parser

**Files:**
- Create: `Sources/SwiftStarKit/TestDigest.swift` (this task: `Failure`, clustering, XCTest path, `digest` entry with text fallback)
- Create: `Tests/SwiftStarKitTests/TestDigestTests.swift` (this task: XCTest fixtures)

**Interfaces:**
- Consumes: `CommandOutput`, `ToolDigest`.
- Produces: `TestDigest.digest(_ out: CommandOutput, command: String, artifactPath: String) -> ToolDigest`, `TestDigest.Failure {testID, file, line, message}`, `TestDigest.maxClusters = 2`. Task 5 adds the pytest JSON parser into the same file behind a `parsePytestJSON` seam (defined here as `nil`), and Task 8 consumes `digest`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/TestDigestTests.swift` (XCTest part only):

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct TestDigestTests {
    /// Three `swift test` failures; two share (file, message) so the clusters
    /// are [2, 1].
    private static let xctestSample = """
    Test Suite 'All tests' started at 2026-08-30 12:00:00
    Test Case '-[SwiftStarKitTests.FooTests testBar]' started.
    /tmp/foo/FooTests.swift:42: error: -[SwiftStarKitTests.FooTests testBar] : XCTAssertEqual failed: ("1") is not equal to ("2")
    Test Case '-[SwiftStarKitTests.FooTests testBar]' failed (0.123 seconds).
    /tmp/foo/FooTests.swift:51: error: -[SwiftStarKitTests.FooTests testBaz] : XCTAssertEqual failed: ("3") is not equal to ("4")
    Test Case '-[SwiftStarKitTests.FooTests testBaz]' failed (0.050 seconds).
    /tmp/foo/FooTests.swift:63: error: -[SwiftStarKitTests.FooTests testBar] : XCTAssertEqual failed: ("1") is not equal to ("2")
    Test Case '-[SwiftStarKitTests.FooTests testBar]' failed (0.020 seconds).
    Test Suite 'All tests' finished at 2026-08-30 12:00:01
    """

    @Test func xctestClustersByFileAndMessage() {
        let out = CommandOutput(stdout: Self.xctestSample, stderr: "", exit: 1, timedOut: false)
        let d = TestDigest.digest(out, command: "swift test", artifactPath: "/runs/test-a.log")
        #expect(d.summary.contains("3 failures in 2 clusters"))
        #expect(d.summary.contains("[1] FooTests.swift — 2 failures"))
        #expect(d.summary.contains("[2] FooTests.swift — 1 failure"))
        #expect(d.summary.contains("XCTAssertEqual failed: (\"1\") is not equal to (\"2\")"))
        #expect(d.summary.contains("(FooTests.swift:42)"))
        #expect(d.summary.hasPrefix("test:"))
        #expect(d.summary.contains("Ran: swift test"))
        #expect(d.summary.contains("full output: /runs/test-a.log"))
    }

    @Test func xctestAllPassedWhenExitZeroAndNoFailures() {
        let out = CommandOutput(stdout: "Test Suite 'All tests' finished\n", stderr: "", exit: 0, timedOut: false)
        let d = TestDigest.digest(out, command: "swift test", artifactPath: "/runs/test-b.log")
        #expect(d.summary.contains("all passed"))
    }

    @Test func condenseIsANoopForPathologicalRun() {
        // 150 distinct failure lines → the summary must still fit the budget.
        var lines = ["Test Suite 'All tests' started"]
        for i in 0..<150 {
            lines.append("/tmp/f/F\(i).swift:\(i): error: -[T.F\(i) test\(i)] : boom \(i)")
        }
        let out = CommandOutput(stdout: lines.joined(separator: "\n"), stderr: "", exit: 1, timedOut: false)
        let d = TestDigest.digest(out, command: "swift test", artifactPath: "/runs/test-c.log")
        #expect(ToolResultCondenser.condense(d.summary) == d.summary)
        #expect(d.summary.utf8.count <= 8000)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TestDigestTests`
Expected: FAIL — "cannot find 'TestDigest' in scope"

- [ ] **Step 3: Implement**

`Sources/SwiftStarKit/TestDigest.swift`:

```swift
import Foundation

/// Clusters test failures by (file, message signature) so every failure in a
/// cluster maps to the same edit; emits ≤2 representatives plus counts.
/// Parses either pytest's `--json-report` JSON (Task 5) or `swift test`'s
/// XCTest text, sharing one clustering core. Total over `CommandOutput`.
public enum TestDigest {
    public struct Failure: Equatable, Sendable {
        public let testID: String
        public let file: String
        public let line: Int?
        public let message: String
    }

    static let maxClusters = 2

    public static func digest(_ out: CommandOutput, command: String, artifactPath: String) -> ToolDigest {
        let (failures, passed): ([Failure], Int?)
        if let parsed = parsePytestJSON(out.stdout) {
            (failures, passed) = parsed
        } else {
            (failures, passed) = (parseXCTestText(out.stdout), nil)
        }
        let summary = summarize(out: out, command: command, artifactPath: artifactPath,
                                failures: failures, passed: passed)
        return ToolDigest(summary: summary, command: command,
                          artifactPath: artifactPath,
                          outputDigest: ToolDigest.sha256(out.stdout))
    }

    // MARK: - XCTest text parser (Task 4)

    /// `swift test` emits `<file>:<line>: error: <testID> : <message>` lines.
    static func parseXCTestText(_ stdout: String) -> [Failure] {
        let pattern = #"^(.*\.swift):(\d+): error: (\[.*\]) : (.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var failures: [Failure] = []
        for line in stdout.split(separator: "\n") {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            guard let m = regex.firstMatch(in: s, range: range),
                  m.numberOfRanges == 5 else { continue }
            failures.append(Failure(
                testID: String(s[Range(m.range(at: 3), in: s)!]),
                file: String(s[Range(m.range(at: 1), in: s)!]),
                line: Int(s[Range(m.range(at: 2), in: s)!]),
                message: String(s[Range(m.range(at: 4), in: s)!])))
        }
        return failures
    }

    /// Task 5 replaces this with the pytest JSON parser. Returns nil here so
    /// the XCTest path is the fallback; never throws.
    static func parsePytestJSON(_ stdout: String) -> ([Failure], Int?)? { nil }

    // MARK: - clustering core (shared)

    typealias Cluster = (key: (file: String, message: String), failures: [Failure])

    static func makeClusters(_ failures: [Failure]) -> [Cluster] {
        var byKey: [(key: (file: String, message: String), failures: [Failure])] = []
        for f in failures {
            let key = (f.file, f.message)
            if let i = byKey.firstIndex(where: { $0.key == key }) {
                byKey[i].failures.append(f)
            } else {
                byKey.append((key: key, failures: [f]))
            }
        }
        return byKey.sorted { $0.failures.count > $1.failures.count }
    }

    static func summarize(out: CommandOutput, command: String, artifactPath: String,
                          failures: [Failure], passed: Int?) -> String {
        let exitLabel = out.timedOut ? "timed out" : "exit \(out.exit)"
        let clusters = makeClusters(failures)
        var lines: [String] = []
        if let passed, !failures.isEmpty {
            lines.append("test: \(passed) passed, \(failures.count) failed (\(exitLabel))")
        } else if failures.isEmpty && !out.timedOut && out.exit == 0 {
            lines.append("test: all passed (\(exitLabel))")
        } else if failures.isEmpty {
            lines.append("test: no failures parsed (\(exitLabel))")
        } else {
            lines.append("test: \(failures.count) failures in \(clusters.count) cluster\(clusters.count == 1 ? "" : "s") (\(exitLabel))")
        }
        lines.append("Ran: \(command)")
        for (i, cluster) in clusters.prefix(maxClusters).enumerated() {
            let rep = cluster.failures[0]
            let count = cluster.failures.count
            lines.append("[\(i + 1)] \(cluster.key.file) — \(count) failure\(count == 1 ? "" : "s")")
            lines.append("    \(rep.testID)")
            if let line = rep.line {
                lines.append("    \(rep.message)   (\(rep.file):\(line))")
            } else {
                lines.append("    \(rep.message)   (\(rep.file))")
            }
        }
        if clusters.count > maxClusters {
            lines.append("and \(clusters.count - maxClusters) more clusters (see full output)")
        }
        lines.append("full output: \(artifactPath)")
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TestDigestTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/TestDigest.swift Tests/SwiftStarKitTests/TestDigestTests.swift
git commit -m "P24.3: TestDigest — clustering core + XCTest text parser"
```

---

### Task 5: `TestDigest` — pytest JSON parser

**Files:**
- Modify: `Sources/SwiftStarKit/TestDigest.swift` (replace the `parsePytestJSON` stub)
- Modify: `Tests/SwiftStarKitTests/TestDigestTests.swift` (add pytest fixtures)

**Interfaces:**
- Consumes: the Task 4 shapes.
- Produces: `parsePytestJSON(_ stdout: String) -> ([Failure], Int?)?` — returns `(failures, passedCount)` for `pytest --json-report` stdout, `nil` when it does not parse (falling back to XCTest text). Non-JSON stdout must never crash (total).

- [ ] **Step 1: Write the failing tests** (append to `TestDigestTests.swift`)

```swift
    @Test func pytestJSONClustersAndCarriesPassedCount() {
        let json = """
        {"summary":{"passed":10,"failed":3,"error":0,"skipped":1},
         "tests":[
           {"nodeid":"tests/test_api.py::test_create_user","outcome":"failed","call":{"longrepr":"def test_create_user():\\n    r = client.post(\\nE   AssertionError: expected 201, got 500\\n"}},
           {"nodeid":"tests/test_api.py::test_delete_user","outcome":"failed","call":{"longrepr":"def test_delete_user():\\nE   AssertionError: expected 201, got 500\\n"}},
           {"nodeid":"tests/test_db.py::test_migration","outcome":"failed","call":{"longrepr":"def test_migration():\\nE   OperationalError: no such table\\n"}},
           {"nodeid":"tests/test_api.py::test_ok","outcome":"passed","call":{"longrepr":""}}
         ]}
        """
        let out = CommandOutput(stdout: json, stderr: "", exit: 1, timedOut: false)
        let d = TestDigest.digest(out, command: "uv run pytest", artifactPath: "/runs/test-d.log")
        #expect(d.summary.contains("test: 10 passed, 3 failed (exit 1)"))
        #expect(d.summary.contains("[1] tests/test_api.py — 2 failures"))
        #expect(d.summary.contains("[2] tests/test_db.py — 1 failure"))
        #expect(d.summary.contains("AssertionError: expected 201, got 500"))
        #expect(d.summary.contains("Ran: uv run pytest"))
    }

    @Test func nonJSONStdoutFallsBackToText() {
        // A crashed runner wrote a traceback, not JSON — the XCTest text path
        // finds nothing, but the digester is total and reports honestly.
        let traceback = "Traceback (most recent call last):\n  File \"/usr/lib/runner.py\", line 9\nRuntimeError: boom\n"
        let out = CommandOutput(stdout: traceback, stderr: "", exit: 1, timedOut: false)
        let d = TestDigest.digest(out, command: "uv run pytest", artifactPath: "/runs/test-e.log")
        #expect(d.summary.contains("no failures parsed"))
        #expect(d.summary.contains("full output: /runs/test-e.log"))
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TestDigestTests`
Expected: FAIL — `pytestJSONClustersAndCarriesPassedCount` fails (stub returns nil → text path → "no failures parsed")

- [ ] **Step 3: Implement** — replace the stub in `Sources/SwiftStarKit/TestDigest.swift`:

```swift
    /// Parses `pytest --json-report` stdout: the `summary.passed` count and,
    /// for each failed test, a `Failure` keyed by (file-from-nodeid, the last
    /// `E   ` assertion line of `call.longrepr`). Returns nil when the stdout
    /// is not that shape (fall back to the XCTest text path).
    static func parsePytestJSON(_ stdout: String) -> ([Failure], Int?)? {
        guard let data = stdout.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tests = obj["tests"] as? [[String: Any]] else { return nil }
        var failures: [Failure] = []
        var passed: Int? = nil
        if let summary = obj["summary"] as? [String: Any],
           let p = summary["passed"] as? Int { passed = p }
        for t in tests {
            guard t["outcome"] as? String == "failed",
                  let nodeid = t["nodeid"] as? String else { continue }
            let file = nodeid.components(separatedBy: "::")[0]
            let message: String
            if let call = t["call"] as? [String: Any],
               let longrepr = call["longrepr"] as? String {
                let assertionLines = longrepr.split(separator: "\n")
                    .filter { $0.hasPrefix("E   ") }
                message = assertionLines.last.map {
                    String($0.dropFirst(4))
                } ?? longrepr.split(separator: "\n").first.map(String.init) ?? "unknown failure"
            } else {
                message = "unknown failure"
            }
            failures.append(Failure(testID: nodeid, file: file, line: nil, message: message))
        }
        return (failures, passed)
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TestDigestTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/TestDigest.swift Tests/SwiftStarKitTests/TestDigestTests.swift
git commit -m "P24.3: TestDigest — pytest --json-report parser with text fallback"
```

---

### Task 6: `RuffDigest`

**Files:**
- Create: `Sources/SwiftStarKit/RuffDigest.swift`
- Create: `Tests/SwiftStarKitTests/RuffDigestTests.swift`

**Interfaces:**
- Consumes: `CommandOutput`, `ToolDigest`.
- Produces: `RuffDigest.digest(_ out: CommandOutput, command: String, artifactPath: String) -> ToolDigest`. Task 8 consumes it for `kind: .lint`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/RuffDigestTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct RuffDigestTests {
    private static let sample = """
    [{"code":"F401","message":"`os` imported but unused","filename":"src/app.py","location":{"row":12,"column":1}},
     {"code":"F401","message":"`sys` imported but unused","filename":"src/app.py","location":{"row":13,"column":1}},
     {"code":"E501","message":"line too long (92 > 88)","filename":"src/util.py","location":{"row":88,"column":1}}]
    """

    @Test func groupsByRuleAndFile() {
        let out = CommandOutput(stdout: Self.sample, stderr: "", exit: 1, timedOut: false)
        let d = RuffDigest.digest(out, command: "uv run ruff check --output-format=json", artifactPath: "/runs/lint-a.log")
        #expect(d.summary.contains("ruff: 3 diagnostics, 2 files (exit 1)"))
        #expect(d.summary.contains("[1] F401 — 2 in 1 file"))
        #expect(d.summary.contains("[2] E501 — 1 in 1 file"))
        #expect(d.summary.contains("src/app.py:12:1 `os` imported but unused"))
        #expect(d.summary.contains("Ran: uv run ruff check --output-format=json"))
    }

    @Test func zeroDiagnosticsIsExplicit() {
        let out = CommandOutput(stdout: "[]", stderr: "", exit: 0, timedOut: false)
        let d = RuffDigest.digest(out, command: "uv run ruff check --output-format=json", artifactPath: "/runs/lint-b.log")
        #expect(d.summary.contains("0 diagnostics"))
        #expect(d.summary.contains("all clean"))
    }

    @Test func unparseableFallsBackToBoundedSummary() {
        let out = CommandOutput(stdout: "error: unrecognized option", stderr: "", exit: 2, timedOut: false)
        let d = RuffDigest.digest(out, command: "uv run ruff check --output-format=json", artifactPath: "/runs/lint-c.log")
        #expect(d.summary.contains("ruff: could not parse"))
        #expect(d.summary.contains("full output: /runs/lint-c.log"))
    }

    @Test func condenseIsANoopForManyDiagnostics() {
        var items: [String] = []
        for i in 0..<150 {
            items.append("{\"code\":\"E501\",\"message\":\"line too long\",\"filename\":\"src/f\(i).py\",\"location\":{\"row\":1,\"column\":1}}")
        }
        let out = CommandOutput(stdout: "[" + items.joined(separator: ",") + "]", stderr: "", exit: 1, timedOut: false)
        let d = RuffDigest.digest(out, command: "uv run ruff check --output-format=json", artifactPath: "/runs/lint-d.log")
        #expect(ToolResultCondenser.condense(d.summary) == d.summary)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter RuffDigestTests`
Expected: FAIL — "cannot find 'RuffDigest' in scope"

- [ ] **Step 3: Implement**

`Sources/SwiftStarKit/RuffDigest.swift`:

```swift
import Foundation

/// Groups ruff JSON diagnostics by (rule code, file) so each group maps to one
/// class of edit; emits ≤2 groups plus counts. Total over `CommandOutput`.
public enum RuffDigest {
    public struct Diagnostic: Equatable, Sendable {
        public let code: String
        public let file: String
        public let line: Int
        public let column: Int
        public let message: String
    }

    static let maxGroups = 2

    public static func digest(_ out: CommandOutput, command: String, artifactPath: String) -> ToolDigest {
        let diagnostics = parseRuffJSON(out.stdout)
        let summary = summarize(out: out, command: command, artifactPath: artifactPath,
                                diagnostics: diagnostics)
        return ToolDigest(summary: summary, command: command,
                          artifactPath: artifactPath,
                          outputDigest: ToolDigest.sha256(out.stdout))
    }

    static func parseRuffJSON(_ stdout: String) -> [Diagnostic] {
        guard let data = stdout.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { item in
            guard let code = item["code"] as? String,
                  let message = item["message"] as? String,
                  let file = item["filename"] as? String,
                  let loc = item["location"] as? [String: Any],
                  let row = loc["row"] as? Int,
                  let column = loc["column"] as? Int else { return nil }
            return Diagnostic(code: code, file: file, line: row, column: column, message: message)
        }
    }

    static func summarize(out: CommandOutput, command: String, artifactPath: String,
                          diagnostics: [Diagnostic]) -> String {
        let exitLabel = out.timedOut ? "timed out" : "exit \(out.exit)"
        var lines: [String] = []
        if diagnostics.isEmpty && !out.timedOut && out.exit == 0 {
            lines.append("ruff: 0 diagnostics, all clean (\(exitLabel))")
        } else if diagnostics.isEmpty {
            lines.append("ruff: could not parse (\(exitLabel))")
        } else {
            let files = Set(diagnostics.map(\.file)).count
            lines.append("ruff: \(diagnostics.count) diagnostics, \(files) file\(files == 1 ? "" : "s") (\(exitLabel))")
        }
        lines.append("Ran: \(command)")
        let groups = group(diagnostics)
        for (i, group) in groups.prefix(maxGroups).enumerated() {
            let files = Set(group.map(\.file)).count
            lines.append("[\(i + 1)] \(group[0].code) — \(group.count) in \(files) file\(files == 1 ? "" : "s")")
            let rep = group[0]
            lines.append("    \(rep.file):\(rep.line):\(rep.column) \(rep.message)")
        }
        if groups.count > maxGroups {
            lines.append("and \(groups.count - maxGroups) more rule groups (see full output)")
        }
        lines.append("full output: \(artifactPath)")
        return lines.joined(separator: "\n")
    }

    static func group(_ diagnostics: [Diagnostic]) -> [[Diagnostic]] {
        var byKey: [(key: (String, String), items: [Diagnostic])] = []
        for d in diagnostics {
            let key = (d.code, d.file)
            if let i = byKey.firstIndex(where: { $0.key == key }) {
                byKey[i].items.append(d)
            } else {
                byKey.append((key: key, items: [d]))
            }
        }
        return byKey.sorted { $0.items.count > $1.items.count }.map(\.items)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter RuffDigestTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/RuffDigest.swift Tests/SwiftStarKitTests/RuffDigestTests.swift
git commit -m "P24.3: RuffDigest — rule/file grouping of ruff JSON diagnostics"
```

---

### Task 7: `ToolCallbackResponder.deterministicTools`

**Files:**
- Modify: `Sources/SwiftStarKit/ToolCallbackResponder.swift` (add the set beside `fileTools`/`shellTools` at ~line 114, and a consent branch before the shell check)
- Modify: `Tests/SwiftStarKitTests/ToolCallbackResponderTests.swift`

**Interfaces:**
- Consumes: existing `consent(idx:name:params:workspace:shellAllowed:writableFiles:)`.
- Produces: `test`/`lint` admitted with `.proceed` and `resolvedPath: nil`, regardless of `shellAllowed`; unknown tools still refused. Task 8's executor relies on this.

- [ ] **Step 1: Write the failing tests** (append to `ToolCallbackResponderTests.swift`)

```swift
    @Test func testAdmittedWithoutShellToggle() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let verdict = ToolCallbackResponder.consent(
            idx: 1, name: "test", params: [ToolParam(name: "selector", value: "FooTests")],
            workspace: ws, shellAllowed: false)
        guard case .proceed(let req) = verdict else {
            Issue.record("expected proceed, got \(verdict)"); return
        }
        #expect(req.resolvedPath == nil)
        #expect(req.params.first?.value == "FooTests")
    }

    @Test func lintAdmittedWithoutShellToggle() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let verdict = ToolCallbackResponder.consent(
            idx: 2, name: "lint", params: [], workspace: ws, shellAllowed: false)
        guard case .proceed = verdict else {
            Issue.record("expected proceed, got \(verdict)"); return
        }
    }

    @Test func unknownToolStillRefusedWhenShellOff() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let verdict = ToolCallbackResponder.consent(
            idx: 3, name: "frobnicate", params: [], workspace: ws, shellAllowed: false)
        guard case .refuse(let reason) = verdict else {
            Issue.record("expected refuse, got \(verdict)"); return
        }
        #expect(reason.contains("unknown or unsupported"))
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ToolCallbackResponderTests`
Expected: FAIL — `test`/`lint` fall through to "unknown or unsupported tool"

- [ ] **Step 3: Implement**

In `Sources/SwiftStarKit/ToolCallbackResponder.swift`, add beside the other sets (~line 117):

```swift
    /// P24.3: the deterministic host tools — fixed, host-assembled commands
    /// (the model names no command string), so they are admitted without the
    /// shell toggle; the model cannot inject arbitrary shell through them.
    /// The tool/bash distinction: a tool runs a fixed command; `bash` runs an
    /// arbitrary one and keeps its `shellAllowed` gate.
    private static let deterministicTools: Set<String> = ["test", "lint"]
```

And in `consent(...)`, after the `fileTools` block and before the `shellTools` block:

```swift
        if Self.deterministicTools.contains(name) {
            return .proceed(ToolExecutionRequest(
                name: name, params: params, workspace: wsStd, resolvedPath: nil))
        }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ToolCallbackResponderTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/ToolCallbackResponder.swift Tests/SwiftStarKitTests/ToolCallbackResponderTests.swift
git commit -m "P24.3: consent admits deterministic host tools test/lint without the shell toggle"
```

---

### Task 8: `CommandToolRunner`

**Files:**
- Create: `Sources/SwiftStarAppKit/CommandToolRunner.swift`
- Create: `Tests/SwiftStarIntegrationTests/CommandToolRunnerTests.swift`

**Interfaces:**
- Consumes: `SubprocessRunner` (sync + async), `CommandOutput`, `ToolDigest`, `TestDigest`, `RuffDigest`, `BashDigest`, `ProjectCommandResolver`.
- Produces: `CommandToolRunner.runsDir(for: URL) -> URL`, `CommandToolRunner.assemble(out:command:kind:runsDir:) -> ToolExecutionResult`, `CommandToolRunner.runTest(selector:workspace:)`, `CommandToolRunner.runLint(workspace:)`, `CommandToolRunner.runBash(command:workspace:)` — each in sync and async forms. Task 9 consumes `assemble` and the run methods.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarIntegrationTests/CommandToolRunnerTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarAppKit
@testable import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct CommandToolRunnerTests {
    private func tmpWorkspace() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("p24-3-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func assembleWritesArtifactAndDigests() throws {
        let ws = try tmpWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let runs = CommandToolRunner.runsDir(for: ws)
        let out = CommandOutput(stdout: "ok\n", stderr: "", exit: 0, timedOut: false)
        let result = CommandToolRunner.assemble(out: out, command: "echo ok", kind: .bash, runsDir: runs)
        #expect(result.ok)
        #expect(result.validationRan)
        #expect(result.outputDigest == ToolDigest.sha256("ok\n"))
        let written = try FileManager.default.contentsOfDirectory(atPath: runs.path)
        #expect(written.count == 1)
        #expect(written[0].hasPrefix("bash-"))
        let content = try String(contentsOfFile: runs.appendingPathComponent(written[0]).path)
        #expect(content == "ok\n")
    }

    @Test func testKindOkIsRanNotCommandSuccess() throws {
        let ws = try tmpWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let runs = CommandToolRunner.runsDir(for: ws)
        // exit 1 = failing tests = a successful RUN for test/lint (ok true);
        // bash keeps exit==0 semantics (sibling: the same input, kind .bash).
        let out = CommandOutput(stdout: "", stderr: "", exit: 1, timedOut: false)
        let asTest = CommandToolRunner.assemble(out: out, command: "swift test", kind: .test, runsDir: runs)
        #expect(asTest.ok)
        #expect(asTest.exitStatus == 1)
        let asBash = CommandToolRunner.assemble(out: out, command: "false", kind: .bash, runsDir: runs)
        #expect(!asBash.ok)
    }

    @Test func runTestRefusesWhenNoProject() throws {
        let ws = try tmpWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let result = CommandToolRunner.runTest(selector: nil, workspace: ws)
        #expect(!result.ok)
        #expect(result.text.contains("no `Package.swift` or `pyproject.toml`"))
    }

    @Test func runTestRefusesShellMetacharacterSelector() throws {
        let ws = try tmpWorkspace()
        try "dummy".write(toFile: ws.appendingPathComponent("Package.swift").path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ws) }
        let result = CommandToolRunner.runTest(selector: "a; rm -rf /", workspace: ws)
        #expect(!result.ok)
        #expect(result.text.contains("selector may only contain"))
    }

    @Test func runBashDigestsRealSubprocessOutput() throws {
        let ws = try tmpWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let result = CommandToolRunner.runBash(command: "echo dig-me", workspace: ws)
        #expect(result.ok)
        #expect(result.text.contains("dig-me"))
        #expect(result.text.contains("(Ran: echo dig-me)"))
        #expect(result.validationRan)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter CommandToolRunnerTests`
Expected: FAIL — "cannot find 'CommandToolRunner' in scope"

- [ ] **Step 3: Implement**

`Sources/SwiftStarAppKit/CommandToolRunner.swift`:

```swift
import Foundation
import SwiftStarKit

/// The run/archive/assemble glue for the run+digest family. Runs a fixed,
/// host-derived command, writes the full output to `.swiftstar/runs/`, calls
/// the pure digester, assembles the `ToolExecutionResult`. `assemble` is the
/// single place that logic lives — shared by the sync/async run paths and by
/// `HostToolExecutor`'s re-scoped `bash` (Task 9).
public enum CommandToolRunner {
    public enum ToolKind: Sendable {
        case test, lint, bash
    }

    public static func runsDir(for workspace: URL) -> URL {
        workspace.appendingPathComponent(".swiftstar/runs")
    }

    /// Writes the artifact, prunes to the last 20 per tool, digests, assembles.
    /// Total: an artifact write failure still yields the digest (without the
    /// pointer) rather than an error.
    public static func assemble(out: CommandOutput, command: String, kind: ToolKind,
                                runsDir: URL) -> ToolExecutionResult {
        let content = out.stdout + out.stderr
        let contentSha = ToolDigest.sha256(content)
        let path = runsDir.appendingPathComponent("\(kindName(kind))-\(contentSha).log")
        var artifactPath = path.path
        do {
            try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
            try content.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            artifactPath = ""
        }
        prune(runsDir: runsDir, kind: kind, keep: 20)
        let digest = digest(out, command: command, artifactPath: artifactPath, kind: kind)
        let ok: Bool
        switch kind {
        case .bash:
            ok = out.exit == 0 && !out.timedOut
        case .test, .lint:
            // "ran" — failures live in the digest + exitStatus; ok:false is
            // reserved for could-not-run (timeout, or exit 127 = not found).
            ok = !out.timedOut && out.exit != 127
        }
        return ToolExecutionResult(ok: ok, text: digest.summary,
                                   exitStatus: Int(out.exit),
                                   outputDigest: digest.outputDigest,
                                   validationRan: true)
    }

    public static func runTest(selector: String?, workspace: URL) -> ToolExecutionResult {
        runTest(selector: selector, workspace: workspace, run: { try SubprocessRunner.run($0, in: workspace) })
    }

    public static func runTest(selector: String?, workspace: URL) async -> ToolExecutionResult {
        await runTest(selector: selector, workspace: workspace, run: { try await SubprocessRunner.run($0, in: workspace) })
    }

    public static func runLint(workspace: URL) -> ToolExecutionResult {
        runLint(workspace: workspace, run: { try SubprocessRunner.run($0, in: workspace) })
    }

    public static func runLint(workspace: URL) async -> ToolExecutionResult {
        await runLint(workspace: workspace, run: { try await SubprocessRunner.run($0, in: workspace) })
    }

    /// `bash` runs the model's (already policy-admitted) command; only the
    /// OUTPUT is digested. The model never names a command for test/lint, but
    /// bash is the arbitrary shell tool and keeps its command param.
    public static func runBash(command: String, workspace: URL) -> ToolExecutionResult {
        runBash(command: command, workspace: workspace, run: { try SubprocessRunner.run($0, in: workspace) })
    }

    public static func runBash(command: String, workspace: URL) async -> ToolExecutionResult {
        await runBash(command: command, workspace: workspace, run: { try await SubprocessRunner.run($0, in: workspace) })
    }

    // MARK: - shared plumbing

    private static func runTest(selector: String?, workspace: URL,
                                run: (String) throws -> SubprocessRunner.Result) -> ToolExecutionResult {
        guard let base = ProjectCommandResolver.testCommand(in: workspace) else {
            return refusal("no `Package.swift` or `pyproject.toml` in workspace")
        }
        if let selector, !ProjectCommandResolver.isValidSelector(selector) {
            return refusal("refused: selector may only contain [A-Za-z0-9_./-]")
        }
        let command = selector.map { "\(base) \($0)" } ?? base
        return runAndAssemble(command: command, kind: .test, workspace: workspace, run: run)
    }

    private static func runTest(selector: String?, workspace: URL,
                                run: (String) async throws -> SubprocessRunner.Result) async -> ToolExecutionResult {
        guard let base = ProjectCommandResolver.testCommand(in: workspace) else {
            return refusal("no `Package.swift` or `pyproject.toml` in workspace")
        }
        if let selector, !ProjectCommandResolver.isValidSelector(selector) {
            return refusal("refused: selector may only contain [A-Za-z0-9_./-]")
        }
        let command = selector.map { "\(base) \($0)" } ?? base
        return await runAndAssemble(command: command, kind: .test, workspace: workspace, run: run)
    }

    private static func runLint(workspace: URL,
                                run: (String) throws -> SubprocessRunner.Result) -> ToolExecutionResult {
        guard let command = ProjectCommandResolver.lintCommand(in: workspace) else {
            return refusal("no ruff target (`pyproject.toml`, `.ruff.toml`, `ruff.toml`) in workspace")
        }
        return runAndAssemble(command: command, kind: .lint, workspace: workspace, run: run)
    }

    private static func runLint(workspace: URL,
                                run: (String) async throws -> SubprocessRunner.Result) async -> ToolExecutionResult {
        guard let command = ProjectCommandResolver.lintCommand(in: workspace) else {
            return refusal("no ruff target (`pyproject.toml`, `.ruff.toml`, `ruff.toml`) in workspace")
        }
        return await runAndAssemble(command: command, kind: .lint, workspace: workspace, run: run)
    }

    private static func runBash(command: String, workspace: URL,
                                run: (String) throws -> SubprocessRunner.Result) -> ToolExecutionResult {
        runAndAssemble(command: command, kind: .bash, workspace: workspace, run: run)
    }

    private static func runBash(command: String, workspace: URL,
                                run: (String) async throws -> SubprocessRunner.Result) async -> ToolExecutionResult {
        await runAndAssemble(command: command, kind: .bash, workspace: workspace, run: run)
    }

    private static func runAndAssemble(command: String, kind: ToolKind, workspace: URL,
                                       run: (String) throws -> SubprocessRunner.Result) -> ToolExecutionResult {
        do {
            let r = try run(command)
            let out = CommandOutput(stdout: r.stdout, stderr: r.stderr, exit: r.exit, timedOut: r.timedOut)
            return assemble(out: out, command: command, kind: kind, runsDir: runsDir(for: workspace))
        } catch {
            return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
        }
    }

    private static func runAndAssemble(command: String, kind: ToolKind, workspace: URL,
                                       run: (String) async throws -> SubprocessRunner.Result) async -> ToolExecutionResult {
        do {
            let r = try await run(command)
            let out = CommandOutput(stdout: r.stdout, stderr: r.stderr, exit: r.exit, timedOut: r.timedOut)
            return assemble(out: out, command: command, kind: kind, runsDir: runsDir(for: workspace))
        } catch {
            return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
        }
    }

    private static func digest(_ out: CommandOutput, command: String, artifactPath: String,
                               kind: ToolKind) -> ToolDigest {
        switch kind {
        case .test: return TestDigest.digest(out, command: command, artifactPath: artifactPath)
        case .lint: return RuffDigest.digest(out, command: command, artifactPath: artifactPath)
        case .bash: return BashDigest.digest(out, command: command, artifactPath: artifactPath)
        }
    }

    private static func kindName(_ kind: ToolKind) -> String {
        switch kind {
        case .test: return "test"
        case .lint: return "lint"
        case .bash: return "bash"
        }
    }

    /// Keep the newest `keep` artifacts per tool (content-addressed names make
    /// the newest-K filter deterministic: sort by modification date).
    private static func prune(runsDir: URL, kind: ToolKind, keep: Int) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: runsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let prefix = kindName(kind) + "-"
        let sorted = entries
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { ($0.contentModificationDate ?? .distantPast) > ($1.contentModificationDate ?? .distantPast) }
        if sorted.count > keep {
            for stale in sorted.dropFirst(keep) { try? FileManager.default.removeItem(at: stale) }
        }
    }

    private static func refusal(_ reason: String) -> ToolExecutionResult {
        ToolExecutionResult(ok: false, text: "error: \(reason)")
    }
}

private extension URL {
    var contentModificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter CommandToolRunnerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarAppKit/CommandToolRunner.swift Tests/SwiftStarIntegrationTests/CommandToolRunnerTests.swift
git commit -m "P24.3: CommandToolRunner — run/archive/assemble scaffold"
```

---

### Task 9: `HostToolExecutor` wiring + digested `bash`

**Files:**
- Modify: `Sources/SwiftStarAppKit/HostToolExecutor.swift`
- Modify: `Tests/SwiftStarIntegrationTests/HostToolExecutorBashTests.swift`
- Modify: `pyproject.toml` (ruff dev dependency + minimal `[tool.ruff]` — gives `lint` a real consumer)

**Interfaces:**
- Consumes: `CommandToolRunner` (Task 8).
- Produces: `test`/`lint` tool cases in `execute`; `bash` results now `BashDigest`-shaped (text starts with `bash: `, carries `(Ran: …)`, and an artifact pointer for large output).

- [ ] **Step 1: Write the failing tests** (append to `HostToolExecutorBashTests.swift`)

```swift
    @Test func bashResultIsDigestedNotRaw() {
        let executor = HostToolExecutor(policy: .app)
        let result = executor.execute(request([param("command", "echo small-output")]))
        #expect(result.ok)
        #expect(result.text.hasPrefix("bash: exit 0 (Ran: echo small-output)"))
        #expect(result.text.contains("small-output"))
    }

    @Test func testToolRunsSwiftTestAgainstFixtureProject() throws {
        // A tiny real Swift package: resolves to `swift test`, runs it, and
        // digests the outcome. Exercised once here; the paired-bill live run
        // (Task 12) is where the decision-completeness claim is measured.
        let pkg = FileManager.default.temporaryDirectory
            .appendingPathComponent("p24-3-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pkg) }
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "Fixture", targets: [.target(name: "Fixture"), .testTarget(name: "FixtureTests", dependencies: ["Fixture"])])
        """.write(toFile: pkg.appendingPathComponent("Package.swift").path, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: pkg.appendingPathComponent("Sources/Fixture"), withIntermediateDirectories: true)
        try "public func answer() -> Int { 42 }\n".write(toFile: pkg.appendingPathComponent("Sources/Fixture/Fixture.swift").path, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: pkg.appendingPathComponent("Tests/FixtureTests"), withIntermediateDirectories: true)
        try """
        import Testing
        @testable import Fixture
        @Test func answers() { #expect(answer() == 42) }
        """.write(toFile: pkg.appendingPathComponent("Tests/FixtureTests/FixtureTests.swift").path, atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)
        let result = executor.execute(ToolExecutionRequest(
            name: "test", params: [], workspace: pkg, resolvedPath: nil))
        #expect(result.ok)
        #expect(result.text.contains("Ran: swift test"))
        #expect(result.text.contains("all passed") || result.text.contains("failures"))
        #expect(result.validationRan)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter HostToolExecutorBashTests`
Expected: FAIL — `bash` still returns raw text (no `Ran: ` prefix); `test` is "unknown tool"

- [ ] **Step 3: Implement**

In `Sources/SwiftStarAppKit/HostToolExecutor.swift`:

Add the two cases to `nonBashResult`'s switch (beside `"read", "more"`):

```swift
        case "test":
            let selector = request.params.first(where: { $0.name == "selector" })?.value
            return CommandToolRunner.runTest(selector: selector, workspace: request.workspace)
        case "lint":
            return CommandToolRunner.runLint(workspace: request.workspace)
```

Re-scope `bashResult` (the two `execute` overloads pass `r` — thread `request.workspace` and the command through):

```swift
    private func bashResult(_ r: SubprocessRunner.Result, command: String,
                            workspace: URL) -> ToolExecutionResult {
        let out = CommandOutput(stdout: r.stdout, stderr: r.stderr,
                                exit: r.exit, timedOut: r.timedOut)
        return CommandToolRunner.assemble(
            out: out, command: command, kind: .bash,
            runsDir: CommandToolRunner.runsDir(for: workspace))
    }
```

and update both `execute` overloads' bash tail from `return bashResult(r)` to `return bashResult(r, command: command, workspace: request.workspace)` (the `command` variable already exists — it is `bashCommand(request)`).

Add ruff to `pyproject.toml` so `lint` has a real consumer:

```toml
[dependency-groups]
dev = ["ruff>=0.9,<1"]

[tool.ruff]
target-version = "py313"
line-length = 100
extend-exclude = ["docs/_build"]
```

- [ ] **Step 4: Run to verify it passes**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter HostToolExecutorBashTests`
Expected: PASS (bash digest pin, swift-test fixture digest)

- [ ] **Step 5: Verify lint resolves and runs against the repo**

Run: `uv run ruff check --output-format=json .`
Expected: valid JSON diagnostics array (or `[]`) — the host command the tool will run resolves.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarAppKit/HostToolExecutor.swift Tests/SwiftStarIntegrationTests/HostToolExecutorBashTests.swift pyproject.toml uv.lock
git commit -m "P24.3: wire test/lint into HostToolExecutor; bash results are BashDigests; ruff dev dep"
```

---

### Task 10: Engine patch — `test`/`lint` schemas, fork-ledger row #15, C unit test

**Files:**
- Modify: `external/ds4/ds4_agent.c`
- Modify: `external/ds4/docs/fork-ledger.md`
- Modify: `external/ds4/tests/ds4_agent_test.c` (register the new unit test)

**Interfaces:**
- Consumes: the existing `agent_schemas_for` + `--host-tools` gating (divergence #12).
- Produces: under `--host-tools`, the advertised schema includes `test` and `lint`; the `bash` description says output is host-digested. The DSML/DeepSeek block is untouched (the `dispatch` precedent).

- [ ] **Step 1: Add the schema constants** — after `agent_dispatch_tool_schema` in `external/ds4/ds4_agent.c`:

```c
/* P24.3 (fork divergence #15): the `test` and `lint` host-tool schemas —
 * advertised only under --host-tools, exactly like `dispatch` (divergence
 * #12): the engine cannot execute them without a host. The DSML/DeepSeek
 * block is intentionally untouched, the same way dispatch is handled. */
static const char agent_test_tool_schema[] =
    "{\"type\":\"function\",\"function\":{\"name\":\"test\",\"description\":\"Run the project's test command (host-run; output is digested).\",\"parameters\":{\"type\":\"object\",\"properties\":{\"selector\":{\"type\":\"string\"}},\"required\":[]}}}\n";
static const char agent_lint_tool_schema[] =
    "{\"type\":\"function\",\"function\":{\"name\":\"lint\",\"description\":\"Run ruff on the project (host-run; output is digested).\",\"parameters\":{\"type\":\"object\",\"properties\":{},\"required\":[]}}}\n";
```

- [ ] **Step 2: Append them under `--host-tools`** — in `agent_schemas_for`, extend the existing `if (host_tools)` block that appends `agent_dispatch_tool_schema`:

```c
    /* P20 (fork divergence #12): advertise `dispatch` only under --host-tools. */
    /* P24.3 (fork divergence #15): `test`/`lint` ride the same gate. */
    if (host_tools) {
        static const char *const extra[] = {
            agent_dispatch_tool_schema,
            agent_test_tool_schema,
            agent_lint_tool_schema,
        };
        for (size_t n = 0; n < sizeof(extra) / sizeof(extra[0]); n++) {
            size_t xl = strlen(extra[n]);
            if (o + xl + 1 < outlen) {
                memcpy(out + o, extra[n], xl + 1);
                o += xl;
            }
        }
    }
```

- [ ] **Step 3: Tweak the `bash` description** — in `agent_glm_tool_schemas`:

Change `"name":"bash","description":"Run a shell command."` to `"name":"bash","description":"Run a shell command; output is host-digested."`

- [ ] **Step 4: Add the C unit test** — in `external/ds4/ds4_agent.c`, beside `test_agent_schemas_gate_dispatch_when_host_tools_off`:

```c
static void test_agent_schemas_add_test_lint_when_host_tools_on(void) {
    char buf[16384];
    agent_schemas_for(buf, sizeof(buf), true, false);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"test\"") == NULL);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"lint\"") == NULL);
    agent_schemas_for(buf, sizeof(buf), true, true);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"test\"") != NULL);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"lint\"") != NULL);
    AGENT_TEST_ASSERT(strstr(buf, "\"selector\"") != NULL);
    /* the bash description now advertises host digestion */
    AGENT_TEST_ASSERT(strstr(buf, "output is host-digested") != NULL);
}
```

Register it in `ds4_agent_unit_tests_run(void)` next to the dispatch-gate test, and add the declaration if the file declares test functions at the top (follow the existing pattern — the file declares `static void test_agent_schemas_gate_dispatch_when_host_tools_off(void);` above the runner).

- [ ] **Step 5: Run the engine tests**

Run: `cd external/ds4 && make test-agent` (or the repo's documented engine test invocation — check `external/ds4/Makefile`/`REBASING.md` for the exact target)
Expected: `ds4-agent tests: ok`

- [ ] **Step 6: Fork-ledger row #15** — add at the top of the patch-divergences table in `external/ds4/docs/fork-ledger.md`, in the same `| # | change | commits | why | reopen when |` shape as #14:

```
| 15 | advertise the `test` and `lint` host-tool schemas under `--host-tools` | (this commit) | the engine cannot execute `test`/`lint` without a host, so they must not be advertised on a host-less wire; the DSML/DeepSeek block is untouched exactly like `dispatch` (divergence #12). The `bash` schema description now advertises host-digested output. | upstream grows a native test/lint tool surface; then the schemas are the engine's implementation of it |
```

- [ ] **Step 7: Commit**

```bash
git add external/ds4/ds4_agent.c external/ds4/docs/fork-ledger.md external/ds4/tests/ds4_agent_test.c
git commit -m "P24.3: engine advertises test/lint under --host-tools (fork divergence #15)"
```

---

### Task 11: Golden recapture + provenance

**Files:**
- Modify: `fixtures/agent/golden.ndjson`, `fixtures/agent/golden.trace`, `fixtures/agent/golden.stderr` (regenerated)
- Modify: `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}` (the bundled copies)
- Modify: `fixtures/agent/provenance.md`

**Interfaces:**
- Consumes: the Task 10 engine build. The standing rule: every submodule bump that touches engine code owes a golden recapture.

- [ ] **Step 1: Build the engine**

Run: `just engine`
Expected: the fork builds with divergence #15.

- [ ] **Step 2: Recapture the fixture**

Run: `CAPTURE_GGUF=<path-to-a-laguna-gguf> just capture` (per `fixtures/agent/provenance.md`'s "Recapture rule": the fixture is the sanctioned output of `swiftstar-drive`).
Expected: `fixtures/agent/golden.ndjson` (and `golden.trace`) regenerate.

- [ ] **Step 3: Verify the wire contract survived**

Run: `just integration`
Expected: green — `FixtureReplayTests`, the `DiagnosticsEvidenceFloorTests` no-critical-findings floor, and `bundledFixtureMatchesRepoFixture` (bundled == repo) all pass.

- [ ] **Step 4: Copy to the bundled resources**

Run:
```bash
cp fixtures/agent/golden.ndjson Sources/SwiftStarAppKit/Resources/golden.ndjson
cp fixtures/agent/golden.trace Sources/SwiftStarAppKit/Resources/golden.trace
```

- [ ] **Step 5: Update `fixtures/agent/provenance.md`** — record the recapture: the divergence #15 date, the capture command, and confirm the handshake `caps`/`tool_request`-free bare wire invariants still hold (follow the file's existing per-recapture entry shape).

- [ ] **Step 6: Commit**

```bash
git add fixtures/agent/ Sources/SwiftStarAppKit/Resources/golden.ndjson Sources/SwiftStarAppKit/Resources/golden.trace
git commit -m "P24.3: golden recapture after divergence #15 (test/lint schemas)"
```

---

### Task 12: Measurement — paired-bill close gate

**Files:**
- Create: `docs/superpowers/research/2026-08-30-p24-3-run-digest-after-measurement.md`
- Create: `Tools/p24-3-measurement/` (the committed protocol: prompts, script, what each knob claims)

**Interfaces:**
- Consumes: the shipped tools (Tasks 1–11), `swiftstar-analyze diff`/`rereads`, `CaptureUsability.recordsWork`.
- Produces: the close-gate evidence — the pre-registered falsifier answered either way. This is the cycle's one live step (real engine, Metal).

- [ ] **Step 1: Write the pre-registered protocol** — commit `Tools/p24-3-measurement/` before running anything: the replay scenario (the observed session's intent: verify the SwiftStar project after a change), the two arms (tools available vs. control without them), the falsifier, and the capture-selection rule (`CaptureUsability.recordsWork`, never "completed turn"). State explicitly that a tool's self-reported savings are a claim about its counterfactual — the number is the paired-bill Σsuffix from `swiftstar-analyze diff`, not the tool's own word.

- [ ] **Step 2: Run the control arm** — the observed session shape without the tools (raw `bash`, condenser truncation): capture, then record the Σsuffix baseline.

- [ ] **Step 3: Run the treatment arm** — the same intent with `test`/`lint` available: capture, then `swiftstar-analyze diff` against the control.

- [ ] **Step 4: Answer the falsifier** — "the digest drops nothing decision-relevant": did the model act correctly on the digest alone in the treatment capture? Record the verdict either way (per the repo's after-measurement discipline — a post-hoc rewrite of the threshold is the documented anti-pattern).

- [ ] **Step 5: Commit the note + protocol**

```bash
git add docs/superpowers/research/2026-08-30-p24-3-run-digest-after-measurement.md Tools/p24-3-measurement/
git commit -m "P24.3: paired-bill measurement (run+digest family)"
```

---

## Self-review notes

- **Spec coverage:** Evidence 1 (host-owned commands) → Tasks 2, 8, 9. Evidence 2 (scout) → recorded in the spec for the scout cycle, not this plan. Evidence 3 (validation contract) → spec's Out of scope, its own item. Full-output valve (saved artifact + command echo) → Task 3/4/6 shapes + Task 8 `assemble`. `ok` semantics → Task 8. Selector charset → Task 2 + Task 8. Engine schemas under `--host-tools`, DSML untouched → Task 10. Recapture → Task 11. Measurement → Task 12. Non-carryovers (dead-letter, "completed turn") → Task 12 protocol.
- **Type consistency:** `CommandOutput`, `ToolDigest` (with `sha256`), `TestDigest.Failure`, `RuffDigest.Diagnostic`, `ProjectCommandResolver.testCommand/lintCommand/isValidSelector`, `CommandToolRunner.assemble/runTest/runLint/runBash` are defined once (Tasks 1, 2, 8) and consumed verbatim in later tasks. The `ToolKind` enum is internal to `CommandToolRunner` — Task 9 uses only `assemble(out:command:kind:runsDir:)` with `.bash`, `.test`, `.lint` as literals.
- **Integration-tier scope choice (documented):** the full pytest/`swift test` subprocess run is exercised once (Task 9's tiny Swift fixture) and measured live (Task 12); `CommandToolRunnerTests` cover `assemble` synthetically, `runBash` with a real subprocess, and the refusal paths — so no heavy/networked test enters the integration suite.
