# P4 — It Shows What the Machine Is Doing: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Metrics tab showing absolute `ctx_used`, Prompt/Decode throughput (fixture-replayed until P7), and live memory/GPU/CPU/power of the running `ds4-server` — on fixed-width, jitter-proof readouts.

**Architecture:** Pure logic in `SwiftStarKit`: `WireEventParser` (NDJSON `status`/`ready` → `WireEvent`), `MetricsReducer` (rate ratchet), `DialLogic` (absolute context thresholds, generic memory thresholds, fixed-width formatting, sanitization), and the `MachineSnapshot` data type. `SwiftStarAppKit` owns the OS collectors (`proc_pid_rusage`, `host_processor_info`, `IOAccelerator`, private `IOReport`) and the fixture replay. `SwiftStar` owns the thin `MetricsModel` + `MetricsView`.

**Tech Stack:** Swift 6.3, SwiftPM, swift-testing, Observation, SwiftUI, Darwin/IOKit. Sphinx docs unchanged.

**Spec:** `docs/superpowers/specs/2026-08-22-p4-it-shows-what-the-machine-is-doing-design.md`

## Global Constraints

- Fast tier (`just test`): no model, no network, no subprocess (tripwire-scanned). Kit code uses none.
- Integration tier (`just integration`): real processes + files, env-gated via `SWIFTSTAR_INTEGRATION=1`.
- Binding rules: every new test shown to fail first; no source-text assertions; refusal tests have sibling success tests; fakes are generated from captures, never hand-authored.
- Kit is pure: no SwiftUI/IOKit/Process/network. All OS/IOKit/file-timer work is in `SwiftStarAppKit` or the integration tier.
- Facts cross with citations: collector keys from `~/projects/ds4-control` (facts cross; code does not). Provisional context thresholds are re-anchorable constants.

---

### Task 1: WireEventParser (Kit)

**Files:**
- Create: `Sources/SwiftStarKit/WireEventParser.swift`, `Tests/SwiftStarKitTests/WireEventParserTests.swift`
- Test: `Tests/SwiftStarKitTests/WireEventParserTests.swift`

**Interfaces:**
- Produces: `StatusSnapshot` (struct: `ctxUsed: Int`, `ctxSize: Int`, `prefillTPS: Double`, `genTPS: Double`), `WireEvent` (`.status(StatusSnapshot)`, `.ready(plannedBytes: Int64?)`, `.ignored(String)`), `WireEventParser` (`init()`, `mutating func feed(_ line: String) -> WireEvent?`).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct WireEventParserTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent")
    }

    @Test func statusLineParsesSnapshot() {
        var parser = WireEventParser()
        let line = #"{"t":"status","state":"prefill","prefill_done":2,"prefill_total":142,"prefill_tps":5.8,"generated":0,"gen_tps":0.0,"ctx_used":1100,"ctx_size":32768,"power":100,"error":""}"#
        #expect(parser.feed(line) == .status(StatusSnapshot(ctxUsed: 1100, ctxSize: 32768, prefillTPS: 5.8, genTPS: 0.0)))
    }

    @Test func readyLineParsesPlannedBytes() {
        var parser = WireEventParser()
        let line = #"{"t":"ready","kv_bytes":1686110208,"scratch_bytes":784752,"model_bytes":48257070080,"planned_bytes":49943965040}"#
        #expect(parser.feed(line) == .ready(plannedBytes: 49_943_965_040))
    }

    @Test func bareReadyHasNilBudget() {
        var parser = WireEventParser()
        #expect(parser.feed(#"{"t":"ready"}"#) == .ready(plannedBytes: nil))
    }

    @Test func otherKindsAreIgnoredNotRefused() {
        var parser = WireEventParser()
        for line in [#"{"t":"text","s":"hi"}"#, #"{"t":"think","s":"..."}"#,
                     #"{"t":"tool","phase":"start","idx":0}"#, #"{"t":"queued"}"#] {
            if case .ignored = parser.feed(line) {} else { Issue.record("expected .ignored for \(line)") }
        }
    }

    @Test func malformedLineIsIgnoredNotRefused() {
        var parser = WireEventParser()
        if case .ignored(let payload) = parser.feed("not json") { #expect(payload == "not json") }
        else { Issue.record("expected .ignored") }
    }

    @Test func blankLineIsNil() {
        var parser = WireEventParser()
        #expect(parser.feed("") == nil)
        #expect(parser.feed("   ") == nil)
    }

    @Test func goldenNdjsonParsesWithoutRefusing() throws {
        // Real invariants, not counts: every non-blank fixture line parses to
        // status/ready/ignored, never nil, and both telemetry kinds appear.
        let text = try String(contentsOf: Self.fixturesRoot.appendingPathComponent("golden.ndjson"), encoding: .utf8)
        var parser = WireEventParser()
        var statuses = 0, readies = 0
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let s = String(line)
            if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            switch parser.feed(s) {
            case .status: statuses += 1
            case .ready: readies += 1
            case .ignored: break
            case nil: Issue.record("non-blank line produced nil: \(s)")
            }
        }
        #expect(statuses > 0)
        #expect(readies > 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test` — build error (`WireEventParser` not found).

- [ ] **Step 3: Implement**

```swift
import Foundation

/// One wire-carried metrics sample from a `status` event. `power` (throttle %)
/// and `error` are deliberately not extracted (Settings/supervisor concerns).
public struct StatusSnapshot: Equatable, Sendable {
    public let ctxUsed: Int
    public let ctxSize: Int
    public let prefillTPS: Double
    public let genTPS: Double
}

/// One modelled event from the NDJSON telemetry wire. `.ignored` carries the
/// raw line for anything not modelled — the wire can grow and this parser will
/// not refuse it (binding rule 7: no handshake before P5).
public enum WireEvent: Equatable, Sendable {
    case status(StatusSnapshot)
    case ready(plannedBytes: Int64?)
    case ignored(String)
}

/// Streaming NDJSON telemetry consumer, shaped like `SSEParser`: feed one wire
/// line at a time; it returns an event or nil.
public struct WireEventParser: Sendable {
    public init() {}

    public mutating func feed(_ line: String) -> WireEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let t = object["t"] as? String
        else { return .ignored(trimmed) }

        switch t {
        case "status":
            return .status(StatusSnapshot(
                ctxUsed: (object["ctx_used"] as? NSNumber)?.intValue ?? 0,
                ctxSize: (object["ctx_size"] as? NSNumber)?.intValue ?? 0,
                prefillTPS: (object["prefill_tps"] as? NSNumber)?.doubleValue ?? 0,
                genTPS: (object["gen_tps"] as? NSNumber)?.doubleValue ?? 0
            ))
        case "ready":
            return .ready(plannedBytes: (object["planned_bytes"] as? NSNumber)?.int64Value)
        default:
            return .ignored(trimmed)
        }
    }
}
```

- [ ] **Step 4: Run to verify pass** — `just test` green.

- [ ] **Step 5: Shown-fail** — temporarily change the `case "status":` dispatch to `return .ignored(trimmed)`; `statusLineParsesSnapshot` fails; restore; green.

- [ ] **Step 6: Commit** — `git add Sources/SwiftStarKit/WireEventParser.swift Tests/SwiftStarKitTests/WireEventParserTests.swift && git commit -m "P4: wire telemetry parser (Kit)"`

---

### Task 2: MetricsReducer + rate ratchet (Kit)

**Files:**
- Create: `Sources/SwiftStarKit/MetricsReducer.swift`, `Tests/SwiftStarKitTests/MetricsReducerTests.swift`
- Test: `Tests/SwiftStarKitTests/MetricsReducerTests.swift`

**Interfaces:**
- Consumes: `WireEvent`, `StatusSnapshot` (Task 1).
- Produces: `MetricsState` (`ctxUsed: Int?`, `ctxSize: Int?`, `prefillTPS: Double`, `genTPS: Double`, `memoryBudgetPlannedBytes: Int64?`), `MetricsReducer` (`init()`, `func reduce(_ state: inout MetricsState, _ event: WireEvent)`).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SwiftStarKit

struct MetricsReducerTests {
    @Test func ratchetHoldsLastNonZeroRates() {
        var state = MetricsState()
        var reducer = MetricsReducer()
        reducer.reduce(&state, .status(StatusSnapshot(ctxUsed: 100, ctxSize: 32768, prefillTPS: 5.8, genTPS: 0)))
        #expect(state.prefillTPS == 5.8)
        #expect(state.genTPS == 0)
        // Generation phase: prefill drops to 0, gen becomes non-zero.
        reducer.reduce(&state, .status(StatusSnapshot(ctxUsed: 200, ctxSize: 32768, prefillTPS: 0, genTPS: 12.3)))
        #expect(state.prefillTPS == 5.8)  // ratcheted — does not flicker to 0
        #expect(state.genTPS == 12.3)
        // Idle: both zero — both hold.
        reducer.reduce(&state, .status(StatusSnapshot(ctxUsed: 200, ctxSize: 32768, prefillTPS: 0, genTPS: 0)))
        #expect(state.prefillTPS == 5.8)
        #expect(state.genTPS == 12.3)
    }

    @Test func statusUpdatesContext() {
        var state = MetricsState()
        var reducer = MetricsReducer()
        #expect(state.ctxUsed == nil)
        reducer.reduce(&state, .status(StatusSnapshot(ctxUsed: 958, ctxSize: 32768, prefillTPS: 0, genTPS: 0)))
        #expect(state.ctxUsed == 958)
        #expect(state.ctxSize == 32768)
    }

    @Test func readySetsBudget() {
        var state = MetricsState()
        var reducer = MetricsReducer()
        reducer.reduce(&state, .ready(plannedBytes: 49_943_965_040))
        #expect(state.memoryBudgetPlannedBytes == 49_943_965_040)
    }

    @Test func ignoredIsNoOp() {
        var state = MetricsState()
        var reducer = MetricsReducer()
        reducer.reduce(&state, .ignored("x"))
        #expect(state == MetricsState())
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Folded wire-telemetry state. Ratcheted rates hold their last non-zero value
/// (the wire reports one rate at a time — a wire fact, so it lives here in the
/// model, not in a view).
public struct MetricsState: Equatable, Sendable {
    public var ctxUsed: Int?
    public var ctxSize: Int?
    public var prefillTPS: Double = 0
    public var genTPS: Double = 0
    public var memoryBudgetPlannedBytes: Int64?

    public init() {}
}

public struct MetricsReducer: Sendable {
    public init() {}

    public func reduce(_ state: inout MetricsState, _ event: WireEvent) {
        switch event {
        case .status(let s):
            state.ctxUsed = s.ctxUsed
            state.ctxSize = s.ctxSize
            if s.prefillTPS != 0 { state.prefillTPS = s.prefillTPS }
            if s.genTPS != 0 { state.genTPS = s.genTPS }
        case .ready(let plannedBytes):
            state.memoryBudgetPlannedBytes = plannedBytes
        case .ignored:
            break
        }
    }
}
```

- [ ] **Step 4: Run to verify pass** — green.

- [ ] **Step 5: Shown-fail** — change `if s.prefillTPS != 0 { state.prefillTPS = s.prefillTPS }` to an unconditional `state.prefillTPS = s.prefillTPS`; `ratchetHoldsLastNonZeroRates` fails; restore; green.

- [ ] **Step 6: Commit** — `git commit -m "P4: metrics reducer + rate ratchet (Kit)"`

---

### Task 3: DialLogic + MachineSnapshot (Kit)

**Files:**
- Create: `Sources/SwiftStarKit/DialLogic.swift`, `Tests/SwiftStarKitTests/DialLogicTests.swift`
- Test: `Tests/SwiftStarKitTests/DialLogicTests.swift`

**Interfaces:**
- Produces: `Severity` (`.healthy`, `.warning`, `.critical`), `MachineSnapshot` (struct: `residentBytes: Int64?`, `watts: Double`, `gpuUtilization: Double`, `cpuUtilization: Double`), `DialLogic` (`contextSeverity(ctxUsed:)`, `memorySeverity(residentBytes:plannedBytes:)`, `fixedWidth(_:width:)`, `sanitize(_:)`; constants `contextWarningTokens`, `contextCriticalTokens`, `memoryWarningFraction`, `memoryCriticalFraction`).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SwiftStarKit

struct DialLogicTests {
    @Test func contextThresholdsAreAbsolute() {
        #expect(DialLogic.contextSeverity(ctxUsed: 10_000) == .healthy)
        #expect(DialLogic.contextSeverity(ctxUsed: 37_500) == .warning)
        #expect(DialLogic.contextSeverity(ctxUsed: 74_999) == .warning)
        #expect(DialLogic.contextSeverity(ctxUsed: 75_000) == .critical)
        #expect(DialLogic.contextSeverity(ctxUsed: 92_500) == .critical)  // the measured ~7x point
    }

    @Test func memoryThresholdsAreGeneric() {
        #expect(DialLogic.memorySeverity(residentBytes: 60, plannedBytes: 100) == .healthy)
        #expect(DialLogic.memorySeverity(residentBytes: 70, plannedBytes: 100) == .warning)
        #expect(DialLogic.memorySeverity(residentBytes: 90, plannedBytes: 100) == .critical)
        #expect(DialLogic.memorySeverity(residentBytes: 50, plannedBytes: 0) == .healthy)  // no budget
    }

    @Test func fixedWidthPadsToWidth() {
        #expect(DialLogic.fixedWidth("41.2", width: 8) == "    41.2")
        #expect(DialLogic.fixedWidth("128340", width: 8) == "  128340")
        #expect(DialLogic.fixedWidth("12345678", width: 8) == "12345678")
    }

    @Test func sanitizeClampsGarbage() {
        let raw = MachineSnapshot(residentBytes: -5, watts: .nan, gpuUtilization: -1, cpuUtilization: 99.0)
        let clean = DialLogic.sanitize(raw)
        #expect(clean.residentBytes == 0)
        #expect(clean.watts == 0)
        #expect(clean.gpuUtilization == 0)
        #expect(clean.cpuUtilization == 99.0)  // clean values pass through
    }

    @Test func sanitizePassesThroughCleanValues() {
        let raw = MachineSnapshot(residentBytes: 1024, watts: 0.8, gpuUtilization: 98.0, cpuUtilization: 6.5)
        #expect(DialLogic.sanitize(raw) == raw)
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum Severity: Equatable, Sendable {
    case healthy
    case warning
    case critical
}

/// One live machine sample from the OS collectors. `residentBytes` is nil when
/// no engine pid is supplied (per-process); the other three are system-wide.
public struct MachineSnapshot: Equatable, Sendable {
    public var residentBytes: Int64?
    public var watts: Double
    public var gpuUtilization: Double
    public var cpuUtilization: Double

    public init(residentBytes: Int64?, watts: Double, gpuUtilization: Double, cpuUtilization: Double) {
        self.residentBytes = residentBytes
        self.watts = watts
        self.gpuUtilization = gpuUtilization
        self.cpuUtilization = cpuUtilization
    }
}

/// The harvest's widget learnings, as pure functions. Color mapping is a view
/// concern — views map `Severity` to a color; Kit never does.
public enum DialLogic {
    // Provisional, absolute-anchored at the measured 150,000 everyday setting
    // (telemetry-findings: ~7x degradation at ~92,500 ctx). Re-anchor before
    // trusting on other hardware — keep these as named constants for that.
    public static let contextWarningTokens = 37_500
    public static let contextCriticalTokens = 75_000
    public static let memoryWarningFraction = 0.70
    public static let memoryCriticalFraction = 0.90

    /// Absolute context anchoring (learning #1): curve-shaped on tokens, never
    /// a fraction of ctx_size.
    public static func contextSeverity(ctxUsed: Int) -> Severity {
        if ctxUsed >= contextCriticalTokens { return .critical }
        if ctxUsed >= contextWarningTokens { return .warning }
        return .healthy
    }

    /// Generic memory thresholds (learning #5) — deliberately not the context
    /// curve.
    public static func memorySeverity(residentBytes: Int64, plannedBytes: Int64) -> Severity {
        guard plannedBytes > 0, residentBytes >= 0 else { return .healthy }
        let fraction = Double(residentBytes) / Double(plannedBytes)
        if fraction >= memoryCriticalFraction { return .critical }
        if fraction >= memoryWarningFraction { return .warning }
        return .healthy
    }

    /// Fixed-width field (learning #2): pad so value changes don't shift the
    /// surrounding line.
    public static func fixedWidth(_ text: String, width: Int) -> String {
        if text.count >= width { return text }
        return String(repeating: " ", count: width - text.count) + text
    }

    /// Private-API hardware reads can return garbage; the surface never shows
    /// it. Negative -> 0, NaN -> 0, clean values pass through.
    public static func sanitize(_ raw: MachineSnapshot) -> MachineSnapshot {
        func clamp(_ v: Double) -> Double { v.isNaN || v < 0 ? 0 : v }
        let resident: Int64?
        if let r = raw.residentBytes, r < 0 { resident = 0 } else { resident = raw.residentBytes }
        return MachineSnapshot(
            residentBytes: resident,
            watts: clamp(raw.watts),
            gpuUtilization: clamp(raw.gpuUtilization),
            cpuUtilization: clamp(raw.cpuUtilization)
        )
    }
}
```

- [ ] **Step 4: Run to verify pass** — green.

- [ ] **Step 5: Shown-fail** — flip `contextSeverity`'s `>= contextWarningTokens` to `>= contextCriticalTokens` (so 37,500 reads healthy); `contextThresholdsAreAbsolute` fails; restore; green.

- [ ] **Step 6: Commit** — `git commit -m "P4: dial logic + machine snapshot (Kit)"`

---

### Task 4: ProcessStatsCollector + IOReport power (AppKit)

**Files:**
- Create: `Sources/SwiftStarAppKit/ProcessStatsCollector.swift`, `Sources/SwiftStarAppKit/IOReportPower.swift`, `Tests/SwiftStarIntegrationTests/ProcessStatsCollectorTests.swift`
- Test: `Tests/SwiftStarIntegrationTests/ProcessStatsCollectorTests.swift`

**Interfaces:**
- Consumes: `MachineSnapshot`, `DialLogic.sanitize` (Task 3).
- Produces: `ProcessStatsCollector` (`init()`, `func collect(pid: pid_t?) -> MachineSnapshot` — sanitized).

**Facts (cited, not copied):** footprint via `proc_pid_rusage` → `ri_phys_footprint`; CPU% via `host_processor_info` tick delta; GPU% via `IOServiceMatching("IOAccelerator")` → `PerformanceStatistics` → `"GPU Activity(%)"` (fallbacks `"Device Utilization %"`, `"gpuActivity"`); watts via private `IOReport` group `"Energy Model"`, channels `"GPU Energy"`/`*"CPU Energy"`/`"ANE"` prefix, units `mJ`/`uJ`/`nJ`. Sources: `~/projects/ds4-control` (PowerCollector/GPUCollector/CPUCollector/IOReportBridge) and vladkens/macmon (MIT). **This task is the one discovery-driven risk: the IOReport piece may need compile/run iteration against real hardware; the smoke test below is the gate.**

- [ ] **Step 1: Write the collector**

```swift
import Foundation
import Darwin
import IOKit
import SwiftStarKit

final class ProcessStatsCollector {
    private var previousCPUTicks: [UInt64]?

    /// Returns a sanitized snapshot. `pid` nil → residentBytes nil (per-process);
    /// watts/GPU/CPU are system-wide and always collected.
    func collect(pid: pid_t?) -> MachineSnapshot {
        DialLogic.sanitize(MachineSnapshot(
            residentBytes: pid.flatMap(residentBytes(pid:)),
            watts: IOReportPower.totalWatts(),
            gpuUtilization: gpuUtilization(),
            cpuUtilization: cpuUtilization()
        ))
    }

    // MARK: memory — proc_pid_rusage, ri_phys_footprint (bytes)

    private func residentBytes(pid: pid_t) -> Int64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return Int64(info.ri_phys_footprint)
    }

    // MARK: CPU — host_processor_info tick delta

    private func cpuUtilization() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &cpuInfoCount) == KERN_SUCCESS,
              let info = cpuInfo else { return 0 }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let stateCount = Int(CPU_STATE_MAX)
        var current = [UInt64](repeating: 0, count: Int(numCPUs) * stateCount)
        for core in 0..<Int(numCPUs) {
            let base = core * stateCount
            let ib = Int32(core) * CPU_STATE_MAX
            current[base + 0] = UInt64(info[Int(ib + CPU_STATE_USER)])
            current[base + 1] = UInt64(info[Int(ib + CPU_STATE_SYSTEM)])
            current[base + 2] = UInt64(info[Int(ib + CPU_STATE_IDLE)])
            current[base + 3] = UInt64(info[Int(ib + CPU_STATE_NICE)])
        }
        defer { previousCPUTicks = current }
        guard let prev = previousCPUTicks, prev.count == current.count else { return 0 }

        var busy: UInt64 = 0, idle: UInt64 = 0
        for core in 0..<Int(numCPUs) {
            let base = core * stateCount
            busy += (current[base] &- prev[base]) + (current[base + 1] &- prev[base + 1]) + (current[base + 3] &- prev[base + 3])
            idle += current[base + 2] &- prev[base + 2]
        }
        let total = busy + idle
        return total > 0 ? Double(busy) / Double(total) * 100.0 : 0
    }

    // MARK: GPU — IOAccelerator registry, PerformanceStatistics

    private func gpuUtilization() -> Double {
        guard let match = IOServiceMatching("IOAccelerator") else { return 0 }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var utilization = 0.0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let perf = dict["PerformanceStatistics"] as? [String: Any] {
                for key in ["GPU Activity(%)", "Device Utilization %", "gpuActivity"] {
                    if let v = (perf[key] as? NSNumber)?.doubleValue, v > 0 { utilization = v; break }
                }
                if utilization > 0 { IOObjectRelease(service); break }
            }
            service = IOIteratorNext(iterator)
        }
        return utilization
    }
}
```

- [ ] **Step 2: Write the IOReport power bridge** (`Sources/SwiftStarAppKit/IOReportPower.swift`)

```swift
import Foundation
import IOKit
import CoreFoundation

// Private IOReport FFI for system power (watts). Approach and channel keys
// from vladkens/macmon (MIT) via ds4-control's PowerCollector/IOReportBridge
// (facts cross with citation; this implementation is written fresh). Apple
// Silicon only — Intel returns 0.

@_silgen_name("IOReportCopyChannelsInGroup")
private func IOReportCopyChannelsInGroup(_ group: OpaquePointer?, _ subgroup: OpaquePointer?, _ c: UInt64, _ d: UInt64, _ e: UInt64) -> OpaquePointer?
@_silgen_name("IOReportMergeChannels")
private func IOReportMergeChannels(_ a: OpaquePointer, _ b: OpaquePointer, _ nilArg: OpaquePointer?)
@_silgen_name("IOReportCreateSubscription")
private func IOReportCreateSubscription(_ a: UnsafeRawPointer?, _ chan: OpaquePointer, _ outChan: UnsafeMutablePointer<OpaquePointer?>, _ d: UInt64, _ e: OpaquePointer?) -> OpaquePointer?
@_silgen_name("IOReportCreateSamples")
private func IOReportCreateSamples(_ subs: OpaquePointer, _ chan: OpaquePointer, _ c: OpaquePointer?) -> OpaquePointer?
@_silgen_name("IOReportCreateSamplesDelta")
private func IOReportCreateSamplesDelta(_ a: OpaquePointer, _ b: OpaquePointer, _ c: OpaquePointer?) -> OpaquePointer?
@_silgen_name("IOReportChannelGetChannelName")
private func IOReportChannelGetChannelName(_ a: OpaquePointer) -> OpaquePointer?
@_silgen_name("IOReportChannelGetUnitLabel")
private func IOReportChannelGetUnitLabel(_ a: OpaquePointer) -> OpaquePointer?
@_silgen_name("IOReportSimpleGetIntegerValue")
private func IOReportSimpleGetIntegerValue(_ a: OpaquePointer, _ b: Int32) -> Int64

enum IOReportPower {
    /// Total system power in watts, sampled over `windowMs`. Blocks for
    /// `windowMs` while sampling. Returns 0 on Intel or any failure.
    static func totalWatts(windowMs: UInt32 = 100) -> Double {
        let group = "Energy Model" as CFString
        guard let chanPtr = IOReportCopyChannelsInGroup(
            OpaquePointer(Unmanaged.passUnretained(group).toOpaque()), nil, 0, 0, 0
        ) else { return 0 }
        var subscribed: OpaquePointer?
        guard let subs = IOReportCreateSubscription(nil, chanPtr, &subscribed, 0, nil) else {
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(chanPtr)).release()
            return 0
        }
        defer {
            // Channel dict is +1 retained; the subscription has no public
            // release and is effectively permanent for the process lifetime.
            Unmanaged<CFMutableDictionary>.fromOpaque(UnsafeRawPointer(chanPtr)).release()
        }
        guard let s1 = IOReportCreateSamples(subs, chanPtr, nil) else { return 0 }
        Thread.sleep(forTimeInterval: Double(windowMs) / 1000.0)
        guard let s2 = IOReportCreateSamples(subs, chanPtr, nil) else {
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(s1)).release()
            return 0
        }
        guard let delta = IOReportCreateSamplesDelta(s1, s2, nil) else {
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(s1)).release()
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(s2)).release()
            return 0
        }
        defer {
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(s1)).release()
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(s2)).release()
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(delta)).release()
        }
        return sumWatts(delta: delta, elapsedMs: Double(windowMs))
    }

    private static func sumWatts(delta: OpaquePointer, elapsedMs: Double) -> Double {
        let deltaCF = Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(delta)).takeUnretainedValue()
        guard let arrayPtr = CFDictionaryGetValue(deltaCF, Unmanaged.passUnretained("IOReportChannels" as CFString).toOpaque()) else { return 0 }
        let array = Unmanaged<CFArray>.fromOpaque(arrayPtr).takeUnretainedValue()
        var total = 0.0
        for i in 0..<CFArrayGetCount(array) {
            guard let itemPtr = CFArrayGetValueAtIndex(array, i) else { continue }
            let cfPtr = OpaquePointer(itemPtr)
            let channel = cfString(IOReportChannelGetChannelName(cfPtr))
            guard isPowerChannel(channel) else { continue }
            let unit = cfString(IOReportChannelGetUnitLabel(cfPtr)).trimmingCharacters(in: .whitespacesAndNewlines)
            let perSecond = Double(IOReportSimpleGetIntegerValue(cfPtr, 0)) / (elapsedMs / 1000.0)
            switch unit {
            case "mJ": total += perSecond / 1e3
            case "uJ": total += perSecond / 1e6
            case "nJ": total += perSecond / 1e9
            default: break
            }
        }
        return total
    }

    private static func isPowerChannel(_ channel: String) -> Bool {
        channel == "GPU Energy" || channel.hasSuffix("CPU Energy") || channel.hasPrefix("ANE")
    }

    private static func cfString(_ p: OpaquePointer?) -> String {
        guard let p else { return "" }
        return Unmanaged<CFString>.fromOpaque(UnsafeRawPointer(p)).takeUnretainedValue() as String
    }
}
```

- [ ] **Step 3: Write the integration smoke test**

```swift
import Testing
import Foundation
@testable import SwiftStarAppKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct ProcessStatsCollectorTests {
    @Test func collectReturnsSanitizedSnapshot() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["2"]
        try process.run()
        defer { process.terminate() }

        let collector = ProcessStatsCollector()
        let snap = collector.collect(pid: process.processIdentifier)
        #expect(snap.residentBytes != nil)
        #expect((snap.residentBytes ?? 0) > 0)
        #expect(snap.watts >= 0 && snap.watts.isFinite)
        #expect(snap.gpuUtilization >= 0 && snap.gpuUtilization <= 100)
        #expect(snap.cpuUtilization >= 0 && snap.cpuUtilization <= 100)
    }

    @Test func collectWithoutPidReturnsNilResident() {
        let collector = ProcessStatsCollector()
        let snap = collector.collect(pid: nil)
        #expect(snap.residentBytes == nil)
        #expect(snap.watts >= 0 && snap.watts.isFinite)
    }
}
```

- [ ] **Step 4: Run to verify pass** — `just integration` green (the IOReport part returns finite watts on Apple Silicon; if `totalWatts()` returns 0 due to a key mismatch, that is a *real* finding to fix, not a test to weaken — the smoke asserts finiteness, not a non-zero floor).

- [ ] **Step 5: Shown-fail** — in `collect`, remove the `DialLogic.sanitize` wrapper and return the raw snapshot; a unit-style check of `collect(pid:)` for a negative-injection isn't possible (hardware is non-negative), so instead break the CPU delta path: change `busy += ...` to `busy = 0` — the smoke still passes (CPU can legitimately be 0), so the meaningful shown-fail for this task is `DialLogicTests.sanitizeClampsGarbage` from Task 3. Record that cross-reference; no local break needed.

- [ ] **Step 6: Commit** — `git commit -m "P4: OS collectors — memory, CPU, GPU, IOReport power (AppKit)"`

---

### Task 5: FixtureReplay + bundled fixture (AppKit)

**Files:**
- Modify: `Package.swift` (add `resources: [.process("Resources")]` to the `SwiftStarAppKit` target)
- Create: `Sources/SwiftStarAppKit/Resources/golden.ndjson` (copy of `fixtures/agent/golden.ndjson`), `Sources/SwiftStarAppKit/FixtureReplay.swift`, `Tests/SwiftStarIntegrationTests/FixtureReplayTests.swift`
- Test: `Tests/SwiftStarIntegrationTests/FixtureReplayTests.swift`

**Interfaces:**
- Consumes: `WireEventParser`, `MetricsReducer`, `MetricsState` (Tasks 1–2).
- Produces: `FixtureReplay.lines() -> AsyncStream<String>` (single-pass, ~30 lines/sec, skips blank lines).

- [ ] **Step 1: Copy the fixture and add the resource**

```bash
mkdir -p Sources/SwiftStarAppKit/Resources
cp fixtures/agent/golden.ndjson Sources/SwiftStarAppKit/Resources/golden.ndjson
```

Edit `Package.swift` — the `SwiftStarAppKit` target gains `resources: [.process("Resources")]`:

```swift
.target(
    name: "SwiftStarAppKit",
    dependencies: ["SwiftStarKit"],
    resources: [.process("Resources")]
),
```

- [ ] **Step 2: Implement `FixtureReplay`**

```swift
import Foundation

/// Replays the bundled `golden.ndjson` capture through the wire parser so the
/// lead dials have data before P7. Single pass, no loop; ~30 lines/sec.
public enum FixtureReplay {
    public static func lines() -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                guard let url = Bundle.module.url(forResource: "golden", withExtension: "ndjson"),
                      let text = try? String(contentsOf: url, encoding: .utf8) else {
                    continuation.finish()
                    return
                }
                for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
                    if Task.isCancelled { break }
                    let s = String(line)
                    guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    continuation.yield(s)
                    do {
                        try await Task.sleep(nanoseconds: 33_000_000)
                    } catch {
                        break  // cancelled: stop yielding to a terminated stream
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 3: Write the integration tests**

```swift
import Testing
import Foundation
@testable import SwiftStarAppKit
@testable import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct FixtureReplayTests {
    @Test func bundledFixtureMatchesRepoFixture() throws {
        guard let bundled = Bundle.module.url(forResource: "golden", withExtension: "ndjson") else {
            Issue.record("bundled golden.ndjson missing")
            return
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarIntegrationTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent/golden.ndjson")
        #expect(try Data(contentsOf: bundled) == Data(contentsOf: repo))
    }

    @Test func replayYieldsStatusAndReadyThroughReducer() async {
        var parser = WireEventParser()
        var reducer = MetricsReducer()
        var state = MetricsState()
        var sawStatus = false, sawBudget = false
        for await line in FixtureReplay.lines() {
            if let event = parser.feed(line) {
                reducer.reduce(&state, event)
                if case .status = event { sawStatus = true }
                if case .ready(let p) = event, p != nil { sawBudget = true }
            }
        }
        #expect(sawStatus)
        #expect(sawBudget)
        #expect(state.ctxUsed != nil)
        #expect(state.memoryBudgetPlannedBytes == 49_943_965_040)
    }
}
```

- [ ] **Step 4: Run to verify pass** — `just integration` green (replay of 2136 lines at ~30/s takes ~70 s; that is acceptable for the integration tier, but if it is too slow, raise the cadence constant — the assertions are cadence-independent).

- [ ] **Step 5: Shown-fail** — in `FixtureReplay`, change the guard `!s.trimmingCharacters(...).isEmpty` to always `continue` (drops every line); `replayYieldsStatusAndReadyThroughReducer` fails; restore; green.

- [ ] **Step 6: Commit** — `git add Package.swift Sources/SwiftStarAppKit/Resources/golden.ndjson Sources/SwiftStarAppKit/FixtureReplay.swift Tests/SwiftStarIntegrationTests/FixtureReplayTests.swift && git commit -m "P4: fixture replay + bundled golden.ndjson (AppKit)"`

---

### Task 6: MetricsModel + MetricsView (SwiftStar)

**Files:**
- Create: `Sources/SwiftStar/MetricsModel.swift`, `Sources/SwiftStar/MetricsView.swift`
- Modify: `Sources/SwiftStar/MainView.swift` (swap the Metrics placeholder for `MetricsView`), `Sources/SwiftStar/EngineController.swift` (add a `runningPid` accessor)

**Interfaces:**
- Consumes: `MetricsState`, `MetricsReducer`, `WireEventParser`, `DialLogic`, `Severity`, `MachineSnapshot` (Tasks 1–3); `ProcessStatsCollector` (Task 4); `FixtureReplay` (Task 5); `EngineController.lastKnownPlannedBytes` (P3).
- Produces: `MetricsModel` (`start(enginePid:)`, `stop()`, `state`, `machine`, `isReplayingWire`, `memoryBudgetPlannedBytes`), `MetricsView`.

- [ ] **Step 1: Add the pid accessor to `EngineController`**

```swift
/// The running engine's pid, if the child process is alive.
var runningPid: pid_t? { process?.processIdentifier }
```

- [ ] **Step 2: Implement `MetricsModel`**

```swift
import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit

@MainActor
@Observable
final class MetricsModel {
    private(set) var state = MetricsState()
    private(set) var machine = MachineSnapshot(residentBytes: nil, watts: 0, gpuUtilization: 0, cpuUtilization: 0)
    private(set) var isReplayingWire = false

    private let collector = ProcessStatsCollector()
    private var collectTask: Task<Void, Never>?
    private var replayTask: Task<Void, Never>?
    private var enginePid: pid_t?

    func start(enginePid: pid_t?) {
        // Idempotent: the collector reads the latest pid each tick, and each
        // task is started at most once — calling start again (e.g. on pid
        // change) must not duplicate the timer or restart the replay.
        self.enginePid = enginePid
        if collectTask == nil {
            collectTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { break }
                    self.tick()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        if replayTask == nil {
            replayTask = Task { [weak self] in
                guard let self else { return }
                self.isReplayingWire = true
                var parser = WireEventParser()
                var reducer = MetricsReducer()
                for await line in FixtureReplay.lines() {
                    if let event = parser.feed(line) {
                        reducer.reduce(&self.state, event)
                    }
                }
                self.isReplayingWire = false
            }
        }
    }

    func stop() {
        collectTask?.cancel()
        replayTask?.cancel()
        isReplayingWire = false
    }

    /// Live boot-line budget wins over the replayed ready-event budget: a
    /// recorded budget must never be paired with a live footprint on a
    /// different machine.
    var memoryBudgetPlannedBytes: Int64? {
        EngineController.lastKnownPlannedBytes ?? state.memoryBudgetPlannedBytes
    }

    private func tick() {
        machine = collector.collect(pid: enginePid)
    }
}
```

- [ ] **Step 3: Implement `MetricsView`** (ring, readouts, badge, widened hit region)

```swift
import SwiftUI
import SwiftStarKit

struct MetricsView: View {
    @Bindable var model: MetricsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.isReplayingWire {
                    Label("capture replay — context and throughput are from a recorded session",
                          systemImage: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 32) {
                    contextDial
                    throughputReadouts
                }

                Divider()

                HStack(spacing: 32) {
                    memoryDial
                    gpuDial
                    cpuDial
                    powerDial
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var contextDial: some View {
        let ctx = model.state.ctxUsed
        let severity = ctx.map(DialLogic.contextSeverity(ctxUsed:)) ?? .healthy
        return VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 12)
                // Full ring colored by severity (a fixed-size ring is
                // jitter-proof by construction; a partial arc would read as a
                // fraction, which is the anchor we rejected).
                Circle().stroke(color(for: severity), lineWidth: 12)
                Text(ctx.map { DialLogic.fixedWidth(String($0), width: 8) } ?? "—")
                    .font(.system(.body, design: .monospaced))
            }
            .frame(width: 96, height: 96)
            // Learning #4: widen the hit region to the frame so the tooltip is
            // reachable (a stroked ring hit-tests only the stroke).
            .contentShape(Circle())
            .help(contextTooltip)
            Text("Context")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var throughputReadouts: some View {
        VStack(alignment: .leading, spacing: 8) {
            readout("Prompt", value: String(format: "%.1f tok/s", model.state.prefillTPS))
            readout("Decode", value: String(format: "%.1f tok/s", model.state.genTPS))
            if let ctx = model.state.ctxUsed, let size = model.state.ctxSize {
                Text("\(DialLogic.fixedWidth(String(ctx), width: 10)) of \(size) tokens")
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private func readout(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Text(DialLogic.fixedWidth(value, width: 14))
                .font(.system(.body, design: .monospaced))
        }
    }

    private var memoryDial: some View {
        let budget = model.memoryBudgetPlannedBytes
        let resident = model.machine.residentBytes
        let severity = (resident != nil && budget != nil)
            ? DialLogic.memorySeverity(residentBytes: resident!, plannedBytes: budget!)
            : .healthy
        return dialCard("Memory", severity: severity) {
            if let resident, let budget {
                Text(DialLogic.fixedWidth(String(format: "%.1f", Double(resident) / 1_073_741_824), width: 8) + " GiB of " +
                     String(format: "%.1f", Double(budget) / 1_073_741_824) + " GiB")
                    .font(.system(.body, design: .monospaced))
            } else {
                Text("—")
            }
        }
    }

    private var gpuDial: some View {
        dialCard("GPU", severity: .healthy) {
            Text(DialLogic.fixedWidth(String(format: "%.0f%%", model.machine.gpuUtilization), width: 6))
                .font(.system(.body, design: .monospaced))
        }
    }

    private var cpuDial: some View {
        dialCard("CPU", severity: .healthy) {
            Text(DialLogic.fixedWidth(String(format: "%.0f%%", model.machine.cpuUtilization), width: 6))
                .font(.system(.body, design: .monospaced))
        }
    }

    private var powerDial: some View {
        dialCard("Power", severity: .healthy) {
            Text(DialLogic.fixedWidth(String(format: "%.1f W", model.machine.watts), width: 8))
                .font(.system(.body, design: .monospaced))
        }
    }

    private func dialCard(_ title: String, severity: Severity, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color(for: severity))
                .frame(width: 12, height: 12)
            value()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func color(for severity: Severity) -> Color {
        switch severity {
        case .healthy: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    private var contextTooltip: String {
        guard let ctx = model.state.ctxUsed else { return "No data yet" }
        return "\(ctx) tokens used"
    }
}
```

- [ ] **Step 4: Wire it into `MainView`**

In `MainView`, replace the Metrics placeholder with `MetricsView()`. Own the model at the composition root (alongside the existing `EngineController`):

```swift
struct MainView: View {
    @State private var engineController = EngineController()
    @State private var metricsModel = MetricsModel()

    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            // ... Agent / Diagnostics / Help placeholders unchanged ...
            MetricsView(model: metricsModel)
                .tabItem { Label("Metrics", systemImage: "gauge") }
        }
        .frame(minWidth: 800, minHeight: 560)
        .onAppear { metricsModel.start(enginePid: engineController.runningPid) }
        .onChange(of: engineController.runningPid) { _, newPid in
            metricsModel.start(enginePid: newPid)
        }
    }
}
```

(Adapt the exact ownership to how `EngineController` is currently held; if it is owned in `SwiftStarApp.swift` or `ChatView`, hoist or observe it there — the only requirement is that `metricsModel.start(enginePid:)` is called with the live pid.)

- [ ] **Step 5: Build and smoke** — `swift build` and `just app` green; launch the app, confirm the Metrics tab shows the "capture replay" badge, the context ring/throughput readouts populated by the replay, and live memory/GPU/CPU/power for the running `ds4-server`. No weights needed beyond what P2/P3 already use.

- [ ] **Step 6: Commit** — `git commit -m "P4: metrics model + view (SwiftStar)"`

---

### Task 7: ROADMAP close + verification record

**Files:**
- Modify: `ROADMAP.md` (P4 → complete; Prior work entry)
- Create: `docs/superpowers/research/2026-08-22-p4-verification-record.md`

- [ ] **Step 1: Verification record** — fast-tier counts and the shown-fail records (parser dispatch, ratchet, context threshold), integration evidence (collector snapshot finite/sanitized for a real pid; bundled fixture byte-identical to repo fixture; replay yields status + ready through the reducer), the app smoke, and the IOReport discovery notes (which channel keys worked on this hardware).

- [ ] **Step 2: ROADMAP** — P4 row → `complete (2026-08-22)`; add a Prior work entry summarizing the wire parser, reducer/ratchet, DialLogic, the OS collectors, and the fixture replay; concept budget reviewed (no new terms — "fixture" already covers replay).

- [ ] **Step 3: Final gates** — `just test`, `just integration`, `just docs` all green; `git status` clean.

- [ ] **Step 4: Commit** — `git commit -m "P4: close — roadmap, concept budget, verification record"`

---

## Self-Review

**Spec coverage:** D1 parser (T1), D2 reducer/ratchet (T2), D3 DialLogic + MachineSnapshot + sanitize (T3), D4 collectors (T4), D5 FixtureReplay + bundle + byte-equality (T5), D6 MetricsModel + MetricsView + badge + hit region (T6), D7 scope (no tasks for out-of-scope work; no state dial, no throttle dial, no live ds4-agent, no live-tier capture). Done-when 1→T1/T2/T3, 2→T4/T5, 3→T6, 4→T7.

**Placeholder scan:** all Kit and collector code is concrete; the only guidance-not-code is the MainView wiring (existing ownership is not pinned in this plan — the instruction names the requirement and the accessor). No TBDs.

**Type consistency:** `StatusSnapshot`/`WireEvent` (T1) used by T2/T5/T6; `MetricsState`/`MetricsReducer` (T2) used by T5/T6; `MachineSnapshot`/`DialLogic`/`Severity` (T3) used by T4/T6; `ProcessStatsCollector` (T4) and `FixtureReplay` (T5) used by T6; `EngineController.lastKnownPlannedBytes` (P3) and `runningPid` (T6) used by T6. `@testable import SwiftStarAppKit` + `SwiftStarKit` in the integration tests matches the target dependencies in `Package.swift`.

**Risk flag:** Task 4's IOReport piece is the one place compile/run iteration against real hardware is expected; its gate is the smoke test asserting finite, non-negative, sanitized values (finiteness is the invariant — a zero-watts result that is *finite* is a key-mismatch finding to fix, not a test to relax).
