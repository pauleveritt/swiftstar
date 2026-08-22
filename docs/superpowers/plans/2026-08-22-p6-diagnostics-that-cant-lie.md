# P6 — Diagnostics That Can't Lie: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deterministic diagnostics analyzer (SwiftStarKit), wire it into a real Diagnostics tab (fixture-driven), and meet the evidence floor — accept a healthy capture, reject a pathological one.

**Architecture:** A pure `DiagnosticsAnalyzer` turns parsed wire events + parsed trace events into typed `[Finding]` values; a `DeterministicPhraser` renders each finding to a sentence (the "model only phrases" seam — a model phraser can replace it later without touching the analyzer). A new `TraceParser` reads the engine's `--trace` side-channel (compaction stats + per-turn prefix-cache hits). The Diagnostics tab replays the committed `golden` capture through the production parsers, exactly as Metrics already does.

**Tech Stack:** Swift 6.3, SwiftPM, swift-testing. No engine patch, no Sphinx changes, no Package.swift target changes (all new files live in existing `SwiftStarKit` / `SwiftStarAppKit` / `SwiftStar` / `SwiftStarKitTests` targets).

**Spec:** `docs/superpowers/specs/2026-08-22-p6-diagnostics-that-cant-lie-design.md`

## Global Constraints

- **Fast tier** (`just test`): no model, no network, no subprocess (tripwire-guarded). Fixture reads by `#filePath`-relative path are allowed (that is how `WireEventParserTests` already reads `golden.ndjson`).
- **Binding rule 3** — no source-text assertions: tests assert on typed `Finding`/`TraceEvent` values, never on rendered sentence strings.
- **Binding rule 2** — every new test shown to fail first (in a compiled language, "fail" = the test target does not compile, or the assertion fails).
- **Binding rule 6** — evidence floor: accept a known-good capture, reject a known-broken one, each asserted by naming the fixture.
- **P6 must not spawn `ds4-agent` live** — the Diagnostics tab is fixture-driven until P7.
- **No model in P6** — phrasing is the deterministic `DeterministicPhraser`; nothing calls a model.
- Depth thresholds reuse `DialLogic.contextWarningTokens` / `contextCriticalTokens` (absolute); P6's own constants live in `DiagnosticsLogic` and are named, re-anchorable values.

---

### Task 1: `TraceEvent` + `TraceParser` (SwiftStarKit)

**Files:**
- Create: `Sources/SwiftStarKit/TraceParser.swift`
- Test: `Tests/SwiftStarKitTests/TraceParserTests.swift`

**Interfaces:**
- Produces: `public enum TraceEvent: Equatable, Sendable` with cases `.compaction(reason: String, old: Int, new: Int, tailStart: Int, tail: Int)`, `.prefillSync(prompt: Int, cached: Int, suffix: Int, rc: Int, ms: Double)`, `.ignored(String)`; `public struct TraceParser: Sendable { public init(); public mutating func feed(_ line: String) -> TraceEvent? }`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/TraceParserTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct TraceParserTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent")
    }

    @Test func parsesCompactionLine() {
        var p = TraceParser()
        let line = #"2026-08-22 14:41:09.813 compacted reason="ctx grew" old=150000 new=45000 tail_start=42000 tail=3000"#
        #expect(p.feed(line) == .compaction(reason: "ctx grew", old: 150000, new: 45000, tailStart: 42000, tail: 3000))
    }

    @Test func parsesCompactionWithEscapedReason() {
        var p = TraceParser()
        let line = #"2026-08-22 14:41:09.813 compacted reason="said \"hi\" and\ncontinued" old=100 new=40 tail_start=30 tail=10"#
        #expect(p.feed(line) == .compaction(reason: "said \"hi\" and\ncontinued", old: 100, new: 40, tailStart: 30, tail: 10))
    }

    @Test func parsesPrefillSyncWithToolRound() {
        var p = TraceParser()
        let line = "2026-08-22 14:41:10.704 prefill sync done tool_round=0 prompt=1026 cached=958 suffix=68 rc=0 575.820 ms"
        #expect(p.feed(line) == .prefillSync(prompt: 1026, cached: 958, suffix: 68, rc: 0, ms: 575.820))
    }

    @Test func parsesPrefillSyncWithoutToolRound() {
        var p = TraceParser()
        let line = "2026-08-22 14:41:10.704 prefill sync done prompt=1026 cached=958 suffix=68 rc=0 575.820 ms"
        #expect(p.feed(line) == .prefillSync(prompt: 1026, cached: 958, suffix: 68, rc: 0, ms: 575.820))
    }

    @Test func ignoresUnknownLines() {
        var p = TraceParser()
        let line = "2026-08-22 14:41:09.831 sysprompt kv hit file=./.ds4/kvcache/sysprompt.kv tokens=958"
        #expect(p.feed(line) == .ignored(line))
        let tokenLine = "2026-08-22 14:41:09.831 token index=0 id=2 bytes=11 text=\"x\" hex=78"
        #expect(p.feed(tokenLine) == .ignored(tokenLine))
    }

    @Test func goldenTraceParsesWithoutRefusing() throws {
        let url = Self.fixturesRoot.appendingPathComponent("golden.trace")
        let text = try String(contentsOf: url, encoding: .utf8)
        var p = TraceParser()
        var events: [TraceEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = p.feed(s) { events.append(e) }
        }
        let syncs = events.filter { if case .prefillSync = $0 { return true } else { return false } }
        #expect(syncs.count == 2)  // golden.trace has two turns, each with one prefill sync
    }
}
```

- [ ] **Step 2: Run to verify the failure**

Run: `just test`
Expected: FAIL — `TraceParserTests.swift` does not compile (`TraceParser` / `TraceEvent` undefined).

- [ ] **Step 3: Implement `TraceEvent` + `TraceParser`**

`Sources/SwiftStarKit/TraceParser.swift`:

```swift
import Foundation

/// One parsed event from the engine's `--trace` side-channel. `.ignored` carries
/// the raw line for anything not modelled — the trace is a diagnostic side-channel,
/// so unknown lines are never a refusal (unlike the handshake-guarded wire).
public enum TraceEvent: Equatable, Sendable {
    case compaction(reason: String, old: Int, new: Int, tailStart: Int, tail: Int)
    case prefillSync(prompt: Int, cached: Int, suffix: Int, rc: Int, ms: Double)
    case ignored(String)
}

/// Streaming parser for the `--trace` file, shaped like `WireEventParser`. Feed
/// one line; it returns a typed event or nil. Trace timestamps are deliberately
/// not carried — the analyzer's findings are session-level and trace-internal
/// order suffices.
public struct TraceParser: Sendable {
    public init() {}

    public mutating func feed(_ line: String) -> TraceEvent? {
        let message = Self.stripTimestamp(line)
        guard !message.isEmpty else { return nil }
        if message.hasPrefix("compacted reason=") {
            return Self.parseCompaction(message)
        }
        if message.hasPrefix("prefill sync done ") {
            return Self.parsePrefillSync(message)
        }
        return .ignored(line)
    }

    /// Trace lines are "<YYYY-MM-DD HH:MM:SS.mmm> <message>" (agent_trace_time,
    /// 23 chars + one space). Anything that is not that shape passes through whole.
    static func stripTimestamp(_ line: String) -> String {
        let a = Array(line)
        guard a.count > 24, a[4] == "-", a[7] == "-", a[10] == " ",
              a[13] == ":", a[16] == ":", a[19] == ".", a[23] == " " else { return line }
        return String(line.dropFirst(24))
    }

    /// `compacted reason="<escaped>" old=<n> new=<n> tail_start=<n> tail=<n>`
    static func parseCompaction(_ message: String) -> TraceEvent? {
        let prefix = "compacted reason=\""
        guard message.hasPrefix(prefix) else { return nil }
        let body = Array(message.dropFirst(prefix.count))
        var reason = ""
        var i = 0
        while i < body.count {
            if body[i] == "\\", i + 1 < body.count {
                let c = body[i + 1]
                switch c {
                case "n": reason.append("\n")
                case "r": reason.append("\r")
                case "t": reason.append("\t")
                default: reason.append(c)
                }
                i += 2
            } else if body[i] == "\"" {
                i += 1
                break
            } else {
                reason.append(body[i])
                i += 1
            }
        }
        let rest = String(body[i...])
        guard let old = Self.intField(rest, "old"),
              let new = Self.intField(rest, "new"),
              let tailStart = Self.intField(rest, "tail_start"),
              let tail = Self.intField(rest, "tail") else { return nil }
        return .compaction(reason: reason, old: old, new: new, tailStart: tailStart, tail: tail)
    }

    /// `prefill sync done [tool_round=<n>] prompt=<n> cached=<n> suffix=<n> rc=<n> <ms> ms`
    /// (`tool_round` is present in the agent turn loop, `ds4_agent.c:12071`, and absent
    /// at the older sync site `:5622` — both parse.)
    static func parsePrefillSync(_ message: String) -> TraceEvent? {
        guard let prompt = Self.intField(message, "prompt"),
              let cached = Self.intField(message, "cached"),
              let suffix = Self.intField(message, "suffix"),
              let rc = Self.intField(message, "rc") else { return nil }
        let ms = Self.millisField(message) ?? 0
        return .prefillSync(prompt: prompt, cached: cached, suffix: suffix, rc: rc, ms: ms)
    }

    /// First numeric run after the first occurrence of `key=`.
    static func intField(_ s: String, _ key: String) -> Int? {
        guard let r = s.range(of: " \(key)=") ?? s.range(of: "\(key)=") else { return nil }
        var v = ""
        for ch in s[r.upperBound...] {
            if ch.isNumber { v.append(ch) } else { break }
        }
        return Int(v)
    }

    /// The numeric token immediately before the trailing " ms".
    static func millisField(_ s: String) -> Double? {
        guard let r = s.range(of: " ms") else { return nil }
        let before = s[..<r.lowerBound]
        var v = ""
        for ch in before.reversed() {
            if ch.isNumber || ch == "." { v.append(ch) } else { break }
        }
        return Double(String(v.reversed()))
    }
}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `just test`
Expected: PASS — all `TraceParserTests` green; the golden trace parses with exactly 2 `prefillSync` events.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/TraceParser.swift Tests/SwiftStarKitTests/TraceParserTests.swift
git commit -m "P6: TraceParser for the --trace channel (compaction + prefill sync)"
```

---

### Task 2: `DiagnosticsLogic` — baseline, current, degradation, cache health (SwiftStarKit)

**Files:**
- Create: `Sources/SwiftStarKit/DiagnosticsLogic.swift`
- Test: `Tests/SwiftStarKitTests/DiagnosticsLogicTests.swift`

**Interfaces:**
- Consumes: `StatusSnapshot` (from `WireEventParser.swift`), `Severity` (from `DialLogic.swift`).
- Produces: `public enum DiagnosticsLogic` with `baselineWindowTokens`, `degradationWarningRatio`, `degradationCriticalRatio`, `prefixCacheHealthyFraction`; `baselineTPS(_: [StatusSnapshot]) -> Double?`; `currentTPS(_: [StatusSnapshot]) -> Double?`; `degradationSeverity(ratio:) -> Severity`; `prefixCacheSeverity(hitFraction:) -> Severity`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/DiagnosticsLogicTests.swift`:

```swift
import Testing
@testable import SwiftStarKit

private func status(_ ctx: Int, _ tps: Double, ts: UInt64 = 0) -> StatusSnapshot {
    StatusSnapshot(ctxUsed: ctx, ctxSize: 150_000, prefillTPS: tps, genTPS: 0, ts: ts)
}

struct DiagnosticsLogicTests {
    @Test func baselineTakesMaxLowContextPrefill() {
        let statuses = [
            status(3_400, 330), status(10_000, 200), status(50_000, 90), status(92_500, 44),
        ]
        #expect(DiagnosticsLogic.baselineTPS(statuses) == 330)
    }

    @Test func baselineIgnoresHighContextAndZeroRate() {
        let statuses = [
            status(3_400, 0), status(20_000, 180), status(92_500, 44),
        ]
        // 3_400 has zero rate; 20_000 is above baselineWindowTokens; so no baseline.
        #expect(DiagnosticsLogic.baselineTPS(statuses) == nil)
    }

    @Test func currentTakesLastNonZeroRate() {
        let statuses = [
            status(3_400, 330), status(50_000, 90), status(92_500, 44), status(92_500, 0),
        ]
        #expect(DiagnosticsLogic.currentTPS(statuses) == 44)
    }

    @Test func degradationSeverityBands() {
        #expect(DiagnosticsLogic.degradationSeverity(ratio: 1.5) == .healthy)
        #expect(DiagnosticsLogic.degradationSeverity(ratio: 2.0) == .warning)
        #expect(DiagnosticsLogic.degradationSeverity(ratio: 3.5) == .critical)
        #expect(DiagnosticsLogic.degradationSeverity(ratio: 7.5) == .critical)
    }

    @Test func prefixCacheSeverityBands() {
        #expect(DiagnosticsLogic.prefixCacheSeverity(hitFraction: 0.98) == .healthy)
        #expect(DiagnosticsLogic.prefixCacheSeverity(hitFraction: 0.50) == .healthy)
        #expect(DiagnosticsLogic.prefixCacheSeverity(hitFraction: 0.49) == .warning)
    }
}
```

- [ ] **Step 2: Run to verify the failure**

Run: `just test`
Expected: FAIL — `DiagnosticsLogicTests.swift` does not compile (`DiagnosticsLogic` undefined).

- [ ] **Step 3: Implement `DiagnosticsLogic`**

`Sources/SwiftStarKit/DiagnosticsLogic.swift`:

```swift
import Foundation

/// P6's analyzer constants and pure arithmetic. Named, re-anchorable values,
/// following the same discipline as `DialLogic`'s thresholds: re-anchor against
/// fresh measurement before trusting far from where they were measured.
public enum DiagnosticsLogic {
    /// `ctx_used` ceiling for "early / small context" baseline samples.
    public static let baselineWindowTokens = 8_192
    /// Degradation ratio (baseline / current) bands. Critical is deliberately
    /// below the measured ~7x so a real problem is flagged long before it is
    /// catastrophic; the exact ratio still travels in the finding payload.
    public static let degradationWarningRatio = 2.0
    public static let degradationCriticalRatio = 3.5
    /// `cached / prompt` floor for "prefix cache healthy".
    public static let prefixCacheHealthyFraction = 0.5

    /// The session's own early prefill rate: the highest `prefill_tps` among
    /// statuses with `ctx_used <= baselineWindowTokens`. Nil if none qualify.
    public static func baselineTPS(_ statuses: [StatusSnapshot]) -> Double? {
        statuses
            .filter { $0.prefillTPS > 0 && $0.ctxUsed <= baselineWindowTokens }
            .map(\.prefillTPS)
            .max()
    }

    /// The current prefill rate: the last status with `prefill_tps > 0`.
    public static func currentTPS(_ statuses: [StatusSnapshot]) -> Double? {
        statuses.last(where: { $0.prefillTPS > 0 })?.prefillTPS
    }

    public static func degradationSeverity(ratio: Double) -> Severity {
        if ratio >= degradationCriticalRatio { return .critical }
        if ratio >= degradationWarningRatio { return .warning }
        return .healthy
    }

    public static func prefixCacheSeverity(hitFraction: Double) -> Severity {
        hitFraction >= prefixCacheHealthyFraction ? .healthy : .warning
    }
}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/DiagnosticsLogic.swift Tests/SwiftStarKitTests/DiagnosticsLogicTests.swift
git commit -m "P6: DiagnosticsLogic — baseline/current/degradation/cache-health arithmetic"
```

---

### Task 3: `Finding`, `CompactionVerdict`, and `DeterministicPhraser` (SwiftStarKit)

**Files:**
- Create: `Sources/SwiftStarKit/Finding.swift`
- Modify: `Sources/SwiftStarKit/DialLogic.swift` (add `Hashable` + `label` to `Severity`)
- Test: `Tests/SwiftStarKitTests/FindingTests.swift`

**Interfaces:**
- Produces:
  - `public struct CompactionObserved: Equatable, Hashable, Sendable { oldTokens, newTokens, tailTokens; init(oldTokens:newTokens:tailTokens:) }`
  - `public enum CompactionVerdict: Equatable, Hashable, Sendable { case willNotFixRate(cacheHitFraction: Double); case mayRecoverCache(cacheHitFraction: Double); case unknown }`
  - `public enum Finding: Equatable, Hashable, Sendable { case contextPosition(ctxUsed: Int, ctxSize: Int, severity: Severity); case prefillThroughput(currentTPS: Double); case baselineDrift(baselineTPS: Double, currentTPS: Double, ratio: Double, severity: Severity); case prefixCache(hitFraction: Double, severity: Severity); case compactionObserved(CompactionObserved); case compactionVerdict(verdict: CompactionVerdict, severity: Severity) }`
  - `public struct DeterministicPhraser: Sendable { public init(); public func phrase(_ finding: Finding) -> String }`

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/FindingTests.swift`:

```swift
import Testing
@testable import SwiftStarKit

struct FindingTests {
    private let phraser = DeterministicPhraser()

    @Test func contextPositionPhraseCarriesNumbers() {
        let f = Finding.contextPosition(ctxUsed: 92_500, ctxSize: 150_000, severity: .critical)
        let s = phraser.phrase(f)
        #expect(s.contains("92,500") == false)  // Swift Int interpolation does not group digits
        #expect(s.contains("92500"))
        #expect(s.contains("150000"))
        #expect(s.contains("critical"))
    }

    @Test func baselineDriftPhraseCarriesRatio() {
        let f = Finding.baselineDrift(baselineTPS: 330, currentTPS: 44, ratio: 7.5, severity: .critical)
        let s = phraser.phrase(f)
        #expect(s.contains("44"))
        #expect(s.contains("330"))
        #expect(s.contains("7.5"))
    }

    @Test func willNotFixRatePhraseSaysCacheIsHealthy() {
        let f = Finding.compactionVerdict(verdict: .willNotFixRate(cacheHitFraction: 0.953), severity: .critical)
        let s = phraser.phrase(f)
        #expect(s.contains("already healthy"))
        #expect(s.contains("95%"))
    }

    @Test func mayRecoverCachePhraseSaysCacheMissing() {
        let f = Finding.compactionVerdict(verdict: .mayRecoverCache(cacheHitFraction: 0.1), severity: .warning)
        let s = phraser.phrase(f)
        #expect(s.contains("missing"))
        #expect(s.contains("10%"))
    }

    @Test func unknownVerdictPhraseAdmitsIt() {
        let f = Finding.compactionVerdict(verdict: .unknown, severity: .warning)
        let s = phraser.phrase(f)
        #expect(s.contains("unknown"))
    }

    @Test func severityHasLabel() {
        #expect(Severity.healthy.label == "healthy")
        #expect(Severity.warning.label == "warning")
        #expect(Severity.critical.label == "critical")
    }

    @Test func findingIsHashableForList() {
        let a = Finding.baselineDrift(baselineTPS: 330, currentTPS: 44, ratio: 7.5, severity: .critical)
        let b = Finding.baselineDrift(baselineTPS: 330, currentTPS: 44, ratio: 7.5, severity: .critical)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
```

- [ ] **Step 2: Run to verify the failure**

Run: `just test`
Expected: FAIL — `FindingTests.swift` does not compile (`Finding`, `CompactionVerdict`, `DeterministicPhraser` undefined).

- [ ] **Step 3: Modify `Severity` in `DialLogic.swift`**

Change the declaration from:

```swift
public enum Severity: Equatable, Sendable {
    case healthy
    case warning
    case critical
}
```

to:

```swift
public enum Severity: Equatable, Hashable, Sendable {
    case healthy
    case warning
    case critical

    /// Deterministic label for phrasing (Kit, not view, concern).
    public var label: String {
        switch self {
        case .healthy: return "healthy"
        case .warning: return "warning"
        case .critical: return "critical"
        }
    }
}
```

- [ ] **Step 4: Implement `Finding` + `CompactionVerdict` + `DeterministicPhraser`**

`Sources/SwiftStarKit/Finding.swift`:

```swift
import Foundation

/// One compaction's rebuild facts, from a trace `compacted` line.
public struct CompactionObserved: Equatable, Hashable, Sendable {
    public let oldTokens: Int
    public let newTokens: Int
    public let tailTokens: Int
    public init(oldTokens: Int, newTokens: Int, tailTokens: Int) {
        self.oldTokens = oldTokens
        self.newTokens = newTokens
        self.tailTokens = tailTokens
    }
}

/// The deterministic answer to "would compaction help". The whole point is to
/// tell apart "size is the cause, cache is fine" from "cache is broken, rebuild
/// it" — the measurement says the former is what actually happens.
public enum CompactionVerdict: Equatable, Hashable, Sendable {
    case willNotFixRate(cacheHitFraction: Double)
    case mayRecoverCache(cacheHitFraction: Double)
    case unknown
}

/// A machine-computed diagnostic finding. Strongly typed so tests assert on
/// values, never on rendered prose (binding rule 3). `DeterministicPhraser`
/// turns one of these into a sentence; a model phraser can replace it later.
public enum Finding: Equatable, Hashable, Sendable {
    case contextPosition(ctxUsed: Int, ctxSize: Int, severity: Severity)
    case prefillThroughput(currentTPS: Double)
    case baselineDrift(baselineTPS: Double, currentTPS: Double, ratio: Double, severity: Severity)
    case prefixCache(hitFraction: Double, severity: Severity)
    case compactionObserved(CompactionObserved)
    case compactionVerdict(verdict: CompactionVerdict, severity: Severity)
}

/// Renders a `Finding` to a sentence built only from the finding's own numbers.
/// This is the shipped renderer; a model phraser implements the same shape later.
public struct DeterministicPhraser: Sendable {
    public init() {}

    public func phrase(_ finding: Finding) -> String {
        switch finding {
        case .contextPosition(let ctxUsed, let ctxSize, let severity):
            return "Context is at \(ctxUsed) of \(ctxSize) tokens (\(severity.label))."
        case .prefillThroughput(let tps):
            return "Current prefill throughput is \(Self.rate(tps)) tok/s."
        case .baselineDrift(let baseline, let current, let ratio, let severity):
            return "Prefill is \(Self.rate(current)) tok/s — \(Self.ratio(ratio))× slower than this session's own baseline of \(Self.rate(baseline)) tok/s at small context (\(severity.label))."
        case .prefixCache(let hit, let severity):
            return "Prefix cache is \(Self.percent(hit)) hit (\(severity.label))."
        case .compactionObserved(let c):
            return "Compaction rebuilt context from \(c.oldTokens) to \(c.newTokens) tokens (tail \(c.tailTokens))."
        case .compactionVerdict(let verdict, let severity):
            switch verdict {
            case .willNotFixRate(let hit):
                return "Compaction will not fix this — the prefix cache is already healthy (\(Self.percent(hit)) hit); the slowdown is context size (\(severity.label))."
            case .mayRecoverCache(let hit):
                return "Compaction may help — the prefix cache is missing (\(Self.percent(hit)) hit); a rebuild could recover it (\(severity.label))."
            case .unknown:
                return "Whether compaction would help is unknown — no prefix-cache data in the trace (\(severity.label))."
            }
        }
    }

    static func rate(_ v: Double) -> String { String(format: "%.0f", v) }
    static func ratio(_ v: Double) -> String { String(format: "%.1f", v) }
    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}
```

- [ ] **Step 5: Run to verify the tests pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/Finding.swift Sources/SwiftStarKit/DialLogic.swift Tests/SwiftStarKitTests/FindingTests.swift
git commit -m "P6: Finding model + CompactionVerdict + deterministic phraser"
```

---

### Task 4: `DiagnosticsAnalyzer` (SwiftStarKit)

**Files:**
- Create: `Sources/SwiftStarKit/DiagnosticsAnalyzer.swift`
- Test: `Tests/SwiftStarKitTests/DiagnosticsAnalyzerTests.swift`

**Interfaces:**
- Consumes: `WireEvent`, `TraceEvent`, `Severity`, `DialLogic`, `DiagnosticsLogic`, `Finding`, `CompactionVerdict`, `CompactionObserved`.
- Produces: `public struct DiagnosticsAnalyzer: Sendable { public init(); public func analyze(events: [WireEvent], trace: [TraceEvent]) -> [Finding] }`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/DiagnosticsAnalyzerTests.swift`:

```swift
import Testing
@testable import SwiftStarKit

private func status(_ ctx: Int, _ tps: Double, ts: UInt64 = 0) -> StatusSnapshot {
    StatusSnapshot(ctxUsed: ctx, ctxSize: 150_000, prefillTPS: tps, genTPS: 0, ts: ts)
}

private func severity(_ f: Finding) -> Severity? {
    switch f {
    case .contextPosition(_, _, let s): return s
    case .prefillThroughput: return .healthy
    case .baselineDrift(_, _, _, let s): return s
    case .prefixCache(_, let s): return s
    case .compactionObserved: return .healthy
    case .compactionVerdict(_, let s): return s
    }
}

struct DiagnosticsAnalyzerTests {
    private let analyzer = DiagnosticsAnalyzer()

    @Test func shallowHealthySessionHasNoCriticalFindings() {
        let events: [WireEvent] = [
            .hello(version: 1, capabilities: ["status", "ready", "ts"]),
            .status(status(958, 300)),
            .status(status(3_400, 330)),
        ]
        let trace: [TraceEvent] = [.prefillSync(prompt: 1_026, cached: 958, suffix: 68, rc: 0, ms: 575.8)]
        let findings = analyzer.analyze(events: events, trace: trace)
        #expect(findings.contains { if case .contextPosition = $0 { true } else { false } })
        #expect(findings.contains { if case .prefillThroughput = $0 { true } else { false } })
        #expect(!findings.contains { if case .baselineDrift = $0 { true } else { false } })
        #expect(!findings.contains { if case .compactionVerdict = $0 { true } else { false } })
        #expect(!findings.contains { (severity($0) ?? .healthy) == .critical })
    }

    @Test func deepDegradedSessionFlagsBaselineDriftAndVerdict() {
        let events: [WireEvent] = [
            .hello(version: 1, capabilities: ["status", "ready", "ts"]),
            .status(status(3_400, 330)),
            .status(status(92_500, 44)),
        ]
        let trace: [TraceEvent] = [.prefillSync(prompt: 1_074, cached: 1_024, suffix: 50, rc: 0, ms: 1_234.5)]
        let findings = analyzer.analyze(events: events, trace: trace)

        // baseline 330, current 44 → ratio 7.5 → critical
        #expect(findings.contains {
            if case .baselineDrift(let b, let c, let r, .critical) = $0 {
                return b == 330 && c == 44 && r > 7.4 && r < 7.6
            }
            return false
        })
        // deep (92_500 >= 37_500) + degraded + cache healthy → willNotFixRate
        #expect(findings.contains {
            if case .compactionVerdict(.willNotFixRate(let hit), .critical) = $0 {
                return hit > 0.9
            }
            return false
        })
        #expect(findings.contains {
            if case .contextPosition(92_500, 150_000, .critical) = $0 { return true }
            return false
        })
    }

    @Test func missingCacheDataGivesUnknownVerdict() {
        let events: [WireEvent] = [
            .hello(version: 1, capabilities: ["status", "ready", "ts"]),
            .status(status(3_400, 330)),
            .status(status(92_500, 44)),
        ]
        let findings = analyzer.analyze(events: events, trace: [])
        #expect(findings.contains {
            if case .compactionVerdict(.unknown, _) = $0 { return true }
            return false
        })
    }

    @Test func lowCacheHitGivesMayRecoverCacheVerdict() {
        let events: [WireEvent] = [
            .hello(version: 1, capabilities: ["status", "ready", "ts"]),
            .status(status(3_400, 330)),
            .status(status(92_500, 44)),
        ]
        let trace: [TraceEvent] = [.prefillSync(prompt: 1_074, cached: 107, suffix: 967, rc: 0, ms: 99.0)]
        let findings = analyzer.analyze(events: events, trace: trace)
        #expect(findings.contains {
            if case .compactionVerdict(.mayRecoverCache(let hit), _) = $0 { return hit < 0.2 }
            return false
        })
    }

    @Test func compactionObservedIsReportedPerEvent() {
        let events: [WireEvent] = [
            .hello(version: 1, capabilities: ["status", "ready", "ts"]),
            .status(status(3_400, 330)),
        ]
        let trace: [TraceEvent] = [
            .compaction(reason: "ctx grew", old: 150_000, new: 45_000, tailStart: 42_000, tail: 3_000),
        ]
        let findings = analyzer.analyze(events: events, trace: trace)
        #expect(findings.contains {
            if case .compactionObserved(let c) = $0 {
                return c.oldTokens == 150_000 && c.newTokens == 45_000 && c.tailTokens == 3_000
            }
            return false
        })
    }
}
```

- [ ] **Step 2: Run to verify the failure**

Run: `just test`
Expected: FAIL — `DiagnosticsAnalyzerTests.swift` does not compile (`DiagnosticsAnalyzer` undefined).

- [ ] **Step 3: Implement `DiagnosticsAnalyzer`**

`Sources/SwiftStarKit/DiagnosticsAnalyzer.swift`:

```swift
import Foundation

/// The deterministic diagnostics engine. Consumes already-parsed wire + trace
/// events (it does not re-read files — the production parsers do that) and emits
/// typed findings. Every rule is a pure function of its inputs.
public struct DiagnosticsAnalyzer: Sendable {
    public init() {}

    public func analyze(events: [WireEvent], trace: [TraceEvent]) -> [Finding] {
        let statuses = statusSnapshots(events)
        let baseline = DiagnosticsLogic.baselineTPS(statuses)
        let current = DiagnosticsLogic.currentTPS(statuses)
        let ratio: Double? = {
            guard let baseline, let current, baseline > 0, current > 0 else { return nil }
            return baseline / current
        }()

        var findings: [Finding] = []

        // 1. Where you are in your context (absolute anchoring).
        if let last = statuses.last {
            findings.append(.contextPosition(
                ctxUsed: last.ctxUsed,
                ctxSize: last.ctxSize,
                severity: DialLogic.contextSeverity(ctxUsed: last.ctxUsed)
            ))
        }

        // 2. Current prefill throughput.
        if let current {
            findings.append(.prefillThroughput(currentTPS: current))
        }

        // 3. How far off this session's own baseline.
        if let baseline, let current, let ratio {
            let severity = DiagnosticsLogic.degradationSeverity(ratio: ratio)
            if severity != .healthy {
                findings.append(.baselineDrift(
                    baselineTPS: baseline, currentTPS: current, ratio: ratio, severity: severity))
            }
        }

        // 4. Prefix-cache health (most recent prefill sync).
        if let hit = latestCacheHitFraction(trace) {
            findings.append(.prefixCache(
                hitFraction: hit,
                severity: DiagnosticsLogic.prefixCacheSeverity(hitFraction: hit)))
        }

        // 5. Compactions observed.
        for event in trace {
            if case .compaction(_, let old, let new, _, let tail) = event {
                findings.append(.compactionObserved(
                    CompactionObserved(oldTokens: old, newTokens: new, tailTokens: tail)))
            }
        }

        // 6. Would compaction help (deep AND degraded).
        if let last = statuses.last, let ratio {
            let deep = last.ctxUsed >= DialLogic.contextWarningTokens
            let degraded = ratio >= DiagnosticsLogic.degradationWarningRatio
            if deep && degraded {
                let severity = DiagnosticsLogic.degradationSeverity(ratio: ratio)
                let verdict: CompactionVerdict
                if let hit = latestCacheHitFraction(trace) {
                    verdict = hit >= DiagnosticsLogic.prefixCacheHealthyFraction
                        ? .willNotFixRate(cacheHitFraction: hit)
                        : .mayRecoverCache(cacheHitFraction: hit)
                } else {
                    verdict = .unknown
                }
                findings.append(.compactionVerdict(verdict: verdict, severity: severity))
            }
        }

        return findings
    }

    private func statusSnapshots(_ events: [WireEvent]) -> [StatusSnapshot] {
        events.compactMap { event in
            if case .status(let s) = event { return s }
            return nil
        }
    }

    private func latestCacheHitFraction(_ trace: [TraceEvent]) -> Double? {
        let syncs: [(prompt: Int, cached: Int)] = trace.compactMap {
            if case .prefillSync(let prompt, let cached, _, _, _) = $0, prompt > 0 {
                return (prompt, cached)
            }
            return nil
        }
        guard let last = syncs.last else { return nil }
        return Double(last.cached) / Double(last.prompt)
    }
}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/DiagnosticsAnalyzer.swift Tests/SwiftStarKitTests/DiagnosticsAnalyzerTests.swift
git commit -m "P6: DiagnosticsAnalyzer — wire + trace events to typed findings"
```

---

### Task 5: Evidence floor — synthetic pathological fixture + end-to-end tests

**Files:**
- Create: `fixtures/diagnostics/pathological.ndjson`
- Create: `fixtures/diagnostics/pathological.trace`
- Create: `fixtures/diagnostics/provenance.md`
- Create: `Tests/SwiftStarKitTests/DiagnosticsEvidenceFloorTests.swift`

**Interfaces:**
- Consumes: `WireEventParser`, `TraceParser`, `DiagnosticsAnalyzer`, `Finding`.
- Produces: the committed synthetic fixture pair, and two evidence-floor tests naming each fixture.

- [ ] **Step 1: Create the synthetic pathological fixture (labeled, cited)**

`fixtures/diagnostics/pathological.ndjson` (a handshake + statuses reproducing the measured curve, ending deep and slow):

```json
{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":0}
{"t":"status","state":"prefill","prefill_done":1024,"prefill_total":1024,"prefill_tps":330.0,"generated":0,"gen_tps":0.0,"ctx_used":3400,"ctx_size":150000,"power":100,"error":"","ts":1000000}
{"t":"status","state":"prefill","prefill_done":20700,"prefill_total":20700,"prefill_tps":165.0,"generated":0,"gen_tps":0.0,"ctx_used":20700,"ctx_size":150000,"power":100,"error":"","ts":2000000}
{"t":"status","state":"prefill","prefill_done":56900,"prefill_total":56900,"prefill_tps":66.0,"generated":0,"gen_tps":0.0,"ctx_used":56900,"ctx_size":150000,"power":100,"error":"","ts":3000000}
{"t":"status","state":"prefill","prefill_done":92500,"prefill_total":92500,"prefill_tps":44.0,"generated":0,"gen_tps":0.0,"ctx_used":92500,"ctx_size":150000,"power":100,"error":"","ts":4000000}
```

`fixtures/diagnostics/pathological.trace` (one prefill-sync with a healthy cache hit — the canonical "cache is fine, size is the problem" case):

```
2026-08-22 14:41:12.735 prefill sync done tool_round=0 prompt=1074 cached=1024 suffix=50 rc=0 1234.500 ms
```

`fixtures/diagnostics/provenance.md`:

```markdown
# `pathological` — synthetic diagnostic fixture (NOT a verbatim capture)

**Synthetic.** This fixture was hand-written to exercise the P6 analyzer's
decision logic, not captured from the real engine. It is typed test input to a
pure decision function (like the synthetic sequences in `DialLogicTests`), not a
fake engine binary — the "fakes are generated from captures" rule is about fake
*binaries* that simulate the wire, not about unit-test inputs to pure functions.

The `status` sequence reproduces the measured prefill curve from
`docs/harvest/telemetry-findings.md` (≈330 tok/s at `ctx_used` 3,400 down to
≈44 tok/s at 92,500 — the ~7x degradation). The trace's single `prefill sync
done` line reports a healthy prefix cache (1024/1074 ≈ 95%), so the analyzer's
"would compaction help" finding must answer `willNotFixRate`: the slowdown is
context size, not cache misses.
```

- [ ] **Step 2: Write the evidence-floor tests**

`Tests/SwiftStarKitTests/DiagnosticsEvidenceFloorTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct DiagnosticsEvidenceFloorTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    private static func wireEvents(_ dir: String, _ file: String) -> [WireEvent] {
        let url = repoRoot.appendingPathComponent("fixtures/\(dir)/\(file)")
        let text = try! String(contentsOf: url, encoding: .utf8)
        var parser = WireEventParser()
        var events: [WireEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = parser.feed(s) { events.append(e) }
        }
        return events
    }

    private static func traceEvents(_ dir: String, _ file: String) -> [TraceEvent] {
        let url = repoRoot.appendingPathComponent("fixtures/\(dir)/\(file)")
        let text = try! String(contentsOf: url, encoding: .utf8)
        var parser = TraceParser()
        var events: [TraceEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = parser.feed(s) { events.append(e) }
        }
        return events
    }

    private static func criticalFindings(_ findings: [Finding]) -> [Finding] {
        findings.filter {
            switch $0 {
            case .contextPosition(_, _, let s): return s == .critical
            case .prefillThroughput: return false
            case .baselineDrift(_, _, _, let s): return s == .critical
            case .prefixCache(_, let s): return s == .critical
            case .compactionObserved: return false
            case .compactionVerdict(_, let s): return s == .critical
            }
        }
    }

    @Test func acceptsKnownGoodGoldenCapture() {
        let analyzer = DiagnosticsAnalyzer()
        let events = Self.wireEvents("agent", "golden.ndjson")
        let trace = Self.traceEvents("agent", "golden.trace")
        let findings = analyzer.analyze(events: events, trace: trace)

        // The golden capture is two shallow, healthy turns: no critical findings,
        // no baseline drift, no compaction verdict.
        #expect(Self.criticalFindings(findings).isEmpty)
        #expect(!findings.contains { if case .baselineDrift = $0 { true } else { false } })
        #expect(!findings.contains { if case .compactionVerdict = $0 { true } else { false } })
        // Prefix cache IS healthy and reported.
        #expect(findings.contains { if case .prefixCache(let hit, .healthy) = $0 { return hit > 0.9 }; return false })
    }

    @Test func rejectsKnownBrokenPathologicalFixture() {
        let analyzer = DiagnosticsAnalyzer()
        let events = Self.wireEvents("diagnostics", "pathological.ndjson")
        let trace = Self.traceEvents("diagnostics", "pathological.trace")
        let findings = analyzer.analyze(events: events, trace: trace)

        #expect(findings.contains { if case .contextPosition(92_500, 150_000, .critical) = $0 { true } else { false } })
        #expect(findings.contains { if case .baselineDrift(330, 44, _, .critical) = $0 { true } else { false } })
        #expect(findings.contains { if case .compactionVerdict(.willNotFixRate(let hit), .critical) = $0 { hit > 0.9 } else { false } })
    }
}
```

- [ ] **Step 3: Run to verify the tests pass**

Run: `just test`
Expected: PASS. (Both evidence-floor tests run in the fast tier — fixture reads by path, no subprocess.)

- [ ] **Step 4: Commit**

```bash
git add fixtures/diagnostics Tests/SwiftStarKitTests/DiagnosticsEvidenceFloorTests.swift
git commit -m "P6: evidence floor — accept golden, reject pathological"
```

---

### Task 6: The Diagnostics surface (SwiftStarAppKit + SwiftStar)

**Files:**
- Copy: `fixtures/agent/golden.trace` → `Sources/SwiftStarAppKit/Resources/golden.trace`
- Create: `Sources/SwiftStarAppKit/DiagnosticsFixture.swift`
- Create: `Sources/SwiftStar/DiagnosticsModel.swift`
- Create: `Sources/SwiftStar/DiagnosticsView.swift`
- Modify: `Sources/SwiftStar/MainView.swift` (replace the Diagnostics placeholder, start the model)

**Interfaces:**
- Consumes: `WireEventParser`, `TraceParser`, `DiagnosticsAnalyzer`, `DeterministicPhraser`, `Finding`, `Severity` (all SwiftStarKit); `Bundle.module` resources.
- Produces: `public struct DiagnosticsFixture { public struct Input: Equatable, Sendable { var events: [WireEvent]; var trace: [TraceEvent] }; public static func load() -> Input? }`; `DiagnosticsModel` (`@Observable`, `@MainActor`, `findings`, `isReplayingCapture`, `start()`, `phrase(_:)`); `DiagnosticsView(model:)`.

- [ ] **Step 1: Bundle the trace fixture and add the loader**

```bash
cp fixtures/agent/golden.trace Sources/SwiftStarAppKit/Resources/golden.trace
```

`Sources/SwiftStarAppKit/DiagnosticsFixture.swift`:

```swift
import Foundation
import SwiftStarKit

/// Loads the bundled `golden` capture (wire + trace) and runs it through the
/// production parsers. Used by the Diagnostics tab's fixture replay until P7's
/// live agent migration — the same relationship Metrics' `FixtureReplay` has to
/// its live source.
public struct DiagnosticsFixture: Sendable {
    public struct Input: Equatable, Sendable {
        public var events: [WireEvent]
        public var trace: [TraceEvent]
        public init(events: [WireEvent], trace: [TraceEvent]) {
            self.events = events
            self.trace = trace
        }
    }

    public static func load() -> Input? {
        guard let wireURL = Bundle.module.url(forResource: "golden", withExtension: "ndjson"),
              let traceURL = Bundle.module.url(forResource: "golden", withExtension: "trace"),
              let wireText = try? String(contentsOf: wireURL, encoding: .utf8),
              let traceText = try? String(contentsOf: traceURL, encoding: .utf8) else {
            return nil
        }

        var wireParser = WireEventParser()
        var events: [WireEvent] = []
        for line in wireText.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = wireParser.feed(s) { events.append(e) }
        }

        var traceParser = TraceParser()
        var trace: [TraceEvent] = []
        for line in traceText.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = traceParser.feed(s) { trace.append(e) }
        }

        return Input(events: events, trace: trace)
    }
}
```

- [ ] **Step 2: Add `DiagnosticsModel`**

`Sources/SwiftStar/DiagnosticsModel.swift`:

```swift
import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit

@MainActor
@Observable
final class DiagnosticsModel {
    private(set) var findings: [Finding] = []
    private(set) var isReplayingCapture = false

    private let analyzer = DiagnosticsAnalyzer()
    private let phraser = DeterministicPhraser()

    /// Idempotent: computed once from the bundled capture. Live wiring is P7.
    func start() {
        guard findings.isEmpty else { return }
        isReplayingCapture = true
        if let input = DiagnosticsFixture.load() {
            findings = analyzer.analyze(events: input.events, trace: input.trace)
        }
        isReplayingCapture = false
    }

    func phrase(_ finding: Finding) -> String {
        phraser.phrase(finding)
    }
}
```

- [ ] **Step 3: Add `DiagnosticsView`**

`Sources/SwiftStar/DiagnosticsView.swift`:

```swift
import SwiftUI
import SwiftStarKit

struct DiagnosticsView: View {
    let model: DiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isReplayingCapture {
                Text("Results computed from a recorded capture — not a live engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.findings.isEmpty {
                ContentUnavailableView(
                    "No findings",
                    systemImage: "stethoscope",
                    description: Text("No diagnostic data available."))
            } else {
                List(model.findings, id: \.self) { finding in
                    FindingRow(finding: finding, phrase: model.phrase(finding))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FindingRow: View {
    let finding: Finding
    let phrase: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(phrase).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var severity: Severity {
        switch finding {
        case .contextPosition(_, _, let s): return s
        case .prefillThroughput: return .healthy
        case .baselineDrift(_, _, _, let s): return s
        case .prefixCache(_, let s): return s
        case .compactionObserved: return .healthy
        case .compactionVerdict(_, let s): return s
        }
    }

    private var title: String {
        switch finding {
        case .contextPosition: return "Context"
        case .prefillThroughput: return "Prefill throughput"
        case .baselineDrift: return "Baseline drift"
        case .prefixCache: return "Prefix cache"
        case .compactionObserved: return "Compaction"
        case .compactionVerdict: return "Would compaction help?"
        }
    }

    private var symbol: String {
        switch severity {
        case .healthy: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "xmark.octagon"
        }
    }

    private var color: Color {
        switch severity {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}
```

- [ ] **Step 4: Wire it into `MainView`**

In `Sources/SwiftStar/MainView.swift`, add the model and replace the placeholder:

```swift
struct MainView: View {
    @State private var engineController = EngineController()
    @State private var metricsModel = MetricsModel()
    @State private var diagnosticsModel = DiagnosticsModel()
```

Replace the placeholder tab:

```swift
            PlaceholderView(title: "Diagnostics", phase: "P6")
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
```

with:

```swift
            DiagnosticsView(model: diagnosticsModel)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
```

And in `.onAppear`, start the model alongside Metrics:

```swift
        .onAppear {
            metricsModel.start(enginePid: engineController.runningPid)
            diagnosticsModel.start()
        }
```

- [ ] **Step 5: Build and run the fast tier**

Run: `just test`, then `swift build`
Expected: fast tier green; the app target compiles (the Diagnostics tab is now a real view).

- [ ] **Step 6: Smoke the app (manual)**

Run: `just app` then open `.build/SwiftStar.app`, select the Diagnostics tab.
Expected: a list of findings from the recorded capture, with a "recorded capture — not a live engine" caption; no critical rows (the golden capture is healthy).

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftStarAppKit/Resources/golden.trace Sources/SwiftStarAppKit/DiagnosticsFixture.swift Sources/SwiftStar/DiagnosticsModel.swift Sources/SwiftStar/DiagnosticsView.swift Sources/SwiftStar/MainView.swift
git commit -m "P6: Diagnostics tab — fixture-driven findings surface"
```

---

### Task 7: Close the phase (ROADMAP + concept budget)

**Files:**
- Modify: `ROADMAP.md`

- [ ] **Step 1: Move P6 out of "Now"**

In the "Now" section, replace the P6 paragraph with P7 as the active phase:

```markdown
**Phase P7 — Agent mode.** Next up; not started. Spawn `ds4-agent`, NDJSON
transcript, tool cards, workspace grant, shell toggle, interruptible turns.
```

- [ ] **Step 2: Add the P6 summary to "Prior work"**

Append after the P5 entry:

```markdown
- **P6 — Diagnostics that can't lie (2026-08-22).** `SwiftStarKit` gains
  `TraceParser` (parses the `--trace` channel: `compacted` rebuild stats and both
  `prefill sync done` shapes), `DiagnosticsLogic` (baseline/current prefill
  extraction, degradation and cache-health bands, all re-anchorable constants),
  the typed `Finding`/`CompactionVerdict` model, `DeterministicPhraser` (the
  "compute vs. phrase" seam — a model phraser can replace it later), and
  `DiagnosticsAnalyzer`, which computes the BRIEF's first job deterministically:
  where you are in context, current prefill throughput, drift off your own
  session's baseline, and — deep *and* degraded — whether compaction would help
  (distinguishing "cache healthy → won't fix the rate" from "cache missing → may
  recover"). The Diagnostics tab replaces its placeholder with a fixture-driven
  list of findings. Evidence floor met: the analyzer accepts the real `golden`
  capture and rejects a committed synthetic `pathological` fixture reproducing
  the measured 7x curve. No live engine, no model, no engine patch.
  Spec: [`docs/superpowers/specs/2026-08-22-p6-diagnostics-that-cant-lie-design.md`](docs/superpowers/specs/2026-08-22-p6-diagnostics-that-cant-lie-design.md).
```

- [ ] **Step 3: Update the phase table status**

Change the P6 row's Status from `planned` to `complete (2026-08-22)`.

- [ ] **Step 4: Review the concept budget**

Add definitions after **fixture**:

```markdown
- **finding** (P6) — a machine-computed diagnostic result: a typed value with a
  severity and the computed numbers it reports; phrased by a deterministic
  renderer now, a model later.
- **baseline** (P6) — a session's own early prefill throughput (highest
  `prefill_tps` at `ctx_used ≤ 8,192`), against which later throughput is
  compared; the session measures itself, no external calibration.
- **diagnostic** (P6) — a finding the analyzer computes from a capture, never a
  model's judgment. The model only phrases.
```

No other terms are added; none are retired.

- [ ] **Step 5: Commit**

```bash
git add ROADMAP.md
git commit -m "P6: close — roadmap, concept budget"
```

- [ ] **Step 6: Final verification**

Run: `just test` and `just integration`
Expected: both green. P6 complete.

---

## Self-review notes (run before execution)

- **Spec coverage:** D1 (analyzer + Finding + phraser seam) → Tasks 3–4; D2 (the six findings) → Task 4; D3 (TraceParser) → Task 1; D4 (constants) → Task 2; D5 (surface) → Task 6; D6 (evidence floor) → Task 5; D7 (scope) is a constraint list, enforced across tasks (no live engine, no model, no engine patch — none of the tasks spawn a process or call a model).
- **Type consistency:** `TraceEvent` cases match between Task 1 (definition), Task 4 (consumption), and the evidence floor (Task 5). `Finding` cases match between Task 3 (definition), Task 4 (emission), Task 5 (assertions), and Task 6 (view). `DiagnosticsLogic` names match Task 2 (definition) and Task 4 (use). `Severity.label` is added in Task 3 and used by the phraser in the same task; `Hashable` is added to `Severity` in Task 3 and relied on by `List(…, id: \.self)` in Task 6.
- **No placeholders:** every step carries real code or an exact edit.
