# P24.1 Window-Honoring Reads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the host's `read` honor `start_line`/`max_lines`/`whole`/`raw` in
the engine's own result format, byte-budgeted so every result fits under the
8000-byte condenser untouched — ending the starvation loop where the model
cannot reach the middle of any file over 8 KB.

**Architecture:** One pure renderer, `ReadWindow`, in `SwiftStarKit` (fast-tier
tested, no I/O). `HostToolExecutor` keeps all the I/O: it reads the file, calls
the renderer, and owns a continuation map keyed by workspace root so `more`
continues the right file even though the `.app` executor is shared by the main
agent and pool workers. `AgentController` supplies `contextSize` and resets the
map at session start. No engine change, no wire change, no recapture.

**Tech Stack:** Swift 6, `SwiftStarKit` + `SwiftStarAppKit` + `SwiftStar`, the
existing `HostToolExecutor`/`ToolCallbackResponder` machinery, Swift Testing
(`import Testing`). No model, no network, no subprocess.

**Spec:**
[`2026-08-30-p24-1-window-honoring-reads-design.md`](../specs/2026-08-30-p24-1-window-honoring-reads-design.md)
(decisions D1–D9; this plan argues from the spec).

## Global Constraints

- **Zero engine work.** No `external/ds4` change, no wire field, no tool name,
  no golden recapture (D8). Swift sources, tests, and documentation only.
- **Port the engine's strings verbatim** (D1). Header, line prefix, and
  bare-mode note are copied from `external/ds4/ds4_agent.c:8138-8163`. Do not
  improve the wording — a divergence is a second contract behind one tool name.
- **The D2 invariant is the point of the whole cycle:** the header's line range
  always names exactly the lines present in the body, and the rendered result
  never exceeds `byteBudget` (7000). Task 2 Step 6 pins it; Task 3 keeps it true
  through the executor.
- **`readCache` is untouched** (D7). The `.pool` branch
  (`HostToolExecutor.swift:161-181`) stays byte-for-byte identical; its existing
  tests must pass unmodified.
- **Red-first** (BRIEF.md rule 2): every changed or new test is shown failing
  before the implementation lands. Where the first red is a *compile* failure
  rather than an assertion failure, this plan says so explicitly — a compile
  error is a different signal and must not be reported as behavioral red.
- **A refusal test has a sibling success test** (BRIEF.md rule 4).
- **Verification reaches the immediate caller** (spec rule 4). Task 2 Step 6's
  `condense` test exists because violating this rule is what invalidated the
  superseded design.

---

## Task 1: Correct the documents the withdrawn design left behind

Three committed artifacts still teach the overturned model. An implementer who
reads them first will build coverage state this design deleted. No code changes.

**Files:**
- Modify: `docs/superpowers/plans/2026-08-30-p24-1-read-guard.md` (header)
- Modify: `docs/superpowers/research/2026-08-30-p24-1-read-guard-before-measurement.md` (§ "Two facts the design must not lose", and the closing § "The after measurement")
- Modify: `Sources/swiftstar-analyze/main.swift:225-230` (the `ReadRequest` doc comment)

**Interfaces:** none — documentation and one comment.

- [ ] **Step 1: Supersede the withdrawn plan**

At the top of `docs/superpowers/plans/2026-08-30-p24-1-read-guard.md`, directly
under the `#` title line, insert:

```markdown
> **SUPERSEDED 2026-08-30. Do not implement.** This plan implements the
> read-guard design, withdrawn after review falsified its premise — see the
> [superseding spec](../specs/2026-08-30-p24-1-window-honoring-reads-design.md)
> and the withdrawal note on the
> [read-guard spec](../specs/2026-08-30-p24-1-read-guard-design.md). Its
> replacement is
> [`2026-08-30-p24-1-window-honoring-reads.md`](2026-08-30-p24-1-window-honoring-reads.md).
```

- [ ] **Step 2: Correct the before-measurement's framing**

In `docs/superpowers/research/2026-08-30-p24-1-read-guard-before-measurement.md`,
insert immediately after the `# ` title line:

```markdown
> **Correction 2026-08-30.** The counts below are correct and reproducible; the
> *framing* is not. "55 redundant re-reads" counts the repeats of a starvation
> loop as redundancy. The host ignores every window parameter and the responder
> condenses each result at 8000 bytes
> (`ToolCallbackResponder.swift:259,284`), so the middle of a file over 8 KB is
> unreachable: the model asked for `AgentView.swift`'s line 252 in 22 distinct
> windows and could never receive it. Those reads were not redundant — none of
> them delivered what was asked for.
>
> **§2 below ("Window coverage is the hard part") was right**, and is the
> premise of the superseding design,
> [`2026-08-30-p24-1-window-honoring-reads-design.md`](../specs/2026-08-30-p24-1-window-honoring-reads-design.md).
> **§1 ("Redundant is a ceiling") is withdrawn**: unchanged content does not
> make a re-read redundant when the prior read never delivered the requested
> lines.
```

Then, in the closing section `## The "after" measurement`, replace its body with:

```markdown
Superseded. That measurement described a replay through the withdrawn guard,
and was arithmetically incapable of returning anything but the numbers above
(short-circuits are forced to `calls − distinct` when every read of a path
hashes the same bytes). The successor cycle's measurement is behavioral: see
"Live validation" in
[the window-honoring spec](../specs/2026-08-30-p24-1-window-honoring-reads-design.md).
```

- [ ] **Step 3: Correct the `rereads` verb's doc comment**

In `Sources/swiftstar-analyze/main.swift`, replace lines 225-230 (the doc
comment above `struct ReadRequest`) with:

```swift
/// A `read`/`more` tool_request reduced to what the measurement cares about:
/// the worker (which session read it) and the path (what it read). Windowed
/// reads (`start_line`/`max_lines`/`offset`/`end_line`) are flagged because the
/// *distribution of windows* is the signal: many distinct windows clustered on
/// one region of one file is the signature of the P24.1 starvation loop — the
/// model asking repeatedly for lines the host never served. (Before P24.1 the
/// host ignored these parameters entirely and returned the whole file, which
/// the responder then condensed at 8000 bytes.)
```

- [ ] **Step 4: Verify nothing else still teaches the withdrawn model**

```bash
grep -rn "read-guard\|read guard\|don't-re-read\|unchanged since turn" --include=*.swift --include=*.md . | grep -v superseded | grep -v "docs/superpowers/specs/2026-08-30-p24-1-read-guard-design.md" | grep -v "docs/superpowers/plans/2026-08-30-p24-1-read-guard.md"
```

Expected: hits only in `ROADMAP.md` (the P24 row, already corrected to describe
the re-scope) and the new spec/plan, which reference the withdrawn design
deliberately. Any other hit is a document this step must fix.

- [ ] **Step 5: Build and commit**

```bash
swift build
git add docs/superpowers/plans/2026-08-30-p24-1-read-guard.md docs/superpowers/research/2026-08-30-p24-1-read-guard-before-measurement.md Sources/swiftstar-analyze/main.swift
git commit -m "P24.1 Task 1: retire the withdrawn read-guard's documents

Supersede its plan, correct the before-measurement's 'redundant re-reads'
framing (the repeats are a starvation loop, and its own section 2 was right),
and fix the rereads verb's doc comment, which described a tool never built."
```

---

## Task 2: `ReadWindow` — the pure renderer (SwiftStarKit)

**Files:**
- Create: `Sources/SwiftStarKit/ReadWindow.swift`
- Test: `Tests/SwiftStarKitTests/ReadWindowTests.swift`

**Interfaces:**
- Produces (consumed by Task 3):

```swift
public struct ReadWindowRequest: Equatable, Sendable {
    public let startLine: Int
    public let maxLines: Int?
    public let whole: Bool
    public let raw: Bool
    public init(startLine: Int = 1, maxLines: Int? = nil,
                whole: Bool = false, raw: Bool = false)
}

public struct ReadWindowResult: Equatable, Sendable {
    public let text: String
    public let nextLine: Int?
    public let lastLine: Int
    public let totalLines: Int
}

public enum ReadWindow {
    public static func defaultLines(contextSize: Int) -> Int
    public static func render(text: String, path: String,
                              request: ReadWindowRequest,
                              defaultLines: Int,
                              byteBudget: Int = 7000) -> ReadWindowResult
}
```

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiftStarKitTests/ReadWindowTests.swift`. Use a plain `struct`
with `@Test` methods — the convention in `Tests/SwiftStarKitTests/` (no file
there uses `@Suite`).

```swift
import Foundation
import Testing
@testable import SwiftStarKit

struct ReadWindowTests {
    /// 5 lines, "l1".."l5".
    private func sample(_ n: Int) -> String {
        (1...n).map { "l\($0)" }.joined(separator: "\n") + "\n"
    }

    // MARK: - tier defaults (ds4_agent.c:8090, :7885-7889)

    @Test func defaultLinesMatchesTheEngineTiers() {
        #expect(ReadWindow.defaultLines(contextSize: 8192) == 120)
        #expect(ReadWindow.defaultLines(contextSize: 16384) == 240)
        #expect(ReadWindow.defaultLines(contextSize: 32768) == 500)
        #expect(ReadWindow.defaultLines(contextSize: 8193) == 240)
    }

    // MARK: - window arithmetic

    @Test func servesTheRequestedWindow() {
        let r = ReadWindow.render(text: sample(5), path: "a.txt",
            request: .init(startLine: 2, maxLines: 2), defaultLines: 500)
        #expect(r.text.contains("2 l2\n3 l3\n"))
        #expect(!r.text.contains("4 l4"))
        #expect(r.lastLine == 3)
        #expect(r.nextLine == 4)
        #expect(r.totalLines == 5)
    }

    @Test func startLineBelowOneClampsToOne() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(startLine: 0, maxLines: 1), defaultLines: 500)
        #expect(r.text.contains("1 l1\n"))
    }

    @Test func startLinePastEndYieldsAnEmptyBodyAtEOF() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(startLine: 99), defaultLines: 500)
        #expect(r.nextLine == nil)
        #expect(!r.text.contains("l1"))
        #expect(r.totalLines == 3)
    }

    @Test func maxLinesPastEndClampsAndReachesEOF() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(startLine: 1, maxLines: 99), defaultLines: 500)
        #expect(r.lastLine == 3)
        #expect(r.nextLine == nil)
    }

    @Test func wholeReachesEOFWhenItFits() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(whole: true), defaultLines: 1)
        #expect(r.lastLine == 3)
        #expect(r.nextLine == nil)
    }

    // MARK: - header shapes (ds4_agent.c:8148-8154)

    @Test func truncatedHeaderCarriesContinueOffset() {
        let r = ReadWindow.render(text: sample(5), path: "a.txt",
            request: .init(startLine: 1, maxLines: 2), defaultLines: 500)
        #expect(r.text.hasPrefix(
            "a.txt: lines 1-2 of 5; continue_offset=3; call more with count=2 to read the next chunk\n"))
    }

    @Test func eofHeaderOmitsContinueOffset() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(startLine: 1, maxLines: 3), defaultLines: 500)
        #expect(r.text.hasPrefix("a.txt: lines 1-3 of 3\n"))
        #expect(!r.text.contains("continue_offset"))
    }

    @Test func headerCountUsesTheTierDefaultWhenMaxLinesAbsent() {
        let r = ReadWindow.render(text: sample(10), path: "a.txt",
            request: .init(startLine: 1), defaultLines: 4)
        #expect(r.text.hasPrefix(
            "a.txt: lines 1-4 of 10; continue_offset=5; call more with count=4 to read the next chunk\n"))
    }

    @Test func lineBodyUsesTheEngineOneBasedPrefix() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(startLine: 1, maxLines: 3), defaultLines: 500)
        #expect(r.text.hasSuffix("1 l1\n2 l2\n3 l3\n"))
    }

    // MARK: - D2: the byte budget wins, and the header never lies

    @Test func byteBudgetCutsBeforeMaxLines() {
        let fat = (1...200).map { "\($0) " + String(repeating: "x", count: 200) }
            .joined(separator: "\n") + "\n"
        let r = ReadWindow.render(text: fat, path: "a.txt",
            request: .init(startLine: 1, maxLines: 200), defaultLines: 500,
            byteBudget: 2000)
        #expect(r.text.utf8.count <= 2000)
        #expect(r.lastLine < 200, "the budget must cut before max_lines")
        #expect(r.nextLine == r.lastLine + 1)
    }

    /// Sibling success for the refusal-adjacent case above (BRIEF rule 4):
    /// when the budget does not bind, the full max_lines is served.
    @Test func budgetDoesNotCutWhenItDoesNotBind() {
        let r = ReadWindow.render(text: sample(5), path: "a.txt",
            request: .init(startLine: 1, maxLines: 5), defaultLines: 500,
            byteBudget: 7000)
        #expect(r.lastLine == 5)
        #expect(r.nextLine == nil)
    }

    @Test func headerRangeAlwaysNamesExactlyTheLinesInTheBody() {
        let fat = (1...300).map { "line \($0) " + String(repeating: "y", count: 90) }
            .joined(separator: "\n") + "\n"
        let r = ReadWindow.render(text: fat, path: "a.txt",
            request: .init(startLine: 7, maxLines: 300), defaultLines: 500,
            byteBudget: 3000)
        #expect(r.text.hasPrefix("a.txt: lines 7-\(r.lastLine) of 300;"))
        let body = r.text.split(separator: "\n").dropFirst()
        #expect(body.count == r.lastLine - 6)
        #expect(body.first?.hasPrefix("7 ") == true)
        #expect(body.last?.hasPrefix("\(r.lastLine) ") == true)
    }

    /// The test that would have caught the withdrawn design's error: a rendered
    /// window must survive the responder's condenser untouched (spec rule 4).
    @Test func aRenderedWindowSurvivesTheCondenserUnchanged() {
        let fat = (1...5000).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let r = ReadWindow.render(text: fat, path: "a.txt",
            request: .init(startLine: 1), defaultLines: 500)
        #expect(ToolResultCondenser.condense(r.text) == r.text)
    }

    // MARK: - D6: progress is guaranteed

    @Test func aSingleOverBudgetLineIsTruncatedInBandAndAdvances() {
        let huge = String(repeating: "z", count: 9000) + "\nnext\n"
        let r = ReadWindow.render(text: huge, path: "a.txt",
            request: .init(startLine: 1), defaultLines: 500, byteBudget: 2000)
        #expect(r.text.utf8.count <= 2000)
        #expect(r.text.contains("[line 1 truncated at "))
        #expect(r.lastLine == 1)
        #expect(r.nextLine == 2, "continue_offset must advance or `more` loops forever")
    }

    // MARK: - raw mode (ds4_agent.c:8138-8143)

    @Test func rawModeEmitsBytesWithoutPrefixesAndNotesTruncation() {
        let r = ReadWindow.render(text: sample(5), path: "a.txt",
            request: .init(startLine: 1, maxLines: 2, raw: true), defaultLines: 500)
        #expect(r.text.hasPrefix("l1\nl2\n"))
        #expect(!r.text.contains("1 l1"))
        #expect(r.text.contains(
            "[Read truncated at line 2 of 5. continue_offset=3. Call more with count=2 to read the next chunk.]"))
    }

    @Test func rawModeAtEOFHasNoNote() {
        let r = ReadWindow.render(text: sample(2), path: "a.txt",
            request: .init(startLine: 1, maxLines: 2, raw: true), defaultLines: 500)
        #expect(r.text == "l1\nl2\n")
        #expect(r.nextLine == nil)
    }

    // MARK: - edges

    @Test func emptyFileRendersZeroLines() {
        let r = ReadWindow.render(text: "", path: "a.txt",
            request: .init(), defaultLines: 500)
        #expect(r.totalLines == 0)
        #expect(r.nextLine == nil)
        #expect(r.text.hasPrefix("a.txt: lines 0-0 of 0\n"))
    }

    @Test func fileWithoutTrailingNewlineCountsItsLastLine() {
        let r = ReadWindow.render(text: "a\nb", path: "a.txt",
            request: .init(), defaultLines: 500)
        #expect(r.totalLines == 2)
        #expect(r.text.hasSuffix("1 a\n2 b\n"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
swift test --filter ReadWindowTests
```

Expected: **compile failure** — `cannot find 'ReadWindow' in scope`. This is a
build error, not behavioral red; the file does not exist yet. The behavioral red
for this task is the executor's, in Task 3 Step 2.

- [ ] **Step 3: Implement**

Create `Sources/SwiftStarKit/ReadWindow.swift`:

```swift
import Foundation

/// Renders one window of a file in the engine's own `read` result format
/// (`external/ds4/ds4_agent.c:8102-8174`), bounded by a byte budget the engine
/// does not need: every host tool result is condensed at 8000 bytes by
/// `ToolCallbackResponder`, so a window that overflows would be cut into
/// head+tail and the middle would never reach the model. Budgeting here instead
/// keeps the guarantee that makes the result honest:
///
/// > the header's line range always names exactly the lines present in the
/// > body, and the output never exceeds `byteBudget`.
///
/// Pure: no I/O, no model. The caller reads the file and owns continuation
/// state.
public struct ReadWindowRequest: Equatable, Sendable {
    public let startLine: Int
    public let maxLines: Int?
    public let whole: Bool
    public let raw: Bool

    public init(startLine: Int = 1, maxLines: Int? = nil,
                whole: Bool = false, raw: Bool = false) {
        self.startLine = startLine
        self.maxLines = maxLines
        self.whole = whole
        self.raw = raw
    }
}

public struct ReadWindowResult: Equatable, Sendable {
    /// Header + body, always ≤ the requested byte budget.
    public let text: String
    /// 1-based line to continue from, or nil when the window reached EOF.
    /// nil is the executor's signal to clear the continuation (D4).
    public let nextLine: Int?
    /// Last line number present in the body (0 when the body is empty).
    public let lastLine: Int
    public let totalLines: Int
}

public enum ReadWindow {
    /// The engine's context tier (`ds4_agent.c:8090`, constants `:7885-7889`).
    public static func defaultLines(contextSize: Int) -> Int {
        if contextSize > 0 && contextSize <= 8192 { return 120 }
        if contextSize > 0 && contextSize <= 16384 { return 240 }
        return 500
    }

    public static func render(text: String, path: String,
                              request: ReadWindowRequest,
                              defaultLines: Int,
                              byteBudget: Int = 7000) -> ReadWindowResult {
        let lines = splitLines(text)
        let total = lines.count
        let startIdx = min(max(request.startLine, 1) - 1, total)

        // The ceiling: `whole` means "to EOF", otherwise max_lines or the tier.
        let requested = request.maxLines ?? defaultLines
        let ceiling = request.whole ? total - startIdx : max(requested, 1)
        let ceilingEnd = min(total, startIdx + ceiling)

        // Reserve the worst-case header so the body budget cannot overflow the
        // total. The real header is never longer than this one.
        let reserved = request.raw
            ? bareNote(lastLine: total, total: total, count: requested).utf8.count
            : header(path: path, start: startIdx + 1, end: total,
                     total: total, truncated: true, count: requested).utf8.count
        let bodyBudget = max(0, byteBudget - reserved)

        var body = ""
        var used = 0
        var endIdx = startIdx
        while endIdx < ceilingEnd {
            let rendered = request.raw
                ? lines[endIdx] + "\n"
                : "\(endIdx + 1) \(lines[endIdx])\n"
            let cost = rendered.utf8.count
            if used + cost > bodyBudget {
                // D6: always make progress. A first line that alone exceeds the
                // budget is truncated in-band rather than dropped, so
                // continue_offset can advance and `more` cannot loop forever.
                if endIdx == startIdx {
                    let marker = "[line \(endIdx + 1) truncated at "
                    let room = max(0, bodyBudget - marker.utf8.count - 32)
                    let cut = utf8Prefix(lines[endIdx], budget: room)
                    body += (request.raw ? cut : "\(endIdx + 1) \(cut)")
                    body += "\n[line \(endIdx + 1) truncated at \(cut.utf8.count)"
                    body += " of \(lines[endIdx].utf8.count) bytes]\n"
                    endIdx += 1
                }
                break
            }
            body += rendered
            used += cost
            endIdx += 1
        }

        let truncated = endIdx < total
        let lastLine = endIdx
        let out: String
        if request.raw {
            out = body + (truncated
                ? bareNote(lastLine: lastLine, total: total, count: requested)
                : "")
        } else {
            out = header(path: path, start: total == 0 ? 0 : startIdx + 1,
                         end: lastLine, total: total,
                         truncated: truncated, count: requested) + body
        }
        return ReadWindowResult(text: out,
                                nextLine: truncated ? lastLine + 1 : nil,
                                lastLine: lastLine, totalLines: total)
    }

    // MARK: - the engine's strings (ds4_agent.c:8138-8154), ported verbatim

    private static func header(path: String, start: Int, end: Int, total: Int,
                               truncated: Bool, count: Int) -> String {
        truncated
            ? "\(path): lines \(start)-\(end) of \(total); continue_offset=\(end + 1); call more with count=\(count) to read the next chunk\n"
            : "\(path): lines \(start)-\(end) of \(total)\n"
    }

    private static func bareNote(lastLine: Int, total: Int, count: Int) -> String {
        "[Read truncated at line \(lastLine) of \(total). continue_offset=\(lastLine + 1). Call more with count=\(count) to read the next chunk.]\n"
    }

    /// Mirrors `agent_split_lines`: a trailing newline does not create a final
    /// empty line, so "a\nb\n" is two lines and "a\nb" is also two.
    private static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var parts = text.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    /// Longest prefix of `s` that fits `budget` UTF-8 bytes, cut on a codepoint
    /// boundary (never mid-scalar, so the output is always valid UTF-8).
    private static func utf8Prefix(_ s: String, budget: Int) -> String {
        if s.utf8.count <= budget { return s }
        var out = ""
        var used = 0
        for ch in s {
            let n = String(ch).utf8.count
            if used + n > budget { break }
            out.append(ch)
            used += n
        }
        return out
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
swift test --filter ReadWindowTests
```

Expected: all 18 tests pass. If `aRenderedWindowSurvivesTheCondenserUnchanged`
fails, the default `byteBudget` is too close to 8000 — lower it, do not raise
the condenser's limit.

- [ ] **Step 5: Confirm the fast tier still accepts the new file**

```bash
swift test
```

Expected: full suite green. `SwiftStarKitTests` runs under the `FastTierGuard`
plugin (`Package.swift:55`), which fails the build on `Process(`, `URLSession`,
`NWConnection`, `posix_spawn`, `Darwin.`, `socket(`. `ReadWindow` uses none of
them; if the build fails here, an import crept in.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/ReadWindow.swift Tests/SwiftStarKitTests/ReadWindowTests.swift
git commit -m "P24.1 Task 2: ReadWindow — pure windowed-read renderer

Ports the engine's read result format (ds4_agent.c:8102-8174) with a 7000-byte
budget the engine does not need, because every host tool result is condensed at
8000. Pins the invariant: the header's line range always names exactly the lines
in the body, and a rendered window survives condense() unchanged."
```

---

## Task 3: `HostToolExecutor` — windowed reads and `more` continuation

**Files:**
- Modify: `Sources/SwiftStarAppKit/HostToolExecutor.swift`
  (`init` :86; instance state :82-84; `readResult` :160, app branch :182-191)
- Modify (test): `Tests/SwiftStarIntegrationTests/HostToolExecutorTests.swift`
  (rewrite `appPolicyReadReturnsFullTextEveryTime` at :37; add a new section)

**Interfaces:**
- Consumes: `ReadWindow`, `ReadWindowRequest`, `ReadWindowResult` (Task 2).
- Produces (consumed by Task 4):
  - `init(policy:contextSize:)` — `contextSize` defaults to 32768
  - `func setContextSize(_ n: Int)`
  - `func resetReadState()`

- [ ] **Step 1: Rewrite the behavior-pinning test red**

`appPolicyReadReturnsFullTextEveryTime` (:37) asserts `first.text == "hello"`.
Windowing changes that for *every* file, small ones included, because the result
now carries the header and the line-number prefix. Rename and rewrite it:

```swift
    @Test func appPolicyReadRendersTheEngineWindowFormat() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "hello".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)
        let req = request("read", [], workspace: ws, path: "a.txt")

        let first = executor.execute(req)
        let second = executor.execute(req)
        #expect(first.text.hasSuffix(": lines 1-1 of 1\n1 hello\n"))
        #expect(second.text == first.text,
                "the app policy has no read cache — a second read serves the same window")
    }
```

- [ ] **Step 2: Run to verify it fails — behaviorally**

```bash
swift test --filter HostToolExecutorTests
```

Expected: **assertion failure**, `first.text` is `"hello"` but the test expects
the windowed format. This is genuine behavioral red: the test compiles and runs
against today's executor, which ignores window parameters. The pool-policy tests
in the same suite still pass.

- [ ] **Step 3: Add the new tests** (same file, new `// MARK: -` section)

Use the file's existing helpers: `makeWorkspace()` (:19),
`request(_:_:workspace:path:)` (:26), `param(_:_:)` (:31). Note
`request(name, params, workspace: ws, path: nil)` yields `resolvedPath: nil`.

```swift
    // MARK: - P24.1 windowed reads and `more` continuation

    /// 40 lines, "l1".."l40".
    private func write40(_ ws: URL) throws {
        let text = (1...40).map { "l\($0)" }.joined(separator: "\n") + "\n"
        try text.write(to: ws.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
    }

    @Test func readHonorsStartLineAndMaxLines() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try write40(ws)
        let executor = HostToolExecutor(policy: .app)
        let r = executor.execute(request("read",
            [param("start_line", "10"), param("max_lines", "3")],
            workspace: ws, path: "big.txt"))
        #expect(r.ok)
        #expect(r.text.contains("lines 10-12 of 40; continue_offset=13;"))
        #expect(r.text.contains("10 l10\n11 l11\n12 l12\n"))
        #expect(!r.text.contains("13 l13"))
    }

    @Test func moreContinuesFromTheContinueOffset() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try write40(ws)
        let executor = HostToolExecutor(policy: .app)
        _ = executor.execute(request("read",
            [param("start_line", "1"), param("max_lines", "5")],
            workspace: ws, path: "big.txt"))
        let more = executor.execute(request("more", [param("count", "5")],
            workspace: ws, path: nil))
        #expect(more.ok)
        #expect(more.text.contains("lines 6-10 of 40"))
        #expect(more.text.contains("6 l6\n"))
        #expect(!more.text.contains("5 l5\n"), "no line may repeat across the seam")
    }

    @Test func readingToEOFClearsTheContinuation() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "hello".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)
        _ = executor.execute(request("read", [], workspace: ws, path: "a.txt"))
        let more = executor.execute(request("more", [], workspace: ws, path: nil))
        #expect(!more.ok)
        #expect(more.text.contains("no previous output to continue"))
    }

    @Test func moreWithNoPriorReadErrors() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let executor = HostToolExecutor(policy: .app)
        let more = executor.execute(request("more", [], workspace: ws, path: nil))
        #expect(!more.ok)
        #expect(more.text.contains("no previous output to continue"))
    }

    /// D5: the `.app` executor is shared by the main agent and pool workers, so
    /// continuation state must be keyed by workspace root. A single scalar
    /// fails this test.
    @Test func continuationsAreKeyedPerWorkspaceRoot() throws {
        let wsA = try makeWorkspace(), wsB = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: wsA)
                try? FileManager.default.removeItem(at: wsB) }
        try write40(wsA)
        let textB = (1...40).map { "b\($0)" }.joined(separator: "\n") + "\n"
        try textB.write(to: wsB.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)

        _ = executor.execute(request("read", [param("max_lines", "5")], workspace: wsA, path: "big.txt"))
        _ = executor.execute(request("read", [param("max_lines", "5")], workspace: wsB, path: "big.txt"))
        let moreA = executor.execute(request("more", [param("count", "2")], workspace: wsA, path: nil))
        #expect(moreA.text.contains("6 l6"), "A's `more` must continue A's file, not B's")
        #expect(!moreA.text.contains("b6"))
    }

    @Test func resetReadStateClearsContinuations() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try write40(ws)
        let executor = HostToolExecutor(policy: .app)
        _ = executor.execute(request("read", [param("max_lines", "5")], workspace: ws, path: "big.txt"))
        executor.resetReadState()
        let more = executor.execute(request("more", [], workspace: ws, path: nil))
        #expect(!more.ok)
        #expect(more.text.contains("no previous output to continue"))
    }

    @Test func contextSizeSelectsTheEngineTier() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try write40(ws)
        let executor = HostToolExecutor(policy: .app, contextSize: 8192)  // 120-line tier
        let r = executor.execute(request("read", [], workspace: ws, path: "big.txt"))
        #expect(r.text.contains("lines 1-40 of 40"), "40 < the 120-line tier, so EOF")
        executor.setContextSize(32768)
        #expect(executor.execute(request("read", [], workspace: ws, path: "big.txt")).text
            .contains("lines 1-40 of 40"))
    }

    /// Sibling success for the two refusal tests above (BRIEF rule 4).
    @Test func readOutsideGrantStillRefusesAndInsideStillServes() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "hello".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)
        let refused = executor.execute(request("read", [], workspace: ws, path: nil))
        #expect(!refused.ok)
        #expect(refused.text.contains("outside the workspace grant"))
        #expect(executor.execute(request("read", [], workspace: ws, path: "a.txt")).ok)
    }
```

- [ ] **Step 4: Run to verify the new tests fail**

```bash
swift test --filter HostToolExecutorTests
```

Expected: **compile failure** — `resetReadState`, `setContextSize`, and
`init(policy:contextSize:)` do not exist yet. This is a build error, not
behavioral red; the behavioral red for this task was Step 2. Proceed to Step 5.

- [ ] **Step 5: Implement**

In `Sources/SwiftStarAppKit/HostToolExecutor.swift`:

1. Import: add `import SwiftStarKit` if not already present (it is — `Policy`
   already uses kit types).
2. Instance state, next to `readCacheStorage` (:84):

```swift
    /// P24.1 (D5): `more` continuation per workspace root. The `.app` executor
    /// is a process-lifetime static shared by the main agent and every pool
    /// worker (`AgentPoolTurnLoop.swift:138`), so a single scalar would let a
    /// worker's read retarget the main agent's next `more`. Workers run in
    /// per-turn UUID worktrees, so roots are disjoint for free.
    private var continuations: [String: (path: String, nextLine: Int, bare: Bool)] = [:]
    private var contextSize: Int
```

3. Replace the initializer (:86):

```swift
    public init(policy: Policy, contextSize: Int = 32768) {
        self.policy = policy
        self.contextSize = contextSize
    }

    /// D3: the app's executor is a `static let` with no settings at type-init,
    /// so it takes its context size at session start instead of construction.
    public func setContextSize(_ n: Int) {
        lock.withLock { contextSize = n }
    }

    /// Clears `more` continuations. Only the app's process-lifetime static
    /// needs this; `PoolOrchestrator` gets a fresh instance per phase.
    public func resetReadState() {
        lock.withLock { continuations.removeAll() }
    }
```

4. Replace the app branch of `readResult` (:182-191, everything after the
   `readCache` block) with:

```swift
        // P24.1: the app's shape — windowed, in the engine's format
        // (ds4_agent.c:8102-8174), byte-budgeted so the responder's condenser
        // never has to cut it (D2).
        let root = HostToolConfinement.realPath(request.workspace.path,
                                                workspace: request.workspace)
            ?? request.workspace.path
        var windowRequest = ReadWindowRequest(
            startLine: intParam(request, "start_line") ?? 1,
            maxLines: intParam(request, "max_lines"),
            whole: boolParam(request, "whole"),
            raw: boolParam(request, "raw"))
        let path: String

        if request.name == "more" {
            // D4: `more` continues; it never re-reads. Consent defaults its
            // missing `path` to the workspace root, so the recorded
            // continuation — not `resolvedPath` — is the authority.
            guard let c = lock.withLock({ continuations[root] }) else {
                return ToolExecutionResult(ok: false,
                    text: "error: no previous output to continue")
            }
            path = c.path
            windowRequest = ReadWindowRequest(
                startLine: c.nextLine,
                maxLines: intParam(request, "count"),
                whole: false, raw: c.bare)
        } else {
            guard let p = HostToolConfinement.realPath(request) else {
                return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
            }
            path = p
        }

        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return ToolExecutionResult(ok: false, text: "error: could not read \(path)")
        }
        let tier = ReadWindow.defaultLines(contextSize: lock.withLock { contextSize })
        let window = ReadWindow.render(text: text, path: path,
                                       request: windowRequest, defaultLines: tier)
        lock.withLock {
            // Mirrors agent_worker_set_more (ds4_agent.c:8167-8170): record on
            // a truncated read, CLEAR at EOF so a later `more` refuses honestly.
            if let next = window.nextLine {
                continuations[root] = (path: path, nextLine: next, bare: windowRequest.raw)
            } else {
                continuations.removeValue(forKey: root)
            }
        }
        return ToolExecutionResult(ok: true, text: window.text)
    }

    private func intParam(_ r: ToolExecutionRequest, _ name: String) -> Int? {
        r.params.first(where: { $0.name == name }).flatMap { Int($0.value) }
    }

    private func boolParam(_ r: ToolExecutionRequest, _ name: String) -> Bool {
        let v = r.params.first(where: { $0.name == name })?.value.lowercased()
        return v == "true" || v == "1"
    }
```

The `readCache` branch above it (:161-181) is **not touched** (D7).

- [ ] **Step 6: Run the suite**

```bash
swift test --filter HostToolExecutorTests
swift test
```

Expected: `HostToolExecutorTests` green, including the untouched pool-policy
tests; full suite green. If `ToolCallbackResponderTests` or
`AgentTestAnalyzerTests` fail, a fixture asserted on the old whole-file read
output — update the fixture to the windowed format; do not weaken the renderer.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftStarAppKit/HostToolExecutor.swift Tests/SwiftStarIntegrationTests/HostToolExecutorTests.swift
git commit -m "P24.1 Task 3: honor read windows and implement more continuation

The app read path now renders through ReadWindow in the engine's format and
records a per-workspace-root continuation, cleared at EOF so `more` refuses
honestly instead of inventing one. Keyed by root because the .app executor is
shared with pool workers. Pool readCache branch untouched (D7)."
```

---

## Task 4: Supply `contextSize` and reset at session start

**Files:**
- Modify: `Sources/SwiftStar/AgentController.swift` (session start/restart block :359-384)
- Modify: `Sources/SwiftStarAppKit/PoolOrchestrator.swift` (:19, :80, :208)

**Interfaces:**
- Consumes: `HostToolExecutor.setContextSize(_:)`, `resetReadState()`,
  `init(policy:contextSize:)` (Task 3).

- [ ] **Step 1: Implement the controller wiring**

In `Sources/SwiftStar/AgentController.swift`, inside the session start/restart
block that already resets `outcomeBuilder` (:380) and `poolState` (:384) — it
runs on both `startAgent` and `restartAgent` — add:

```swift
        // P24.1 (D3/D5): the executor is a process-lifetime `static let`, so
        // it cannot take the context size at construction, and its `more`
        // continuations outlive a session unless cleared here.
        Self.hostToolExecutor.setContextSize(settings.contextSize)
        Self.hostToolExecutor.resetReadState()
```

- [ ] **Step 2: Implement the orchestrator wiring**

In `Sources/SwiftStarAppKit/PoolOrchestrator.swift`, pass the harness's context
size at all three construction sites, so agenttest reads use the same tier as
the engine it is measuring:

- `:19` — `HostToolExecutor(policy: .pool(vettedCommands: []), contextSize: contextSize)`
- `:80` — `HostToolExecutor(policy: .pool(vettedCommands: vettedCommands), contextSize: contextSize)`
- `:208` — `HostToolExecutor(policy: .app, contextSize: contextSize)`

If `PoolOrchestrator` has no `contextSize` of its own, add a `let contextSize:
Int` initializer parameter defaulting to `32768` and thread it from the
`swiftstar-agenttest` call site; do **not** read it from the environment here —
the harness's config belongs at its entry point.

- [ ] **Step 3: Verify build, suite, and wiring**

```bash
swift build
swift test
grep -n "setContextSize\|resetReadState" Sources/SwiftStar/AgentController.swift
grep -n "contextSize:" Sources/SwiftStarAppKit/PoolOrchestrator.swift
```

Expected: build clean; full suite green; exactly one `setContextSize` and one
`resetReadState` call in the controller, both inside the start/restart block;
three `contextSize:` arguments in `PoolOrchestrator`. Review the diff: the calls
must be in the block that runs on restart, not only on first start — a stale
continuation surviving a restart is the bug this pins.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftStar/AgentController.swift Sources/SwiftStarAppKit/PoolOrchestrator.swift
git commit -m "P24.1 Task 4: supply contextSize and reset read state at session start

The app's static executor takes its tier at session start (it has no settings at
type-init) and clears more-continuations on start and restart. PoolOrchestrator
passes its context size at all three construction sites."
```

---

## Task 5: The measurement — the pre-registered falsifier

The spec's success criterion is behavioral, not a token count (D9, rule 5). This
task records the answer either way.

**Files:**
- Create: `docs/superpowers/research/2026-08-30-p24-1-window-honoring-after-measurement.md`
- Modify: `docs/superpowers/specs/2026-08-30-p24-1-window-honoring-reads-design.md` (status stamp)
- Modify: `ROADMAP.md` (P24 row status cell)

**Interfaces:** consumes the shipped behavior from Tasks 2–4.

- [ ] **Step 1: Confirm the 1809 counterfactual directly**

`AgentView.swift`'s `bottomStatusBar` is the content the 1809 session spent 32
reads failing to reach. With the app built from Task 4, run a session and issue
one read:

```
read Sources/SwiftStar/AgentView.swift start_line=252 max_lines=80
```

Expected: the result contains the `bottomStatusBar` definition and a header
reading `lines 252-331 of <N>`. Record the result verbatim in the note. If the
lines do not appear, stop — the cycle has not delivered its premise.

- [ ] **Step 2: Run a read-heavy live session and extract its read sequence**

Run the 1809 shape — explore this repo, work on a file over 8000 bytes, let it
compact at least once — with the guard-free windowed build. Then, from the repo
root (`resolveDir`/`captureRoot()` are cwd-relative,
`Sources/swiftstar-analyze/main.swift:16-18,58-74`):

```bash
swift run swiftstar-analyze rereads --latest
```

- [ ] **Step 3: Answer the falsifier in the note**

Create `docs/superpowers/research/2026-08-30-p24-1-window-honoring-after-measurement.md`
containing, in this order:

1. The Step 1 counterfactual result verbatim.
2. The Step 2 command and full output.
3. **The falsifier, answered.** The pre-registered failure condition (spec, Live
   validation): *many distinct windows clustered on one region of one file.*
   Tabulate the window distribution for the hottest path the way the spec's
   Problem section does for the 1809 capture, and state plainly whether the
   pattern is gone. **If it is not gone, this cycle failed** — record that, do
   not re-explain it.
4. `swift run swiftstar-analyze diff <new capture> live/20260827-200648` as
   secondary evidence, with the Σsuffix ratio recorded whatever it is, and the
   explicit note that a rise is acceptable if turns now complete (rule 5).

- [ ] **Step 4: Stamp the spec and the roadmap**

Change the spec's `**Status:** proposed` to `**Status:** implemented`, and update
the P24 row's status cell in `ROADMAP.md` from
`**planned — P24.1 spec written 2026-08-30 (re-scoped); …**` to record P24.1 as
landed with a link to the after-measurement note.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/research/2026-08-30-p24-1-window-honoring-after-measurement.md docs/superpowers/specs/2026-08-30-p24-1-window-honoring-reads-design.md ROADMAP.md
git commit -m "P24.1 Task 5: after-measurement — the falsifier, answered

Records the 1809 counterfactual (one read of AgentView.swift:252 now returns
bottomStatusBar), the live window distribution against the pre-registered
failure condition, and the paired-bill diff as secondary evidence."
```

---

## Self-Review Notes

- **Spec coverage.** D1 (engine format ported verbatim — Task 2 Step 3, header
  and bareNote helpers; pinned by Task 2's header/raw tests). D2 (byte budget
  wins, invariant — Task 2 Steps 1/3, tests
  `byteBudgetCutsBeforeMaxLines`, `headerRangeAlwaysNamesExactlyTheLinesInTheBody`,
  `aRenderedWindowSurvivesTheCondenserUnchanged`). D3 (tier + both delivery
  mechanisms — Task 3 Step 5 item 3, Task 4 Steps 1/2, test
  `contextSizeSelectsTheEngineTier`). D4 (`more` continues, EOF clears — Task 3
  Step 5 item 4, tests `moreContinuesFromTheContinueOffset`,
  `readingToEOFClearsTheContinuation`, `moreWithNoPriorReadErrors`). D5 (keyed
  by workspace root — Task 3, test `continuationsAreKeyedPerWorkspaceRoot`).
  D6 (progress on an over-budget line — Task 2, test
  `aSingleOverBudgetLineIsTruncatedInBandAndAdvances`). D7 (`readCache`
  untouched — Task 3 Step 5 closing note; its existing tests run unmodified).
  D8 (pure type + one seam, zero engine — by construction). D9 (behavioral
  criterion — Task 5 Step 3).
  Spec tests 1–7 map to Task 2; 8–12 to Task 3; Live validation to Task 5.
  The spec's "Documents this spec invalidates" section maps to Task 1.
- **Red-first honesty.** Task 2 Step 2 and Task 3 Step 4 predict *compile*
  failures and say so; Task 3 Step 2 is the one genuine behavioral red
  (`first.text == "hello"` against the windowed format) and is sequenced first
  in that task for exactly that reason. This is the defect the review found in
  the withdrawn plan, corrected here.
- **Placeholder scan.** Every step names concrete files, signatures, test names,
  and commands. The one conditional — Task 4 Step 2's "if `PoolOrchestrator` has
  no `contextSize` of its own" — states both branches and the rule for choosing.
- **Type consistency.** `ReadWindowRequest(startLine:maxLines:whole:raw:)`,
  `ReadWindowResult.text/nextLine/lastLine/totalLines`,
  `ReadWindow.render(text:path:request:defaultLines:byteBudget:)`,
  `ReadWindow.defaultLines(contextSize:)`, `setContextSize(_:)`,
  `resetReadState()`, `init(policy:contextSize:)` are spelled identically in
  Tasks 2, 3 and 4.
- **Known follow-ups, deliberately not in this plan.** The pool `readCache`
  honesty bug and the read-guard re-decision are P24.2 (spec, Scope/Out); the
  agenttest instrument reconciliation is P24's last cycle (`ROADMAP.md` P24 row).
  Task 4 Step 2 changes what agenttest reads return, so the open campaign arm
  must be finished or re-baselined around this cycle — stated in the spec's
  Component 4, and worth repeating to whoever runs the campaign.
