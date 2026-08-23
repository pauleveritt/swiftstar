# P11 — Subagent Pool: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Context-isolated subagents sharing one locked engine: a `worker`-id wire, an app-side queue over the serialized GPU, a context-assembly packet-maker, and a measurement gate that proves the context-curve win as an envelope, not a point.

**Architecture:** Pure `WorkerId`/`PoolWireParser`/`DispatchReceipt`/`PoolScheduler`/`RollingDigest`/`ContextAssembly`/`EnvelopeMath` in Kit; `PoolEngine` (spawn `--subagent-pool`, multiplex drain, `.kv` loader) in AppKit; the orchestrator wiring in Swift; the `--subagent-pool` C patch (divergence #11) in the engine. Dispatch is a host-tool (P9 `tool_request`/`tool_result`); the receipt folds back on the orchestrator's *next* turn.

**Tech Stack:** Swift 6.3, SwiftPM, swift-testing; C (`ds4_agent.c`, fork divergence #11); git CLI. Fake engine generated from a committed multi-worker capture.

**Spec:** `docs/superpowers/specs/2026-08-23-p11-subagent-pool-design.md`

## Global Constraints

- Fast tier: no model/network/subprocess; the worker-id wire, scheduler, digest, assembly, and envelope are pure Kit functions (tripwire-guarded).
- Binding rule 2 (shown-fail), rule 3 (no source-text assertions), rule 4 (refusal tests have a sibling success test), rule 6 (evidence floor: the fake is regenerated from a committed capture; a worker-tagged capture parses and routes).
- D2 wire-contract-first: the fake for part (1) is hand-authored *against the typed contract* (no multi-worker capture exists yet) and regenerated from a golden capture once the C patch lands (standing recapture rule).
- D8: workers budget-or-receipt, never compact; mutations revision-checked against `writableFiles` (P10 unchanged).
- D10: A-plumbing (dispatch tool schema, receipt schema, worker-id correlation) is non-slippable; A-routing is deferred — the contract reserves the types now.
- Standing rule: every submodule bump owes a golden-fixture recapture (the C patch in Task 8 is a bump).

## File Structure

- Kit: `WorkerId.swift`, `PoolWireParser.swift`, `DispatchReceipt.swift`, `PoolScheduler.swift`, `RollingDigest.swift`, `ContextAssembly.swift`, `EnvelopeMath.swift`; tests `WorkerIdTests`, `PoolWireParserTests`, `DispatchReceiptTests`, `PoolSchedulerTests`, `RollingDigestTests`, `ContextAssemblyTests`, `EnvelopeMathTests`.
- AppKit: `PoolEngine.swift`; integration test `PoolEngineTests`.
- App: `PoolController` wiring in `AgentController.swift` + `DispatchView.swift` updates.
- Engine: `external/ds4/ds4_agent.c` (divergence #11); fixture `fixtures/agent/pool.ndjson`.

---

### Task 1: WorkerId + the worker-id wire contract (outbound and inbound) + DispatchReceipt

**Files:**
- Create: `Sources/SwiftStarKit/WorkerId.swift`
- Create: `Sources/SwiftStarKit/PoolWireParser.swift`
- Create: `Sources/SwiftStarKit/PoolPrompt.swift`
- Create: `Sources/SwiftStarKit/DispatchReceipt.swift`
- Test: `Tests/SwiftStarKitTests/WorkerIdTests.swift`, `Tests/SwiftStarKitTests/PoolWireParserTests.swift`, `Tests/SwiftStarKitTests/PoolPromptTests.swift`, `Tests/SwiftStarKitTests/DispatchReceiptTests.swift`

**Interfaces:**
- Consumes: `AgentWireParser`, `AgentEvent` (existing).
- Produces: `WorkerId { rawValue: Int }` (`.orchestrator == 0`, `Comparable`); `PoolWireEvent { worker: WorkerId, event: AgentEvent }`; `PoolWireParser.feed(_ line: String) -> PoolWireEvent?`; `PoolPrompt { worker: WorkerId, text: String }` + `encode() -> String` (the inbound `{"t":"prompt","worker":N,"s":"..."}` line, D1); `DispatchExecutor { fullContext }` (the D10 reserved discriminator); `DispatchReceipt { worker, executor, ref: String?, reason: String?, summary: String }` + `injectionPrompt() -> String`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/WorkerIdTests.swift`:
```swift
import Testing
@testable import SwiftStarKit

struct WorkerIdTests {
    @Test func orchestratorIsZero() {
        #expect(WorkerId.orchestrator.rawValue == 0)
    }
    @Test func orderingFollowsRawValue() {
        #expect(WorkerId(2) > WorkerId(1))
        #expect(WorkerId(1) < WorkerId(2))
    }
    @Test func roundTripsThroughCodable() throws {
        let id = WorkerId(7)
        let data = try JSONEncoder().encode(id)
        #expect(try JSONDecoder().decode(WorkerId.self, from: data) == id)
    }
}
```

`Tests/SwiftStarKitTests/PoolWireParserTests.swift`:
```swift
import Testing
@testable import SwiftStarKit

struct PoolWireParserTests {
    @Test func absentWorkerDefaultsToOrchestrator() {
        var p = PoolWireParser()
        guard case .hello = p.feed(#"{"t":"hello","v":1,"caps":["text","tool","status","ts"],"ts":1}"#)?.event else {
            Issue.record("expected hello"); return
        }
        // second line: worker field absent
        let ev = p.feed(#"{"t":"text","s":"hi","ts":2}"#)
        #expect(ev?.worker == .orchestrator)
        if case .text(let s) = ev?.event { #expect(s == "hi") }
    }
    @Test func readsWorkerField() {
        var p = PoolWireParser()
        _ = p.feed(#"{"t":"hello","v":1,"caps":["text","tool","status","ts"],"ts":0}"#)
        let ev = p.feed(#"{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":0,"power":100,"error":"","worker":3,"ts":5}"#)
        #expect(ev?.worker == WorkerId(3))
    }
    @Test func malformedWorkerIsZeroNotRefused() {
        var p = PoolWireParser()
        _ = p.feed(#"{"t":"hello","v":1,"caps":["text","tool","status","ts"],"ts":0}"#)
        let ev = p.feed(#"{"t":"text","s":"x","worker":"nope","ts":9}"#)
        #expect(ev?.worker == .orchestrator)
    }
}
```

`Tests/SwiftStarKitTests/DispatchReceiptTests.swift`:
```swift
import Testing
@testable import SwiftStarKit

struct DispatchReceiptTests {
    @Test func candidateInjectionNamesRef() {
        let r = DispatchReceipt(worker: WorkerId(2), ref: "refs/swiftstar/candidates/abc", reason: nil, summary: "3 files changed")
        #expect(r.injectionPrompt().contains("candidate ref refs/swiftstar/candidates/abc"))
        #expect(r.injectionPrompt().contains("Worker 2"))
    }
    @Test func refusalInjectionNamesReason() {
        let r = DispatchReceipt(worker: WorkerId(1), ref: nil, reason: "budgetExceeded", summary: "turn budget exceeded")
        #expect(r.injectionPrompt().contains("refused"))
        #expect(r.injectionPrompt().contains("budgetExceeded"))
    }
}
```

`Tests/SwiftStarKitTests/PoolPromptTests.swift`:
```swift
import Testing
@testable import SwiftStarKit

struct PoolPromptTests {
    @Test func encodesWorkerAddressedPrompt() {
        #expect(PoolPrompt(worker: WorkerId(3), text: "do it").encode()
                == #"{"s":"do it","t":"prompt","worker":3}"#)
    }
    @Test func barePromptIsWorkerZero() {
        #expect(PoolPrompt(worker: .orchestrator, text: "go").encode()
                == #"{"s":"go","t":"prompt","worker":0}"#)
    }
}
```

- [ ] **Step 2: Run the tests, confirm RED**

Run: `swift test --filter WorkerIdTests` then `--filter PoolWireParserTests` then `--filter DispatchReceiptTests`
Expected: compile errors (types undefined).

- [ ] **Step 3: Write the implementation**

`Sources/SwiftStarKit/WorkerId.swift`:
```swift
import Foundation

/// A worker's identity on the pooled wire (D1): one engine hosts N sessions,
/// each event line carries a `worker` id. `0` is the orchestrator (the project
/// session). Absent on a single-session wire, so a parser defaults to `.orchestrator`.
public struct WorkerId: RawRepresentable, Codable, Equatable, Hashable, Sendable, Comparable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public static let orchestrator = WorkerId(rawValue: 0)
    public static func < (lhs: WorkerId, rhs: WorkerId) -> Bool { lhs.rawValue < rhs.rawValue }
}
```

`Sources/SwiftStarKit/PoolWireParser.swift`:
```swift
import Foundation

/// One event from the pooled wire (D1): the event plus the worker id it was
/// emitted for. The `worker` field is optional (absent = orchestrator), so a
/// pre-pool single-session wire parses as worker 0.
public struct PoolWireEvent: Equatable, Sendable {
    public let worker: WorkerId
    public let event: AgentEvent
}

/// Streaming consumer for the pooled wire. Composes `AgentWireParser` (which
/// deliberately ignores the unknown `worker` field, keeping the single-session
/// consumers untouched) and reads `worker` out of the raw line before
/// delegating. The handshake is worker 0.
public struct PoolWireParser: Sendable {
    private var inner = AgentWireParser()
    public init() {}

    public mutating func feed(_ line: String) -> PoolWireEvent? {
        let worker = Self.extractWorker(line)
        guard let event = inner.feed(line) else { return nil }
        return PoolWireEvent(worker: worker, event: event)
    }

    private static func extractWorker(_ line: String) -> WorkerId {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let worker = object["worker"] as? NSNumber else {
            return .orchestrator
        }
        return WorkerId(rawValue: worker.intValue)
    }
}
```

`Sources/SwiftStarKit/DispatchReceipt.swift`:
```swift
import Foundation

/// The reserved routing discriminator (D10): which executor shape ran the
/// worker. `.fullContext` is the only case in v1; the specialized one-command
/// worker is the future case A-routing adds without churning the contract.
public enum DispatchExecutor: String, Codable, Equatable, Sendable {
    case fullContext
}

/// The bounded result that folds back from a worker into the orchestrator's
/// next turn (D4). A candidate ref (a real commit) or a refusal reason — never
/// the worker's transcript. `Codable` so the pool ledger can persist it.
public struct DispatchReceipt: Codable, Equatable, Sendable {
    public let worker: WorkerId
    public let executor: DispatchExecutor
    public let ref: String?
    public let reason: String?
    public let summary: String

    public init(worker: WorkerId, executor: DispatchExecutor = .fullContext,
                ref: String?, reason: String?, summary: String) {
        self.worker = worker
        self.executor = executor
        self.ref = ref
        self.reason = reason
        self.summary = summary
    }

    /// The prompt text injected into the orchestrator's next turn (D4).
    public func injectionPrompt() -> String {
        if let ref {
            return "Worker \(worker.rawValue) returned candidate ref \(ref): \(summary)"
        }
        return "Worker \(worker.rawValue) refused: \(reason ?? summary)"
    }
}
```

`Sources/SwiftStarKit/PoolPrompt.swift`:
```swift
import Foundation

/// The inbound prompt line (D1): how the app addresses a worker's turn on the
/// pooled wire. A bare line (no `worker`) is the orchestrator (worker 0). The
/// encoder is the single authority; the C patch and the fake both consume it.
public struct PoolPrompt: Equatable, Sendable {
    public let worker: WorkerId
    public let text: String
    public init(worker: WorkerId, text: String) { self.worker = worker; self.text = text }

    /// `{"t":"prompt","worker":N,"s":"..."}` — keys sorted for determinism.
    public func encode() -> String {
        let obj: [String: Any] = ["t": "prompt", "worker": worker.rawValue, "s": text]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}
```

- [ ] **Step 4: Run the tests, confirm GREEN**

Run: `swift test --filter WorkerIdTests --filter PoolWireParserTests --filter DispatchReceiptTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/WorkerId.swift Sources/SwiftStarKit/PoolWireParser.swift Sources/SwiftStarKit/PoolPrompt.swift Sources/SwiftStarKit/DispatchReceipt.swift Tests/SwiftStarKitTests/WorkerIdTests.swift Tests/SwiftStarKitTests/PoolWireParserTests.swift Tests/SwiftStarKitTests/PoolPromptTests.swift Tests/SwiftStarKitTests/DispatchReceiptTests.swift
git commit -m "P11: WorkerId + worker-id wire (in+out) + PoolPrompt + DispatchReceipt"
```

---

### Task 2: PoolScheduler — the pure queue/scheduler state machine

**Files:**
- Create: `Sources/SwiftStarKit/PoolScheduler.swift`
- Test: `Tests/SwiftStarKitTests/PoolSchedulerTests.swift`

**Interfaces:**
- Consumes: `WorkerId`, `HandoffPacket`, `DispatchReceipt`.
- Produces: `PoolState { pending: [WorkerId: HandoffPacket], running: WorkerId?, completed: [WorkerId: DispatchReceipt], pendingDelivery: [WorkerId: DispatchReceipt], nextId: Int }`; `PoolCommand` (`.enqueue(packet:)`, `.workerStarted(WorkerId)`, `.workerFinished(WorkerId, DispatchReceipt)`, `.workerFailed(WorkerId, DispatchReceipt)`, `.receiptInjected(WorkerId)`); `PoolScheduler.apply(_:_:) -> PoolState`, `PoolScheduler.nextWorker(_:) -> (WorkerId, HandoffPacket)?`, `PoolScheduler.canStart(_:) -> Bool`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SwiftStarKit

struct PoolSchedulerTests {
    private func packet(_ task: String) -> HandoffPacket {
        HandoffPacket(taskText: task, writableFiles: ["a.swift"], validationCommand: nil,
                      baselines: [:], turnBudget: 1000, toolCallBudget: 8)
    }
    @Test func enqueueThenStartRunsOneAtATime() {
        var s = PoolState()
        s = PoolScheduler.apply(s, .enqueue(packet: packet("one")))
        s = PoolScheduler.apply(s, .enqueue(packet: packet("two")))
        let first = PoolScheduler.nextWorker(s)
        #expect(first?.1.taskText == "one")
        s = PoolScheduler.apply(s, .workerStarted(first!.0))
        #expect(s.running != nil)
        #expect(PoolScheduler.canStart(s) == false)   // serialized: one at a time
        #expect(s.pending.count == 1)
    }
    @Test func finishRecordsReceiptAndFreesTheEngine() {
        var s = PoolState()
        s = PoolScheduler.apply(s, .enqueue(packet: packet("one")))
        s = PoolScheduler.apply(s, .enqueue(packet: packet("two")))
        let first = PoolScheduler.nextWorker(s)!
        s = PoolScheduler.apply(s, .workerStarted(first.0))
        let receipt = DispatchReceipt(worker: first.0, ref: "ref", reason: nil, summary: "done")
        s = PoolScheduler.apply(s, .workerFinished(first.0, receipt))
        #expect(s.completed[first.0] == receipt)
        #expect(s.running == nil)
        #expect(PoolScheduler.canStart(s) == true)     // engine freed for the next worker
        #expect(PoolScheduler.nextWorker(s)?.1.taskText == "two")
    }
    @Test func refusalReceiptStillCompletes() {
        var s = PoolState()
        s = PoolScheduler.apply(s, .enqueue(packet: packet("one")))
        let w = PoolScheduler.nextWorker(s)!
        s = PoolScheduler.apply(s, .workerStarted(w.0))
        let receipt = DispatchReceipt(worker: w.0, ref: nil, reason: "noChanges", summary: "nothing")
        s = PoolScheduler.apply(s, .workerFinished(w.0, receipt))
        #expect(s.completed[w.0]?.reason == "noChanges")
    }
    @Test func workerFailureFreesTheEngineAsAReceipt() {
        var s = PoolState()
        s = PoolScheduler.apply(s, .enqueue(packet: packet("one")))
        s = PoolScheduler.apply(s, .enqueue(packet: packet("two")))
        let w = PoolScheduler.nextWorker(s)!
        s = PoolScheduler.apply(s, .workerStarted(w.0))
        let failure = DispatchReceipt(worker: w.0, ref: nil, reason: "engine crash", summary: "crashed")
        s = PoolScheduler.apply(s, .workerFailed(w.0, failure))
        #expect(s.completed[w.0]?.reason == "engine crash")
        #expect(s.running == nil)             // engine freed
        #expect(PoolScheduler.canStart(s))    // next worker can run
        #expect(PoolScheduler.nextWorker(s)?.1.taskText == "two")
    }
    @Test func receiptInjectedClearsPendingDelivery() {
        var s = PoolState()
        s = PoolScheduler.apply(s, .enqueue(packet: packet("one")))
        let w = PoolScheduler.nextWorker(s)!
        s = PoolScheduler.apply(s, .workerStarted(w.0))
        s = PoolScheduler.apply(s, .workerFinished(w.0, DispatchReceipt(worker: w.0, ref: "r", reason: nil, summary: "d")))
        s = PoolScheduler.apply(s, .receiptInjected(w.0))
        // completed receipts that were injected move to an "injected" set; they no longer count as pending delivery
        #expect(s.pendingDelivery.isEmpty)
    }
}
```

- [ ] **Step 2: Run, confirm RED** (`swift test --filter PoolSchedulerTests`).

- [ ] **Step 3: Write the implementation**

`Sources/SwiftStarKit/PoolScheduler.swift`:
```swift
import Foundation

/// The pool's state (D1): the queue of pending workers, the currently running
/// worker (at most one — the serialized family), the completed receipts, and
/// receipts awaiting delivery back into the orchestrator. Pure value type.
public struct PoolState: Equatable, Sendable {
    public var pending: [WorkerId: HandoffPacket] = [:]
    public var running: WorkerId?
    public var completed: [WorkerId: DispatchReceipt] = [:]
    public var pendingDelivery: [WorkerId: DispatchReceipt] = [:]
    public var nextId: Int = 1
    public init() {}
}

/// A command that transitions `PoolState` (D1). Pure; `PoolScheduler.apply` is
/// a function of state + command.
public enum PoolCommand: Equatable, Sendable {
    case enqueue(packet: HandoffPacket)
    case workerStarted(WorkerId)
    case workerFinished(WorkerId, DispatchReceipt)
    /// An infrastructure failure (engine crash, timeout, thrown attempt) folded
    /// into a receipt — the caller maps the failure to a `DispatchReceipt` with
    /// a reason. Frees the engine exactly like `workerFinished`.
    case workerFailed(WorkerId, DispatchReceipt)
    case receiptInjected(WorkerId)
}

/// The pure scheduler (D1): a queue over one serialized engine. One worker
/// generates at a time; `nextWorker` returns the next pending worker only when
/// the engine is free.
public enum PoolScheduler {
    public static func apply(_ state: PoolState, _ command: PoolCommand) -> PoolState {
        var s = state
        switch command {
        case .enqueue(let packet):
            let id = WorkerId(s.nextId)
            s.nextId += 1
            s.pending[id] = packet
        case .workerStarted(let id):
            s.pending[id] = nil
            s.running = id
        case .workerFinished(let id, let receipt), .workerFailed(let id, let receipt):
            s.running = nil
            s.completed[id] = receipt
            s.pendingDelivery[id] = receipt
        case .receiptInjected(let id):
            s.pendingDelivery[id] = nil
        }
        return s
    }

    public static func canStart(_ state: PoolState) -> Bool {
        state.running == nil && !state.pending.isEmpty
    }

    /// The next worker to run, in enqueue order (smallest id), when the engine
    /// is free. Returns nil when nothing is pending or the engine is busy.
    public static func nextWorker(_ state: PoolState) -> (WorkerId, HandoffPacket)? {
        guard state.running == nil,
              let entry = state.pending.min(by: { $0.key < $1.key }) else { return nil }
        return (entry.key, entry.value)
    }
}
```

- [ ] **Step 4: Run, confirm GREEN** (`swift test --filter PoolSchedulerTests`).

- [ ] **Step 5: Commit** `P11: PoolScheduler state machine`.

---

### Task 3: RollingDigest — the objective-independent reduced form

**Files:**
- Create: `Sources/SwiftStarKit/RollingDigest.swift`
- Test: `Tests/SwiftStarKitTests/RollingDigestTests.swift`

**Interfaces:**
- Consumes: `PoolWireEvent`, `AgentEvent`, `DispatchReceipt`.
- Produces: `RollingDigest` (value); `RollingDigestReducer.apply(_:event:) -> RollingDigest`; `RollingDigestReducer.record(_:receipt:) -> RollingDigest`; `RollingDigest.summary() -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SwiftStarKit

struct RollingDigestTests {
    @Test func stripsToolNoiseKeepsMutations() {
        var d = RollingDigest()
        // a tool_request that the host verdict recorded (mutation on file a.swift)
        var p = PoolWireParser()
        _ = p.feed(#"{"t":"hello","v":1,"caps":["text","tool","status","ts"],"ts":0}"#)
        if let ev = p.feed(#"{"t":"tool_request","idx":0,"name":"edit","params":[{"name":"path","value":"a.swift"}],"worker":1,"ts":3}"#) {
            d = RollingDigestReducer.apply(d, event: ev)
        }
        // the reducer itself does NOT record mutations from a tool_request
        // (the host verdict does, via `record`); it records the call name only.
        #expect(d.toolCalls == ["edit"])
        #expect(!d.filesTouched.contains("a.swift"))   // mutations come via recordHostVerdict, not the wire
    }
    @Test func recordReceiptAddsRefAndKeepsLedger() {
        var d = RollingDigest()
        d = RollingDigestReducer.record(d, receipt: DispatchReceipt(worker: WorkerId(1), ref: "ref1", reason: nil, summary: "changed 2 files"))
        #expect(d.refs[WorkerId(1)] == "ref1")
        #expect(d.summary().contains("ref1"))
    }
    @Test func recordHostVerdictAccumulatesMutationsAndExit() {
        var d = RollingDigest()
        d = RollingDigestReducer.recordHostVerdict(d, mutations: ["a.swift"], exitStatus: 0, validationRan: true)
        #expect(d.filesTouched == ["a.swift"])
        #expect(d.exitStatuses == [0])
        #expect(d.validationRan)
    }
    @Test func summaryIsDeterministic() {
        var d = RollingDigest()
        d = RollingDigestReducer.record(d, receipt: DispatchReceipt(worker: WorkerId(2), ref: "r", reason: nil, summary: "s"))
        let s1 = d.summary()
        let s2 = d.summary()
        #expect(s1 == s2)
        #expect(s1.contains("Worker 2"))
    }
}
```

- [ ] **Step 2: Run, confirm RED** (`swift test --filter RollingDigestTests`).

- [ ] **Step 3: Write the implementation**

`Sources/SwiftStarKit/RollingDigest.swift`:
```swift
import Foundation

/// The objective-independent "always-want" reduced form of the conversation
/// (D6): strip tool noise, keep the host-authoritative ledger. Maintained
/// incrementally, host-side, with no model and no inference — the packet-maker's
/// Layer 1, pre-chewed out-of-band. The raw conversation is never prefilled
/// again; only this digest is.
public struct RollingDigest: Equatable, Sendable {
    public var toolCalls: [String] = []
    public var filesTouched: [String] = []
    public var exitStatuses: [Int] = []
    public var validationRan = false
    public var refs: [WorkerId: String] = [:]
    public var receipts: [WorkerId: String] = [:]

    public init() {}

    /// The bounded, deterministic one-line-per-fact form the adaptation step
    /// reads (and the compaction ledger reconstructs from — D9).
    public func summary() -> String {
        var lines: [String] = []
        if !filesTouched.isEmpty { lines.append("files: \(filesTouched.joined(separator: ","))") }
        if !exitStatuses.isEmpty { lines.append("exit: \(exitStatuses.map(String.init).joined(separator: ","))") }
        if validationRan { lines.append("validated: true") }
        for (w, ref) in refs.sorted(by: { $0.key < $1.key }) { lines.append("Worker \(w.rawValue) ref: \(ref)") }
        for (w, reason) in receipts.sorted(by: { $0.key < $1.key }) { lines.append("Worker \(w.rawValue) refused: \(reason)") }
        return lines.joined(separator: "\n")
    }
}

/// The pure reducer that folds wire events and host facts into the digest.
public enum RollingDigestReducer {
    /// Fold one pooled wire event: tool calls are kept (the name only — the
    /// params, which carry the noise, are dropped); text/think/status are not
    /// digested (they are the noise being stripped).
    public static func apply(_ digest: RollingDigest, event: PoolWireEvent) -> RollingDigest {
        var d = digest
        switch event.event {
        case .toolRequest(_, let name, _):
            d.toolCalls.append(name)
        default:
            break
        }
        return d
    }

    /// The host's verdict on a tool call (P9/P10 facts): the actual mutations
    /// and the validation/exit facts — these, not the wire, are authoritative.
    public static func recordHostVerdict(_ digest: RollingDigest, mutations: [String],
                                         exitStatus: Int?, validationRan: Bool) -> RollingDigest {
        var d = digest
        d.filesTouched.append(contentsOf: mutations)
        if let exitStatus { d.exitStatuses.append(exitStatus) }
        if validationRan { d.validationRan = true }
        return d
    }

    /// Fold a worker's receipt into the ledger (D9): the ref or the refusal
    /// reason. This is the pool state that survives the orchestrator's
    /// compaction.
    public static func record(_ digest: RollingDigest, receipt: DispatchReceipt) -> RollingDigest {
        var d = digest
        if let ref = receipt.ref {
            d.refs[receipt.worker] = ref
        } else if let reason = receipt.reason {
            d.receipts[receipt.worker] = reason
        }
        return d
    }
}
```

- [ ] **Step 4: Run, confirm GREEN** (`swift test --filter RollingDigestTests`).

- [ ] **Step 5: Commit** `P11: RollingDigest reducer`.

---

### Task 4: ContextAssembly — the packet-maker's pure mapping

**Files:**
- Create: `Sources/SwiftStarKit/ContextAssembly.swift`
- Test: `Tests/SwiftStarKitTests/ContextAssemblyTests.swift`

**Interfaces:**
- Consumes: `RollingDigest`, `HandoffPacket`.
- Produces: `ContextAssembly.deterministicAdaptation(objective:digest:loaded:implementer:) -> String` (the v1 sizing template, D7 — no model trip); `ContextAssembly.adaptationPrompt(objective:digest:loaded:implementer:) -> String` (the **deferred** no-think model prompt — not run in P11); `ContextAssembly.assemble(objective:digest:loaded:adaptation:) -> String` (the prepared `taskText`).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SwiftStarKit

struct ContextAssemblyTests {
    @Test func assembleBundlesObjectiveDigestReadsAndAdaptation() {
        var d = RollingDigest()
        d = RollingDigestReducer.record(d, receipt: DispatchReceipt(worker: WorkerId(1), ref: "ref1", reason: nil, summary: "s"))
        let task = ContextAssembly.assemble(
            objective: "Fix the broken test",
            digest: d,
            loaded: ["ROADMAP.md": "P11 is next"],
            adaptation: "The worker should edit Tests/FooTests.swift")
        #expect(task.contains("Fix the broken test"))
        #expect(task.contains("ref1"))            // digest folded in
        #expect(task.contains("ROADMAP.md"))       // staged read named
        #expect(task.contains("edit Tests/FooTests.swift"))
    }
    @Test func deterministicAdaptationSizesToImplementer() {
        let small = ContextAssembly.deterministicAdaptation(objective: "o", digest: RollingDigest(), loaded: ["a.swift": "x"], implementer: "mellum")
        let large = ContextAssembly.deterministicAdaptation(objective: "o", digest: RollingDigest(), loaded: ["a.swift": "x"], implementer: "laguna")
        #expect(small.contains("one at a time"))       // small-capability: finer, chunked
        #expect(!large.contains("one at a time"))      // large-capability: coarse
        #expect(large.contains("as you see fit"))
    }
    @Test func adaptationPromptTargetsImplementerSize() {
        let prompt = ContextAssembly.adaptationPrompt(
            objective: "o", digest: RollingDigest(), loaded: ["f": "x"], implementer: "mellum")
        #expect(prompt.contains("mellum"))
        #expect(prompt.contains("split into smaller chunks"))
    }
    @Test func assembleWithoutAdaptationStillCarriesObjective() {
        let task = ContextAssembly.assemble(objective: "o", digest: RollingDigest(), loaded: [:], adaptation: "")
        #expect(task.contains("o"))
    }
}
```

- [ ] **Step 2: Run, confirm RED** (`swift test --filter ContextAssemblyTests`).

- [ ] **Step 3: Write the implementation**

`Sources/SwiftStarKit/ContextAssembly.swift`:
```swift
import Foundation

/// The packet-maker (D5): `deterministic-load → rolling digest → objective-dependent
/// adaptation → packet`. This type is the **pure** half — it maps the assembled
/// inputs (objective, digest, staged reads, the adaptation text) into the
/// packet's prepared `taskText`. The model trip that produces `adaptation`
/// (D7) is impure and lives in the app; `adaptationPrompt` is the pure prompt
/// that trip is fed.
public enum ContextAssembly {
    /// The deterministic v1 adaptation (D7): size the brief to the implementer
    /// without a model trip. A small-capability implementer (mellum/afm) gets a
    /// finer, single-file-steps brief; a large one (laguna) gets a coarse,
    /// general brief. Pure — the deferred no-think model trip (`adaptationPrompt`)
    /// would replace this once the gate justifies it.
    public static func deterministicAdaptation(objective: String, digest: RollingDigest,
                                               loaded: [String: String], implementer: String) -> String {
        let isSmall = implementer.lowercased().contains("mellum")
            || implementer.lowercased().contains("afm")
        let reads = loaded.keys.sorted().joined(separator: ", ")
        if isSmall {
            return "Work in small, single-file steps, one at a time. Staged files: \(reads). Objective: \(objective)"
        }
        return "Objective: \(objective). Staged files: \(reads). Work as you see fit."
    }

    /// The deferred no-think prompt for the model-trip form of D7 (NOT run in
    /// P11 — out of scope with the RLM tier). Kept so the contract is complete
    /// when that trip lands.
    public static func adaptationPrompt(objective: String, digest: RollingDigest,
                                        loaded: [String: String], implementer: String) -> String {
        let reads = loaded.keys.sorted().joined(separator: ", ")
        return """
        Objective: \(objective)

        Available reduced context (host ledger — already stripped of tool noise):
        \(digest.summary())

        Staged files: \(reads)

        Write the minimal worker brief for the implementer model \(implementer):
        - filter this context to only what bears on the objective;
        - if \(implementer) is small-capability, split the task into smaller, more
          detailed chunks; if large-capability, keep it coarse and general.
        Output only the brief.
        """
    }

    /// Assemble the packet's prepared `taskText` from its inputs (D5). The
    /// objective leads; the digest and staged reads follow; the adaptation is
    /// the final, objective-scoped instruction. Deterministic and pure.
    public static func assemble(objective: String, digest: RollingDigest,
                                loaded: [String: String], adaptation: String) -> String {
        var parts: [String] = ["Task: \(objective)"]
        let d = digest.summary()
        if !d.isEmpty { parts.append("Context (reduced):\n\(d)") }
        if !loaded.isEmpty {
            parts.append("Staged files: \(loaded.keys.sorted().joined(separator: ", "))")
        }
        if !adaptation.isEmpty { parts.append("Instructions:\n\(adaptation)") }
        return parts.joined(separator: "\n\n")
    }
}
```

- [ ] **Step 4: Run, confirm GREEN** (`swift test --filter ContextAssemblyTests`).

- [ ] **Step 5: Commit** `P11: ContextAssembly (packet-maker pure mapping)`.

---

### Task 5: EnvelopeMath — the measurement-gate report

**Files:**
- Create: `Sources/SwiftStarKit/EnvelopeMath.swift`
- Test: `Tests/SwiftStarKitTests/EnvelopeMathTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `PacketPerturbation` (`.canonical`, `.taskTextBloat15x`, `.taskTextBloat2x`, `.failureInjection`, `.packetCountSweep`); `EnvelopeReport`; `EnvelopeMath.ceiling` (4.2); `EnvelopeMath.overheadRatio(realizedWin:) -> Double`; `EnvelopeMath.report(winByPerturbation:tokensEvaluated:tokensNominal:peakResidentMB:snapshotSaveCount:snapshotRestoreCount:) -> EnvelopeReport`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SwiftStarKit

struct EnvelopeMathTests {
    @Test func overheadRatioIsRealizedOverCeiling() {
        #expect(EnvelopeMath.overheadRatio(realizedWin: 4.2) == 1.0)
        #expect(EnvelopeMath.overheadRatio(realizedWin: 2.1) == 0.5)
    }
    @Test func reportCarriesAllEnvelopeArms() {
        let r = EnvelopeMath.report(
            winByPerturbation: [.canonical: 2.5, .taskTextBloat2x: 1.1],
            tokensEvaluated: 900, tokensNominal: 1000,
            peakResidentMB: 41000, snapshotSaveCount: 0, snapshotRestoreCount: 0)
        #expect(r.winByPerturbation[.canonical] == 2.5)
        #expect(r.tokensEvaluated == 900)
        #expect(r.snapshotSaveCount == 0)
        #expect(r.overheadRatio == EnvelopeMath.overheadRatio(realizedWin: 2.5))
    }
    @Test func zeroWinIsNotANumberHazard() {
        // a realized win of 0 (the pool did no better than deep) → ratio 0, not NaN
        #expect(EnvelopeMath.overheadRatio(realizedWin: 0) == 0)
    }
    @Test func perturbationsAreDeterministic() {
        let t = "fix a.swift"
        #expect(PacketPerturbation.canonical.apply(to: t) == t)
        #expect(PacketPerturbation.taskTextBloat2x.apply(to: t).count > t.count)
        #expect(PacketPerturbation.taskTextBloat2x.apply(to: t) == PacketPerturbation.taskTextBloat2x.apply(to: t))
        #expect(PacketPerturbation.packetCountSweepCounts == [1, 2, 4, 8])
    }
}
```

- [ ] **Step 2: Run, confirm RED** (`swift test --filter EnvelopeMathTests`).

- [ ] **Step 3: Write the implementation**

`Sources/SwiftStarKit/EnvelopeMath.swift`:
```swift
import Foundation

/// One arm of the sensitivity envelope (D11): the deterministic perturbations
/// of the canonical packet set — no model judgment anywhere in the sweep.
public enum PacketPerturbation: String, CaseIterable, Equatable, Sendable {
    case canonical
    case taskTextBloat15x
    case taskTextBloat2x
    case failureInjection
    case packetCountSweep
}

/// The gate's report (D11): an envelope, not a point. `overheadRatio` is the
/// realized win over the analytic ceiling; `winByPerturbation` is the
/// sensitivity envelope; the counters are the instrumentation.
public struct EnvelopeReport: Equatable, Sendable {
    public let overheadRatio: Double
    public let winByPerturbation: [PacketPerturbation: Double]
    public let tokensEvaluated: Int
    public let tokensNominal: Int
    public let peakResidentMB: Int
    public let snapshotSaveCount: Int
    public let snapshotRestoreCount: Int
}

/// The pure arithmetic of the measurement gate (D11).
public enum EnvelopeMath {
    /// The analytic upper bound (research note): 8 × 16k sequential prefills
    /// vs one 131k prefill, integrated from the measured curve.
    public static let ceiling = 4.2

    /// realized win / ceiling. A realized win of 0 is a ratio of 0 (not NaN);
    /// the win is `deepSeconds / poolSeconds`.
    public static func overheadRatio(realizedWin: Double) -> Double {
        realizedWin / ceiling
    }

    public static func report(winByPerturbation: [PacketPerturbation: Double],
                              tokensEvaluated: Int, tokensNominal: Int,
                              peakResidentMB: Int,
                              snapshotSaveCount: Int, snapshotRestoreCount: Int) -> EnvelopeReport {
        EnvelopeReport(
            overheadRatio: overheadRatio(realizedWin: winByPerturbation[.canonical] ?? 0),
            winByPerturbation: winByPerturbation,
            tokensEvaluated: tokensEvaluated,
            tokensNominal: tokensNominal,
            peakResidentMB: peakResidentMB,
            snapshotSaveCount: snapshotSaveCount,
            snapshotRestoreCount: snapshotRestoreCount)
    }
}

/// The deterministic perturbation constructors (D11): each arm is built by a
/// pure function over the canonical packet, never by ad-hoc shell logic.
extension PacketPerturbation {
    /// The counts the packet-count sweep runs (D11).
    public static let packetCountSweepCounts = [1, 2, 4, 8]

    /// Apply this perturbation to a canonical `taskText` (deterministic filler;
    /// bloat simulates a wordier brief to sample the prefill curve's response to
    /// input size). `.canonical`/`.failureInjection`/`.packetCountSweep` leave
    /// the text unchanged.
    public func apply(to taskText: String) -> String {
        switch self {
        case .taskTextBloat15x: return taskText + String(repeating: " detail", count: taskText.count / 2)
        case .taskTextBloat2x:  return taskText + String(repeating: " detail", count: taskText.count)
        case .canonical, .failureInjection, .packetCountSweep: return taskText
        }
    }
}
```

- [ ] **Step 4: Run, confirm GREEN** (`swift test --filter EnvelopeMathTests`).

- [ ] **Step 5: Commit** `P11: EnvelopeMath (gate arithmetic)`.

---

### Task 6: The worker-tagged fake — fixture + argv + parser integration

**Files:**
- Create: `fixtures/agent/pool.ndjson` (a small synthetic multi-worker capture, hand-authored *against the typed contract* — the D2 stand-in, regenerated from a golden capture in Task 8).
- Test: `Tests/SwiftStarIntegrationTests/PoolEngineTests.swift` (or extend `FakeAgentIntegrationTests.swift`).

**Interfaces:**
- Consumes: `FakeAgentSource`, `FakeAgentHarness`, `PoolWireParser`, `AgentCommand`.
- Produces: an integration proof that a worker-tagged capture replays verbatim through the fake and parses/routes by worker.

- [ ] **Step 1: Write the fixture**

`fixtures/agent/pool.ndjson` — every line carries `worker` and `ts` (the fake derives delays from `ts`; `worker` is replayed verbatim):
```
{"t":"hello","v":1,"caps":["text","tool","status","ts"],"ts":0,"worker":0}
{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":0,"power":100,"error":"","ts":1,"worker":0}
{"t":"tool_request","idx":0,"name":"dispatch","params":[{"name":"taskText","value":"fix a.swift"}],"ts":2,"worker":0}
{"t":"ready","stop_reason":"eos","generated":3,"ctx_used":10,"ts":3,"worker":0}
{"t":"status","state":"generating","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":0,"power":100,"error":"","ts":4,"worker":1}
{"t":"ready","stop_reason":"eos","generated":2,"ctx_used":8,"ts":5,"worker":1}
```

- [ ] **Step 2: Write the failing integration test**

`Tests/SwiftStarIntegrationTests/PoolEngineTests.swift`:
```swift
import Foundation
import Testing
import SwiftStarKit

@testable import SwiftStarAppKit

struct PoolEngineTests {
    @Test func workerTaggedCaptureRoutesByWorker() throws {
        let capture = try Data(contentsOf: FakeAgentHarness.fixture("pool.ndjson"))
        // The fake validates argv strictly; a pool spawn adds --subagent-pool 2.
        let argv = ["-m", "model.gguf", "-c", "8192", "--metal", "--non-interactive",
                    "--json-events", "--workspace", "/tmp/w", "--shell", "off",
                    "--host-tools", "--subagent-pool", "2"]
        let source = try FakeAgentSource.generate(capture: capture, engineArgv: argv, hostTools: true)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pool-\(UUID().uuidString)")
        let binary = try FakeAgentHarness.compileFake(source: source, into: dir)
        let fake = try FakeAgentHarness.spawnAgent(binary, arguments: argv, env: ["FAKE_SPEED": "0"])
        defer { fake.process.terminate() }

        var parser = PoolWireParser()
        // The inbound contract (D1): the prompt is PoolPrompt-encoded. The fake
        // replays the whole capture per prompt line, so one prompt yields every
        // worker-tagged event in the fixture.
        FakeAgentHarness.writePrompt(fake, PoolPrompt(worker: .orchestrator, text: "go").encode())
        let events = try FakeAgentHarness.readPoolEvents(fake, parser: &parser) { es in
            es.contains { $0.worker.rawValue == 1 }
        }
        // The dispatch request is on worker 0; the worker's turn is worker 1.
        let dispatch = events.first { $0.worker == .orchestrator && {
            if case .toolRequest(_, let name, _) = $0.event { return name == "dispatch" }; return false
        }() }
        #expect(dispatch != nil)
        let workerEvents = events.filter { $0.worker == WorkerId(1) }
        #expect(!workerEvents.isEmpty)
    }
}
```

Run `SWIFTSTAR_INTEGRATION=1 swift test --filter PoolEngineTests`, confirm RED (compile fails: `readPoolEvents` undefined).

- [ ] **Step 3: Add the `PoolWireParser` overload to the harness**

Add to `Tests/SwiftStarIntegrationTests/FakeAgentHarness.swift` (a sibling of `readAgentEvents`):
```swift
static func readPoolEvents(_ fake: FakeAgentProcess,
                           parser: inout PoolWireParser,
                           until: @escaping ([PoolWireEvent]) -> Bool,
                           timeout: TimeInterval = 30) throws -> [PoolWireEvent] {
    var events: [PoolWireEvent] = []
    let fd = fake.stdout.fileHandleForReading.fileDescriptor
    let deadline = Date().addingTimeInterval(timeout)
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while Date() < deadline {
        let n = Darwin.read(fd, &chunk, chunk.count)
        if n == 0 { throw FakeAgentHarnessError.unexpectedEOF }
        if n < 0 { if errno == EINTR { continue }; throw FakeAgentHarnessError.readFailed(errno: errno) }
        buffer.append(contentsOf: chunk[0..<n])
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let event = parser.feed(line) {
                events.append(event)
                if until(events) { return events }
            }
        }
    }
    throw FakeAgentHarnessError.timeout(eventCount: events.count)
}
```

- [ ] **Step 4: Run `SWIFTSTAR_INTEGRATION=1 swift test --filter PoolEngineTests`, confirm GREEN.**

- [ ] **Step 5: Commit** `P11: worker-tagged pool fixture + fake-argv integration`.

---

### Task 7: PoolEngine (AppKit) — spawn + multiplex drain + loaders

**Files:**
- Create: `Sources/SwiftStarAppKit/PoolEngine.swift`
- Test: `Tests/SwiftStarIntegrationTests/PoolEngineTests.swift` (extend)

**Interfaces:**
- Consumes: `AgentCommand`, `PoolWireParser`, `SubprocessRunner`.
- Produces: `PoolEngine.argv(settings:workers:) -> [String]` (adds `--subagent-pool N`); `PoolEngine.readKVText(_:) throws -> String` (the `.kv` loader, 48-byte header — the D6 crash-recovery backing, consumed by digest reconstruction); `PoolEngine.listFiles(_:)` (deterministic loader). The multiplex drain and the dispatch loop land in Task 9 (they need the scheduler + `WorktreeDispatcher`).

- [ ] **Step 1: Write the failing tests**

Extend `PoolEngineTests`:
```swift
    @Test func kvReaderSkipsThe48ByteHeader() throws {
        // A synthetic .kv: 48 header bytes, then rendered UTF-8 text.
        var bytes = Data(repeating: 0x41, count: 48)   // header (garbage, ignored)
        let body = Data("hello conversation".utf8)
        bytes.append(body)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("session.kv")
        try bytes.write(to: url)
        let text = try PoolEngine.readKVText(url)
        #expect(text == "hello conversation")
    }
```

- [ ] **Step 2: Run, confirm RED** (`SWIFTSTAR_INTEGRATION=1 swift test --filter PoolEngineTests`, the kv test fails: `PoolEngine` undefined).

- [ ] **Step 3: Write the implementation**

`Sources/SwiftStarAppKit/PoolEngine.swift`:
```swift
import Foundation
import SwiftStarKit

/// The app-side pool engine (D1/D2): spawns `--subagent-pool`, reads the
/// `.kv` rendered text inference-free (D6), and the deterministic loaders the
/// packet-maker uses (D5). No SwiftUI; integration-tier (real Process/files).
public enum PoolEngine {
    /// The engine argv for a pooled spawn: the existing agent argv plus
    /// `--subagent-pool N` (one orchestrator + N-1 worker sessions).
    public static func argv(settings: AgentSettings, workers: Int) -> [String] {
        AgentCommand.argv(settings: settings) + ["--subagent-pool", String(workers)]
    }

    /// Read the rendered conversation from a session `.kv` file (D6): the full
    /// text lives as plain UTF-8 behind a fixed 48-byte header. No model, no
    /// engine. Throws on a missing file or a sub-48-byte header.
    public static func readKVText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard data.count > 48 else { throw PoolEngineError.kvTooShort(data.count) }
        let body = data.dropFirst(48)
        return String(decoding: body, as: UTF8.self)
    }

    /// The deterministic file listing (D5): a sorted list of the repo's
    /// tracked files, via `git ls-files` (falls back to an empty list on a
    /// non-repo, which the packet-maker then treats as "no file list").
    public static func listFiles(in repo: URL) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "ls-files"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return [] }
        guard p.terminationStatus == 0,
              let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return [] }
        return out.split(separator: "\n").map(String.init).sorted()
    }
}

public enum PoolEngineError: Error, Equatable {
    case kvTooShort(Int)
}
```

- [ ] **Step 4: Run, confirm GREEN** (`SWIFTSTAR_INTEGRATION=1 swift test --filter PoolEngineTests`).

- [ ] **Step 5: Commit** `P11: PoolEngine spawn + .kv loader + listFiles`.

---

### Task 8: The `--subagent-pool` C patch (divergence #11)

**Files:**
- Modify: `external/ds4/ds4_agent.c` (and the fork ledger `external/ds4/docs/fork-ledger.md`).
- Test: C unit tests in `ds4_agent.c` (`test_agent_*`); a golden recapture.

**Interfaces:**
- Consumes: the existing session primitives (`ds4_session_new`, `ds4_session_rewind`, `ds4_session_save_payload`/`load_snapshot`, `ds4_session_common_prefix`, `ds4_session_eval`) and the P9 `--host-tools` wire.
- Produces: `--subagent-pool N` (default 1 = the single-worker behavior byte-for-byte); a `worker` field on every `--json-events` event (absent when N==1, preserving the pre-P11 wire exactly); one engine, N sessions, exactly one generating at a time.

- [ ] **Step 1: Read the three anchor regions before editing.** `agent_config` and `agent_worker` (`ds4_agent.c` ~75–207); `parse_options` (`ds4_agent.c` ~755–870, where `--host-tools` is parsed); the event emitters (`agent_emit_event_str`/`agent_publish` and the `hello`/`status`/`ready` emitters, ~420–520 and ~4852); the single `agent_completion_worker` global (~414) and the non-interactive main loop (~55373–55414). Record line numbers in the commit message.

- [ ] **Step 2: Add the config flag and parse it.** In `agent_config`, add `int num_workers;` (default 1). In `parse_options`, add:
```c
        } else if (!strcmp(arg, "--subagent-pool")) {
            c.num_workers = atoi(need_arg(&i, argc, argv, arg));
            if (c.num_workers < 1) c.num_workers = 1;
```
Mirror the `--json-events` gate: `--subagent-pool` with `N > 1` requires `--json-events` (the worker field is a json-events field); refuse loudly otherwise (the `--host-tools requires --json-events` precedent at ~963).

- [ ] **Step 3: Emit the `worker` field + advertise the pool cap.** Add `int worker_id;` to `agent_worker`. In the shared event emitter, append `"worker":<id>` to every event object **only when `cfg->num_workers > 1`** (so `N == 1` output is byte-identical to pre-P11 — the recapture in Step 6 proves it). Add `"pool"` to the `hello` `caps` array iff `num_workers > 1`, so the app can *detect* pool support instead of guessing (this is also how the use-it-or-lose-it flag-gate knows it can switch off). Add C tests `test_agent_emit_hello_worker_omitted_when_single`, `test_agent_emit_event_carries_worker_id`, `test_agent_hello_advertises_pool_cap_when_multi`.

- [ ] **Step 4: Refactor to ONE worker thread multiplexing N sessions.** Keep the single completion worker thread; replace the singleton `agent_worker` with `agent_worker *workers` (size `num_workers`), each holding its own `ds4_session` created at startup from the shared `engine`. **Do not add per-worker threads**: the serialized family means one generation at a time anyway, and N threads + a pool mutex is deadlock surface for zero win (and moves N==1 further from byte-identical). Each `workers[i]` gets `worker_id = i` and **its own small ctx_size at session creation** (D8: the orchestrator keeps `-c`; worker sessions are created at the packet's budget-mapped ctx, so scratch is ~1.5 GB at 4k, not 6.1 GB). Add a `generating_worker` pointer plus `assert(generating_worker == NULL)` at each turn entry/exit — the D1 serialization invariant — and a C test that runs two turns and checks the invariant via a debug counter.

- [ ] **Step 5: Route stdin by worker (the pre-fixed contract, D1).** Inbound prompts are `PoolPrompt`-encoded: `{"t":"prompt","worker":<id>,"s":"..."}` addresses worker `<id>`; a bare line addresses worker 0 (so `N == 1` is byte-identical). `tool_result` lines carry **no worker tag**: because exactly one session generates at a time, at most one `tool_request` is outstanding, so the result routes unambiguously to the generating worker — enforce this with `assert(generating_worker != NULL)` before consuming a `tool_result`. Add C tests `test_agent_pool_prompt_worker_route` and `test_agent_pool_tool_result_routes_to_generating_worker`.

- [ ] **Step 6: Rebuild + recapture (standing rule).** `just engine`, then run `swiftstar-drive` to recapture `golden.ndjson` at the new SHA with the **default** argv (no `--subagent-pool`, so `N == 1`), and capture a second, small **pool** capture (two workers) that becomes the regenerated `fixtures/agent/pool.ndjson` — retiring Task 6's hand-authored stand-in. Regenerate the fake from both. Confirm the single-session recapture is identical **modulo the volatile fields** — `ts`, `prefill_tps`, `gen_tps`, `power`, and the `status` prefill counters (extend the existing recapture normalizer first if it does not already strip these). A diff on any *other* field is a semantic collision, not a clean rebase.

- [ ] **Step 7: Commit** `P11: --subagent-pool C patch (divergence #11) + recapture`.

> **Risk note (Task 8 is the schedule risk):** the change touches the worker lifecycle, the emitters, and the main loop — the same regions the patch set already instruments (fork-ledger standing rule). Split it into two commits, both behind the flag, neither regressing N==1: (a) the flag + `worker` field emission + `pool` cap for N>1 (additive, zero-behavior-change at N==1, recapture-green), then (b) the N-session multiplex on the single worker thread. **Stop and report if the recapture at (a) differs beyond the volatile fields named in Step 6** — that is a semantic collision, not a clean rebase.

---

### Task 9: App wiring — orchestrator dispatch → queue → worker turn → receipt injection

**Files:**
- Modify: `Sources/SwiftStar/AgentController.swift` (add a `PoolController`-shaped extension or a new `PoolController.swift`).
- Modify: `Sources/SwiftStar/DispatchView.swift` (surface the pool).
- Modify: `Sources/SwiftStarKit/ToolCallbackResponder.swift` (add `dispatch` to the host-executed tool set — it is a host-tool, D3).

**Interfaces:**
- Consumes: `PoolScheduler`, `PoolEngine`, `WorktreeDispatcher`, `ToolCallbackResponder`, `ContextAssembly`, `DispatchReceipt`, `RollingDigest`, `PoolPrompt`.
- Produces: the orchestrator loop — on a `.toolRequest` named `dispatch`, assemble the packet's prepared context (D5: `ContextAssembly.assemble(objective:digest:loaded:deterministicAdaptation(...))`), enqueue it (the scheduler assigns the worker id); run the worker's turn in the pooled engine inside a disposable worktree (D1+D4: `WorktreeDispatcher` with a turn-runner that drives worker N, not a fresh spawn); on completion, fold the outcome into a `DispatchReceipt`, `RollingDigestReducer.record` it, and enqueue `receipt.injectionPrompt()` for the orchestrator's next turn.

- [ ] **Step 1: Add `dispatch` to the responder's host-tool set.** In `ToolCallbackResponder`, the `dispatch` tool is a host-tool (D3): `consent` refuses it unless the params carry a non-empty `taskText` and a `writableFiles` list; `respond` returns `ok:true` immediately. The worker id comes from the scheduler, not the responder — the controller enqueues first, then formats the answer "dispatched as worker N" itself (the responder's `s` is a placeholder the controller overwrites).

- [ ] **Step 2: Write the failing tests** in `ToolCallbackResponderTests` — `dispatchProceedsWhenWellFormed` / `dispatchRefusedWithoutTaskText` (binding rule 4: refusal has a sibling success).

- [ ] **Step 3: Implement** the `dispatch` branch in `respond` (pure) + the controller's enqueue: on the `toolRequest` named `dispatch`, the controller builds the packet via `ContextAssembly.assemble(objective: params.taskText, digest: rollingDigest, loaded: loadedRoadmap, adaptation: ContextAssembly.deterministicAdaptation(objective:digest:loaded:implementer:))`, enqueues it (`PoolScheduler.apply(.enqueue)`), reads back the assigned `WorkerId`, and answers `ok:true` "dispatched as worker N".

- [ ] **Step 4: The worker turn + receipt injection.** On the orchestrator's turn-end `ready`, drain queued workers (`PoolScheduler.nextWorker`); run each via `WorktreeDispatcher.dispatch` whose `attempt` closure drives **worker N of the pooled engine** (`PoolPrompt(worker: N, text: preparedTaskText).encode()` on stdin, draining worker-N-tagged events) instead of spawning a fresh process (D1). Fold the `DispatchOutcome` into a `DispatchReceipt` (`candidate` ref or `receipt` reason), `RollingDigestReducer.record` it, `PoolScheduler.apply(.workerFinished/.workerFailed)`, and enqueue the combined `injectionPrompt()` for the orchestrator's next turn (D4).

- [ ] **Step 5: The enqueue → run → receipt-inject integration test.** Against the fake pool engine (Task 6's fixture + argv): enqueue a packet, run the worker turn, and assert the receipt is recorded in the digest and queued for injection — the spec's integration tier, explicitly.

- [ ] **Step 6: Run `swift build`, `just test`, `just integration`; confirm GREEN.**

- [ ] **Step 7: Commit** `P11: orchestrator dispatch loop + context assembly + receipt injection`.

---

### Task 10: The measurement gate (live tier)

**Files:**
- Create: `Tools/p11-gate.sh` (or a `swiftstar-drive` mode) that runs the envelope (D11) against the real engine and weights.

**Interfaces:**
- Consumes: `EnvelopeMath`, the real `ds4-agent` with `--subagent-pool`.
- Produces: the three gate reports — overhead ratio, sensitivity envelope, instrumentation — written to a committed `docs/superpowers/research/2026-08-23-p11-verification-record.md`.

- [ ] **Step 1: Commit the canonical packet corpus** under `fixtures/gate/` (the packet set the headline ratio is computed on — named, so the number is reproducible).

- [ ] **Step 2: Write the driver** that, for each `PacketPerturbation` (using `apply(to:)` and `packetCountSweepCounts` from Task 5), builds the packet set, runs the deep-context baseline (one 131k) and the pooled shallow-context runs (8 × 16k, sequential — **including the orchestrator's own prefill+decode, not just 8 isolated workers**), applies the fixed retry policy (one retry on a budget/validation receipt, then surface), and records seconds, tokens-evaluated, tokens-nominal, and peak resident.

- [ ] **Step 3: Run it** (live tier, never CI). **Size it honestly**: one 131k prefill is ~35 min alone, so the full envelope is ~hours — schedule it, don't call it "minutes." Record the numbers and the exact commands in the verification record (binding rule 1: carry the command, not the number).

- [ ] **Step 4: Commit** `P11: measurement gate — envelope report + verification record`.

> **Gate note:** the gate is the phase's **hard exit criterion** — the phase does not close until the envelope is measured. There is no "record as pending" path; if the hardware is unavailable, the phase stays open and the plan says so, rather than asserting a number that was not measured.

---

### Task 11: Close the phase

**Files:**
- Modify: `ROADMAP.md` (P11 complete, P12 next; concept budget gains **rolling digest** and **context assembly**; the P11 dependency bullet moves to prior work).
- Modify: `README.md` (Status: P0–P11 complete).
- Modify: `docs/superpowers/research/2026-08-23-p11-verification-record.md` (finalize).

- [ ] **Step 1: `just test` + `just integration` + the engine suite (`make -C external/ds4 ds4_agent_test && external/ds4/ds4_agent_test`) all green.**

- [ ] **Step 2: Update ROADMAP/README; record the evidence floor (the pool capture parses and routes; a worker-tagged capture parses; a refusal receipt has a sibling success) and the use-it-or-lose-it commitment (divergence #11 is flag-gated off or reverted if A-routing has not landed within one phase).**

- [ ] **Step 3: Commit** `P11: close — roadmap, concept budget, verification record`.

---

## Self-review

**Spec coverage:** D1→Tasks 1,2,7,8 (inbound `PoolPrompt` in Task 1; N bound + per-worker ctx in Task 8); D2→Tasks 6,8; D3→Task 9; D4→Tasks 1,9; D5→Tasks 4,9 (assembled in the dispatch loop); D6→Tasks 3,7 (`.kv` backing is the digest-reconstruction consumer); D7→Task 4 (deterministic v1; model trip deferred); D8→Task 8 (per-worker ctx at session creation); D9→Tasks 3,9 (digest `summary()` is the ledger); D10→Tasks 1,9 (executor discriminator reserved on `DispatchReceipt`); D11→Tasks 5,10 (perturbation constructors in Kit; hard exit).

**Placeholder scan:** no TBD/TODO; the C patch (Task 8) names exact anchor regions and splits on a recapture gate rather than hand-waving.

**Type consistency:** `WorkerId` (Task 1) is the id type throughout (`PoolScheduler`, `RollingDigest`, `DispatchReceipt`); `DispatchReceipt` is produced by Task 1 and consumed by Tasks 2/3/9; `RollingDigest.summary()` is consumed by `ContextAssembly` (Task 4) and the compaction ledger (D9); `EnvelopeMath.ceiling`/`overheadRatio` are consumed by the gate (Task 10).

**Known deviation, stated:** the fake in Task 6 is hand-authored against the typed contract — a deliberate D2 stand-in, retired by the Task 8 recapture (the fake is then regenerated from a committed capture, restoring the "never hand-authored" rule).
