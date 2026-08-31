# Host-controlled action mode (text contract) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Mellum-class models a text contract (emit labeled file blocks; the host harvests, writes, validates) and produce two host-verified results — a repair fix and a build candidate — to settle whether Mellum is "ready to improve" rather than "fundamentally broken."

**Architecture:** Approach A — directive-in-loop. The model stays in the agent loop; a `textContract` packet directive says "do not call tools, emit labeled blocks." A new fail-closed `LabeledBlockParser` harvests the turn's text (first-complete-block-wins, allowlist-exact, fence-parity), the host writes files and injects the harvested paths into `TurnOutcome.mutations` so the existing `WorktreeDispatch.verdict` produces a candidate. Repair ships first (strongest existing evidence); the step-0 forcing gate runs first and gates how much of the build path is built.

**Tech Stack:** Swift 6 (SwiftStarKit = pure logic, SwiftStarAppKit = IO), Swift Testing (`@Test`/`#expect`), no engine changes.

**Spec:** [`docs/superpowers/specs/2026-08-25-host-controlled-action-mode-design.md`](../specs/2026-08-25-host-controlled-action-mode-design.md) — the plan argues from the spec's decisions D1–D11; executors read both.

## Global Constraints

- All new types are `struct`/`enum` with explicit `Sendable` conformance (Swift 6 strict concurrency).
- `SwiftStarKit` holds pure logic (no I/O, no subprocess); `SwiftStarAppKit` holds I/O. `LabeledBlockParser` is pure; file writes live behind `WorktreeDispatcher`.
- Fast-tier tests (SwiftStarKitTests) run under the `FastTierGuard` plugin: no model, no network, no subprocess. The live experiments (forcing gate, repair, build) are manual, never CI.
- Follow existing test style: Swift Testing `import Testing`, `@Test func`, `#expect`, `Issue.record`.
- Existing wire semantics must not change: `.limit`/`.contextFull` stays session-exhaustion; `.noChanges + eos` keeps meaning "grade the accumulated tree."
- Commit after every task.

## File Structure

- Create: `Sources/SwiftStarKit/LabeledBlockParser.swift` — the fail-closed parser + `HarvestResult` + `TextContract.directive`.
- Delete: `Sources/SwiftStarKit/ThinkHarvest.swift`, `Tests/SwiftStarKitTests/ThinkHarvestTests.swift` (unwired dead code for a different mechanism).
- Create: `Tests/SwiftStarKitTests/LabeledBlockParserTests.swift`.
- Modify: `Sources/SwiftStarKit/TurnOutcome.swift` — add `text` capture.
- Modify: `Tests/SwiftStarKitTests/TurnOutcomeTests.swift` — text-capture test.
- Modify: `Sources/SwiftStarKit/HandoffPacket.swift` — `textContract` field.
- Modify: `Sources/SwiftStarKit/PhasePacketBuilder.swift` — `textContract`/`turnBudget` params.
- Modify: `Sources/SwiftStarKit/DispatchOutcome.swift` — `.contractNotFollowed` receipt.
- Modify: `Sources/SwiftStarAppKit/WorktreeDispatcher.swift` — public `writeFile` helper.
- Modify: `Sources/swiftstar-agenttest/main.swift` — forcing gate, harvest hook, `textContract` in `phasePacket`/`repairPacket`.
- Modify: `Sources/SwiftStarAppKit/RepairLoop.swift` — harvest seam + cap guard.
- Modify: `Sources/SwiftStar/AgentController.swift` + `Sources/SwiftStar/DispatchView.swift` — `.contractNotFollowed` switch arms.

---

### Task 1: LabeledBlockParser (fail-closed) + delete ThinkHarvest

**Files:**
- Create: `Sources/SwiftStarKit/LabeledBlockParser.swift`
- Delete: `Sources/SwiftStarKit/ThinkHarvest.swift`, `Tests/SwiftStarKitTests/ThinkHarvestTests.swift`
- Test: `Tests/SwiftStarKitTests/LabeledBlockParserTests.swift`

**Interfaces:**
- Produces: `HarvestResult` (struct: `files: [(path: String, content: String)]`, `outOfGrantHeadings: [String]`, `duplicateCounts: [String: Int]`); `LabeledBlockParser.parse(_ text: String, writableFiles: [String]) -> HarvestResult`; `TextContract.directive` (String).

- [ ] **Step 1: Delete the dead code**

```bash
git rm Sources/SwiftStarKit/ThinkHarvest.swift Tests/SwiftStarKitTests/ThinkHarvestTests.swift
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/SwiftStarKitTests/LabeledBlockParserTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct LabeledBlockParserTests {
    private let allowlist = ["app.py", "models.py", "templates/base.html", "tests/test_app.py"]

    @Test func harvestsALabeledBlock() {
        let text = "### `app.py`\n```python\nfrom fastapi import FastAPI\napp = FastAPI()\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
        #expect(r.files[0].content == "from fastapi import FastAPI\napp = FastAPI()")
    }

    @Test func firstCompleteBlockWinsAndDuplicatesAreCounted() {
        let text = """
        ### `app.py`
        ```
        full = True
        ```
        some re-review prose
        ### `app.py`
        ```
        import x
        ```
        """
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].content == "full = True")
        #expect(r.duplicateCounts["app.py"] == 1)
    }

    @Test func headingInsideAFenceDoesNotFlipAttribution() {
        let text = """
        ### `app.py`
        ```
        # a heading-looking line inside code:
        ### `models.py`
        real = True
        ```
        """
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
        #expect(r.files[0].content.contains("### `models.py`"))
    }

    @Test func fenceWithoutHeadingIsIgnored() {
        let text = "```\norphan = True\n```\n"
        #expect(LabeledBlockParser.parse(text, writableFiles: allowlist).files.isEmpty)
    }

    @Test func unterminatedFenceIsDropped() {
        let text = "### `app.py`\n```\npartial = True\n"
        #expect(LabeledBlockParser.parse(text, writableFiles: allowlist).files.isEmpty)
    }

    @Test func headingWithNoFenceIsDroppedAndNotCarriedForward() {
        let text = "### `app.py`\nsome prose, no fence follows\n### `models.py`\n```\nok = 1\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "models.py")
    }

    @Test func digitBearingInfoStringIsAccepted() {
        let text = "### `templates/base.html`\n```jinja2\n<div>x</div>\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "templates/base.html")
    }

    @Test func pathNormalization() {
        let text = "### `./app.py`\n```\nok = 1\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
    }

    @Test func outOfGrantHeadingIsDroppedAndRecorded() {
        let text = "### `README.md`\n```\nsecret\n```\n### `app.py`\n```\nok = 1\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
        #expect(r.outOfGrantHeadings == ["README.md"])
    }

    @Test func noBacktickHeadingIsNotAHeading() {
        // A prose line like "### app.py" (no backticks) is not a label.
        #expect(LabeledBlockParser.parse("### app.py\n```\nx=1\n```\n", writableFiles: allowlist).files.isEmpty)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter LabeledBlockParserTests`
Expected: compile error — `LabeledBlockParser` not found.

- [ ] **Step 4: Write the implementation**

Create `Sources/SwiftStarKit/LabeledBlockParser.swift`:

```swift
import Foundation

/// The pinned directive a text-contract packet inserts in place of the
/// "use your write tool" note (spec Section 1).
public enum TextContract {
    public static let directive = """
    Do not call tools. For each file, emit a heading line `### \u{0060}<path>\u{0060}` (path relative \
    to the workspace root), immediately followed by one fenced code block containing the complete \
    file contents. A fenced block with no preceding heading is ignored.
    """
}

/// One parsed text-contract turn: the files the model emitted as labeled
/// blocks (first-complete-block-wins), plus the diagnostics the failure
/// classification needs. Pure — no I/O.
public struct HarvestResult: Equatable, Sendable {
    public let files: [(path: String, content: String)]
    public let outOfGrantHeadings: [String]
    public let duplicateCounts: [String: Int]

    public init(files: [(path: String, content: String)],
                outOfGrantHeadings: [String],
                duplicateCounts: [String: Int]) {
        self.files = files
        self.outOfGrantHeadings = outOfGrantHeadings
        self.duplicateCounts = duplicateCounts
    }
}

/// Fail-closed parser for the text output contract (spec Section 1). The rules:
/// a heading `### \u{0060}path\u{0060}` is accepted only if its *normalized* path
/// exactly equals an allowlist entry; it must be immediately followed (optional
/// one blank line) by a fenced block; an unterminated fence is dropped; a fence
/// with no accepted heading is ignored; a heading inside a fenced body does not
/// flip attribution; first complete block per file wins, duplicates counted;
/// an out-of-grant heading is dropped and recorded.
public enum LabeledBlockParser {
    public static func parse(_ text: String, writableFiles: [String]) -> HarvestResult {
        let allowlist = Set(writableFiles.map(normalize))
        var files: [(path: String, content: String)] = []
        var seen = Set<String>()
        var duplicateCounts: [String: Int] = [:]
        var outOfGrant: [String] = []

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < lines.count {
            if isFence(lines[i]) {
                // A fence with no accepted heading: skip to its close.
                i += 1
                while i < lines.count, !isFence(lines[i]) { i += 1 }
                i += 1
                continue
            }
            if let path = headingPath(lines[i]) {
                var j = i + 1
                if j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    j += 1  // optional single blank line
                }
                if j < lines.count, isFence(lines[j]) {
                    var body: [String] = []
                    var k = j + 1
                    var closed = false
                    while k < lines.count {
                        if isFence(lines[k]) { closed = true; break }
                        body.append(lines[k])
                        k += 1
                    }
                    if closed {
                        let norm = normalize(path)
                        if allowlist.contains(norm) {
                            if seen.contains(norm) {
                                duplicateCounts[norm, default: 0] += 1
                            } else {
                                seen.insert(norm)
                                files.append((norm, body.joined(separator: "\n")))
                            }
                        } else {
                            outOfGrant.append(path)
                        }
                    }
                    i = k + 1
                    continue
                }
                // Heading with no fence before the next line: dropped, not carried forward.
                i += 1
                continue
            }
            i += 1
        }
        return HarvestResult(files: files, outOfGrantHeadings: outOfGrant, duplicateCounts: duplicateCounts)
    }

    static func normalize(_ path: String) -> String {
        var p = path
        while p.hasPrefix("./") { p.removeFirst(2) }
        p = p.replacingOccurrences(of: "//", with: "/")
        p = p.replacingOccurrences(of: "/./", with: "/")
        while p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    static func headingPath(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("### `"), t.hasSuffix("`") else { return nil }
        let inner = t.dropFirst(5).dropLast()
        guard !inner.contains("`") else { return nil }
        return String(inner)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter LabeledBlockParserTests`
Expected: all 10 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/LabeledBlockParser.swift Tests/SwiftStarKitTests/LabeledBlockParserTests.swift
git commit -m "text-contract: fail-closed LabeledBlockParser, replace unwired ThinkHarvest"
```

---

### Task 2: Capture assistant text in TurnOutcome

Harvest needs the model's text, which `TurnOutcome` does not carry today.

**Files:**
- Modify: `Sources/SwiftStarKit/TurnOutcome.swift`
- Test: `Tests/SwiftStarKitTests/TurnOutcomeTests.swift`

**Interfaces:**
- Produces: `TurnOutcome.text: String` (default `""`), populated from the wire's `.text` events.

- [ ] **Step 1: Write the failing test**

Add to `Tests/SwiftStarKitTests/TurnOutcomeTests.swift` (or a new file if absent):

```swift
@Test func builderAccumulatesText() {
    var b = TurnOutcomeBuilder(model: "m", build: "b", sampler: "s", task: "t")
    b.apply(.text("Hello "))
    b.apply(.text("world."))
    let o = b.finish()
    #expect(o.text == "Hello world.")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TurnOutcomeTests`
Expected: FAIL — `TurnOutcome` has no member `text` / `.text` case not accepted.

- [ ] **Step 3: Implement**

In `TurnOutcome.swift`:
1. Add `public var text: String = ""` beside `mutations` (the `var` host-facts block).
2. In `TurnOutcomeBuilder`, add `private var text = ""`.
3. In `apply(_:)`, change the `break` case list: remove `.text` from the `break` arm and add a new arm before it:

```swift
case .text(let s):
    text += s
case .hello, .status, .queued, .think, .ignored, .refused, .toolRequestRefused:
    break
```

4. In `finish()`, after `outcome.validationRan = self.validationRan`, add `outcome.text = self.text`.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TurnOutcomeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/TurnOutcome.swift Tests/SwiftStarKitTests/TurnOutcomeTests.swift
git commit -m "text-contract: capture assistant text in TurnOutcome"
```

---

### Task 3: Schema — textContract field + contractNotFollowed receipt

**Files:**
- Modify: `Sources/SwiftStarKit/HandoffPacket.swift`
- Modify: `Sources/SwiftStarKit/PhasePacketBuilder.swift`
- Modify: `Sources/SwiftStarKit/DispatchOutcome.swift`
- Modify: `Sources/SwiftStar/AgentController.swift`, `Sources/SwiftStar/DispatchView.swift` (switch arms)
- Test: `Tests/SwiftStarKitTests/HandoffPacketTests.swift`

**Interfaces:**
- Produces: `HandoffPacket.textContract: Bool` (default false); `PhasePacketBuilder.build(..., textContract: Bool = false, turnBudget: Int = 100_000, ...)`; `Receipt.contractNotFollowed`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/SwiftStarKitTests/HandoffPacketTests.swift`:

```swift
@Test func textContractDecodesWhenPresent() throws {
    let json = """
    {"taskText":"t","writableFiles":["app.py"],"validationCommand":"uv run x","baselines":{},"turnBudget":100,"toolCallBudget":5,"textContract":true}
    """
    let pkt = try JSONDecoder().decode(HandoffPacket.self, from: Data(json.utf8))
    #expect(pkt.textContract == true)
}

@Test func textContractDefaultsFalseWhenAbsent() throws {
    let json = """
    {"taskText":"t","writableFiles":["app.py"],"validationCommand":"uv run x","baselines":{},"turnBudget":100,"toolCallBudget":5}
    """
    let pkt = try JSONDecoder().decode(HandoffPacket.self, from: Data(json.utf8))
    #expect(pkt.textContract == false)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter HandoffPacketTests`
Expected: FAIL — `textContract` not a key / decoding error.

- [ ] **Step 3: Implement the field + receipt**

In `HandoffPacket.swift`:
1. Add `public let textContract: Bool` after `toolCallBudget`.
2. In the memberwise `init`, add `textContract: Bool = false` after `toolCallBudget: Int` and set `self.textContract = textContract`.
3. In `init(from:)`, add `textContract = try container.decodeIfPresent(Bool.self, forKey: .textContract) ?? false` after the `toolCallBudget` line. (The synthesized `CodingKeys` gains `.textContract` automatically.)

In `DispatchOutcome.swift`, add to `Receipt`:

```swift
/// The text-contract turn produced no usable labeled blocks (initiation
/// failure). Distinct from `.noChanges` so the existing `noChanges+eos ->
/// continue` branch cannot swallow it.
case contractNotFollowed
```

- [ ] **Step 4: Fix exhaustive switches**

Run `swift build` and fix every `switch` that now reports a missing case. Known sites: `AgentController.swift` (receipt switch, ~line 563) and `DispatchView.swift` (~line 149). For `.contractNotFollowed`, render: `"the worker produced no labeled files (text contract not followed)"`.

- [ ] **Step 5: Extend PhasePacketBuilder**

In `PhasePacketBuilder.build`, add two parameters after `toolCallBudget: Int`:

```swift
textContract: Bool = false,
turnBudget: Int = 100_000,
```

and in the returned `HandoffPacket(`, replace the hardcoded `turnBudget: 100_000` with `turnBudget: turnBudget` and add `textContract: textContract`.

- [ ] **Step 6: Run tests + build**

Run: `swift test --filter HandoffPacketTests` and `swift build`
Expected: PASS + clean build.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftStarKit/HandoffPacket.swift Sources/SwiftStarKit/PhasePacketBuilder.swift Sources/SwiftStarKit/DispatchOutcome.swift Sources/SwiftStar/AgentController.swift Sources/SwiftStar/DispatchView.swift Tests/SwiftStarKitTests/HandoffPacketTests.swift
git commit -m "text-contract: HandoffPacket.textContract + Receipt.contractNotFollowed"
```

---

### Task 4: WorktreeDispatcher.writeFile + mutation injection

**Files:**
- Modify: `Sources/SwiftStarAppKit/WorktreeDispatcher.swift`
- Test: `Tests/SwiftStarIntegrationTests/WorktreeTransactionTests.swift` (or a new integration test)

**Interfaces:**
- Produces: `WorktreeDispatcher.writeFile(_ content: String, to path: String, in worktree: URL) throws`; the injection is `outcome.mutations = harvestedRelativePaths` (callers do this).

- [ ] **Step 1: Write the failing test**

Add an integration test (real temp dir, no model):

```swift
@Test func writeFileCreatesParentDirs() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try WorktreeDispatcher.writeFile("x = 1", to: "templates/base.html", in: dir)
    let url = dir.appendingPathComponent("templates/base.html")
    #expect(try String(contentsOf: url, encoding: .utf8) == "x = 1")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter WorktreeTransactionTests`
Expected: FAIL — `writeFile` not found.

- [ ] **Step 3: Implement**

In `WorktreeDispatcher.swift`, add next to `runValidation`:

```swift
/// Write one harvested file's content into the worktree, creating parent
/// directories as needed (text-contract harvest). The path is a worktree-
/// relative writable path (may contain `/` separators).
public static func writeFile(_ content: String, to path: String, in worktree: URL) throws {
    let url = file(path, in: worktree)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try content.write(to: url, atomically: true, encoding: .utf8)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter WorktreeTransactionTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarAppKit/WorktreeDispatcher.swift Tests/SwiftStarIntegrationTests/WorktreeTransactionTests.swift
git commit -m "text-contract: WorktreeDispatcher.writeFile for harvest"
```

---

### Task 5: Step-0 forcing gate (run first, gates the build path)

**Files:**
- Modify: `Sources/swiftstar-agenttest/main.swift` (inside `runOnce`, between `orch.runPhase` and `runValidation`)

**Interfaces:**
- Consumes: `TurnOutcome.toolCalls`, `orch.runPhase`, `phasePacket`.
- Produces: a re-prompt loop bounded by `AGENTTEST_FORCE` (default 0 = off).

- [ ] **Step 1: Implement the re-prompt loop**

First change the binding `let outcome: TurnOutcome` (declared just above the `do`/`catch`) to `var outcome: TurnOutcome` — the loop reassigns it.

Then, immediately after the `do`/`catch` that sets `outcome = try orch.runPhase(...)` and before the `WorktreeDispatcher.runValidation` call, insert:

```swift
// Step-0 forcing gate (experiment): on a zero-tool-call turn, re-prompt with
// an explicit "emit a tool call" directive, bounded by AGENTTEST_FORCE.
var forced = 0
var forcingOutcome = outcome
let maxForces = Int(env["AGENTTEST_FORCE"] ?? "0") ?? 0
while forcingOutcome.toolCalls.isEmpty, forced < maxForces {
    forced += 1
    print("[agenttest]   forcing re-prompt \(forced)/\(maxForces) (0 tool calls)")
    let forcingPacket = phasePacket(
        "The previous turn produced no tool calls. Do not narrate a plan: emit a tool call now and keep working.")
    forcingOutcome = try orch.runPhase(worker: WorkerId(1), packet: forcingPacket, worktree: wt.url, capture: captureHandle)
}
outcome = forcingOutcome
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean build. (`wt` and `captureHandle` and `WorkerId(1)` are already in scope in `runOnce`.)

- [ ] **Step 3: Run the experiment (manual, long)**

Run: `AGENTTEST_FORCE=2 swift run swiftstar-agenttest --variant mellum-2.1 --spec roadmap`
Expected: capture records how many forced rounds produced tool calls. Record the 0→N measurement in the spec's Verification item 1.

- [ ] **Step 4: Commit**

```bash
git add Sources/swiftstar-agenttest/main.swift
git commit -m "text-contract: step-0 forcing gate (AGENTTEST_FORCE)"
```

---

### Task 6: Text-contract repair (first live experiment)

**Files:**
- Modify: `Sources/SwiftStarAppKit/RepairLoop.swift` (harvest seam + cap guard)
- Modify: `Sources/swiftstar-agenttest/main.swift` (`repairPacket` — add `textContract: true` + directive)

**Interfaces:**
- Consumes: `LabeledBlockParser.parse`, `WorktreeDispatcher.writeFile`, `TurnOutcome.text`, `WorktreeDispatcher.finalize`.
- Produces: a text-contract repair that yields a `.candidate` from a text-only turn, or `.contractNotFollowed`.

- [ ] **Step 1: Write the failing integration test**

Add to the integration tests (fake engine emits a labeled repair block, no tool calls):

```swift
@Test func textContractRepairProducesCandidate() throws {
    // Build a repair whose FakeAgentSource emits a labeled block for app.py
    // and no tool calls; assert RepairLoop.run returns .passed after the host
    // writes the block and the real acceptance suite passes.
    // (Full fixture in the existing FakeAgentSource pattern; the assertion is
    // the deliverable — a text-only turn must grade .passed, not .exhausted.)
    #expect(/* RepairLoop.run(...) == .passed(...) */ true)
}
```

(If a full fake-engine repair fixture is too large for one step, split it: first the cap-guard unit test, then the seam, then the live run.)

- [ ] **Step 2: Add the cap guard in RepairLoop.run**

Before assembling `MachineEvidence` (the `for path in authored.writableFiles` loop), add:

```swift
// Text-contract repair re-emits a *complete* file; evidence truncated to
// `fileCap` would be re-emitted truncated and overwrite a good copy. Refuse
// the round instead of silently shipping a partial view.
if authored.textContract {
    for path in authored.writableFiles {
        let url = fileURL(path, in: wt.url)
        if let data = FileManager.default.contents(atPath: url.path),
           data.count > fileCap {
            write(record: RoundRecord(round: round, candidateRef: nil, receipt: .contractNotFollowed, grade: nil, elapsed: Int(Date().timeIntervalSince(start))), to: captureDir)
            return .exhausted(lastGrade: lastGrade, receipt: .contractNotFollowed)
        }
    }
}
```

- [ ] **Step 3: Insert the harvest + mutation-injection seam**

First change `let turn = try runPhase(...)` to `var turn = try runPhase(...)` — the seam mutates `turn.mutations`.

Then, between that line (and its `.limit` guard) and `let validation = try WorktreeDispatcher.runValidation(...)`, insert:

```swift
if packet.textContract, turn.toolCalls.isEmpty, turn.stopReason == .eos {
    let harvest = LabeledBlockParser.parse(turn.text, writableFiles: packet.writableFiles)
    if harvest.files.isEmpty {
        write(record: RoundRecord(round: round, candidateRef: nil, receipt: .contractNotFollowed, grade: nil, elapsed: Int(Date().timeIntervalSince(start))), to: captureDir)
        return .exhausted(lastGrade: lastGrade, receipt: .contractNotFollowed)
    }
    for (path, content) in harvest.files {
        try WorktreeDispatcher.writeFile(content, to: path, in: wt.url)
    }
    turn.mutations = harvest.files.map(\.path)
}
```

- [ ] **Step 4: Make repairPacket text-contract**

In `main.swift`'s `repairPacket`, pass `textContract: true` to `PhasePacketBuilder.build` and prefix the directive into `writableNote`:

```swift
let writableNote = ([
    TextContract.directive,
    "",
    "You may write or edit only these files:",
    renderedFiles,
] + pathRule + [...]).joined(separator: "\n")
```

- [ ] **Step 5: Build + fast tests**

Run: `swift build && swift test --filter LabeledBlockParserTests`
Expected: clean + pass.

- [ ] **Step 6: Run the repair experiment (manual, long)**

Run the existing fixture repair tier against Mellum text-contract: `swift run swiftstar-agenttest --variant mellum-2.1 --fixture plausible-wrong-fix`
Expected: a host-verified fix (the failing test passes after host re-run) — spec Verification item 4. Record it.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftStarAppKit/RepairLoop.swift Sources/swiftstar-agenttest/main.swift
git commit -m "text-contract: repair seam (harvest + mutation injection + cap guard)"
```

---

### Task 7: Text-contract build (second, gated by Task 5)

Build only if Task 5's forcing gate did **not** move Mellum 0→N.

**Files:**
- Modify: `Sources/swiftstar-agenttest/main.swift` (`phasePacket` — `textContract: true` + directive; `runOnce` — harvest hook)

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: a text-contract build candidate from a text-only turn, or `.contractNotFollowed`.

- [ ] **Step 1: Make phasePacket text-contract**

In `phasePacket`, prepend `TextContract.directive` to `writableNote` and pass `textContract: true` to `PhasePacketBuilder.build`, with a `turnBudget` computed from expected file bytes (e.g. `max(100_000, renderedFiles.utf8.count * 4)`).

- [ ] **Step 2: Insert the harvest hook in runOnce**

After the Task 5 forcing-gate block, before `WorktreeDispatcher.runValidation`, insert:

```swift
// Text-contract harvest: a zero-tool-call eos turn's labeled blocks become the
// phase's mutations (spec Section 2 step 3).
if packet.textContract, outcome.toolCalls.isEmpty, outcome.stopReason == .eos {
    let harvest = LabeledBlockParser.parse(outcome.text, writableFiles: seedPacket.writableFiles)
    if harvest.files.isEmpty {
        return RunOutcome(finish: .stopped,
                          note: "phase \(i + 1) contractNotFollowed (0 labeled blocks)",
                          acceptanceExit: nil, verdict: nil, report: nil,
                          elapsed: Int(Date().timeIntervalSince(runStart)))
    }
    for (path, content) in harvest.files {
        try WorktreeDispatcher.writeFile(content, to: path, in: wt.url)
    }
    outcome.mutations = harvest.files.map(\.path)
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 4: Run the build experiment (manual, long)**

Run: `swift run swiftstar-agenttest --variant mellum-2.1 --spec roadmap`
Expected: a host-verified candidate (imports clean, required file set covered, failures bucketed content) — spec Verification item 6. Record it.

- [ ] **Step 5: Commit**

```bash
git add Sources/swiftstar-agenttest/main.swift
git commit -m "text-contract: build harvest hook + phasePacket textContract"
```

---

## Self-review notes

- D1→Tasks 6/7 (directive-in-loop); D2→Task 3; D3→Task 1; D4→Task 4 + Tasks 6/7 seams; D5→Tasks 6/7 (`toolCalls.isEmpty && .eos`); D6→Task 6; D7→Task 3; D8→Tasks 6/7 live runs; D9→Task 5; D10→Task 6 cap guard + Task 7 turnBudget; D11→capture labels (add `"textContract": ...` to `run-config.json` in Task 7 Step 4 — do not skip).
- Type consistency: `HarvestResult.files: [(path: String, content: String)]` is consumed as `harvest.files.map(\.path)` (→ `[String]`) everywhere; `LabeledBlockParser.parse(text:writableFiles:)` signature is used identically in Tasks 6 and 7.
- The `.contractNotFollowed` receipt is produced by the callers (returning `.exhausted`/`.stopped`), not by `WorktreeDispatch.verdict` — the verdict never sees a text-only turn with empty mutations because the callers short-circuit first. Keep it that way; do not teach the verdict about text mode.
- Risks: `TurnOutcome.text` must accumulate across the whole turn (not just the last event); the `FakeAgentSource` text-emitting path must be exercised in Task 6's integration test or the seam is untested.
