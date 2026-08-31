import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit
import Darwin

/// The agent child's lifecycle + turn state. Unlike the server's `Supervisor`
/// state machine, the agent wire carries no explicit turn-end event: the
/// turn-end `ready` is the single gate (D6) — `status.state → idle` is a
/// precursor, not the gate (see consumeWire).
@MainActor
@Observable
final class AgentController {
    /// Single reachable controller, so the app delegate can stop the agent on
    /// quit even though the controller is owned by MainView (mirrors the
    /// Chat surface's EngineController.shared pattern, retired 2026-08-26).
    static weak var shared: AgentController?

    enum AgentState: Equatable {
        case stopped
        case starting
        case ready       // handshake seen, idle (waiting for or between turns)
        case generating  // a turn is in flight
        case stopping
        case failed(String)
    }

    private(set) var state: AgentState = .stopped
    var transcript = AgentTranscript()
    private(set) var stderrTail: [String] = []
    /// Latest wire `status` snapshot, for the bottom status bar's readout
    /// (activity line + context ring). nil before the first status event.
    private(set) var lastStatus: StatusSnapshot?
    /// Ratcheted prompt/decode rates (`AgentStatusText.ratchet`): the wire
    /// reports only one of prefill/gen as nonzero per event, so a zero must
    /// never blank a live rate (the DS4 Control 2989d2c fix).
    private(set) var lastPrefillTPS: Double = 0
    private(set) var lastGenTPS: Double = 0
    /// The engine's own startup memory plan (`ready.planned_bytes`), for the
    /// bottom bar's memory ring denominator.
    private(set) var lastPlannedBytes: Int64?
    /// The model (`modelPath` last component) the plan in `lastPlannedBytes`
    /// was measured for; the memory ring only uses the denominator when it
    /// matches the running model (mirrors the Chat surface's EngineController
    /// stale-plan guard, retired 2026-08-26).
    private(set) var lastPlannedModel: String?
    /// The agent process's resident footprint, polled once a second while the
    /// agent is up; nil when the process is gone.
    private(set) var lastFootprintBytes: Int64?

    private let memoryCollector = ProcessStatsCollector()
    /// Mutated only on MainActor; the nonisolated `deinit` reads it to cancel
    /// the poll. `@ObservationIgnored` because nothing observes a Task handle —
    /// which is also what lets it be `nonisolated`: the `@Observable` macro
    /// cannot apply `nonisolated` to a *tracked* stored property.
    @ObservationIgnored private var memoryTask: Task<Void, Never>?
    /// Tails the engine's trace side-channel so compaction becomes a persistent
    /// transcript row instead of only a Diagnostics finding.
    @ObservationIgnored private var traceTask: Task<Void, Never>?
    /// The in-flight turn's decode work, accumulated per generation segment on
    /// the engine's own clock. Reset at each turn's start and end.

    /// The running agent's pid, if the child process is alive.
    var runningPid: pid_t? { process?.processIdentifier }
    /// The last completed turn's outcome record (D12); the full trail goes to
    /// the SWIFTSTAR_LOG file. Persistence beyond that is P9/P10 work.
    private(set) var lastTurnOutcome: TurnOutcome?
    /// Finished orchestrator turns this process has seen. The signal Diagnostics
    /// re-analyzes on: the session's capture only becomes analyzable once a turn
    /// has been written to it, and a pid change alone fires too early (the wire
    /// is empty and the engine has not opened its trace yet).
    private(set) var completedTurns = 0
    /// The current session's outcomes.ndjson (nil when capture is disabled):
    /// one appended `TurnOutcome` line per finished turn (P21 — captures become
    /// self-contained evidence the CLI reads back).
    private var outcomesURL: URL?
    var settings: AgentSettings
    /// P11 (D1): the pool scheduler state — enqueued workers, the running
    /// worker, and receipts awaiting delivery back into the orchestrator.
    var poolState = PoolState(workerCapacity: SubagentPoolSize.workerCapacity(AgentController.poolSize()))
    /// P21: the Metrics tab's live source — fired on each status/ready wire
    /// event (MainActor; consumeWire). A single observer slot (Metrics owns it;
    /// the fixture replay is only the pre-spawn placeholder).
    var onTelemetry: ((AgentEvent) -> Void)?
    /// P11 (D6): the rolling digest — the objective-independent reduced form
    /// of the session, maintained incrementally as host facts arrive.
    var rollingDigest = RollingDigest()

    /// Mutated only on MainActor; the nonisolated `deinit` terminates it. No
    /// isolation opt-out is needed on this toolchain (the compiler reports
    /// `nonisolated(unsafe)` here as having no effect), and plain `nonisolated`
    /// is illegal on a mutable stored property. Must stay observation-TRACKED:
    /// `runningPid` is computed over it, and `MainView` re-points
    /// Metrics/Diagnostics when that changes.
    var process: Process?
    /// The headless single-turn loop (eval-cli task 2): owns the actual
    /// `Process`/pipes/wire-parsing/tool-callback answering that used to live
    /// directly in this type's `consumeWire`/`send`/`writeToolResult`/
    /// `interrupt`/`stopAgent`. This type now keeps only view state
    /// (`transcript`, `state`, the telemetry readout) and consumes the
    /// session's callbacks — see `startAgent`. A restart replaces this with a
    /// brand-new session (mirrors the old "a restart is a fresh wire"
    /// invariant); `AgentPoolTurnLoop.swift` (untouched by this task — its own
    /// header says its handles cannot leave the app target) still reads
    /// `process` directly for worker prompts until a later task seams the
    /// pool loop behind this same session.
    // Not `private`: `AgentPoolTurnLoop.swift` (an extension in another file)
    // calls `agentSession?.dispatch(...)` to write a worker's `PoolPrompt` —
    // eval-cli task 3's seam (the same reason `process`/`poolState`/
    // `workerTurn` are already not `private`). Not widened to `internal`
    // beyond this file's module boundary either.
    var agentSession: AgentSession?
    /// The capabilities the engine's `hello` advertised (P23, D3): the app
    /// records what was advertised so it can gate outbound feature fields.
    /// `"think_override"` gates per-turn think sends; `/quick` is refused
    /// without it. Reset per spawn; now populated from `AgentSession`'s
    /// `onEvent` callback (`.hello`'s own carried capabilities) rather than a
    /// parser this type no longer owns.
    private(set) var advertisedCaps: Set<String> = []
    private var startupTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var stopEscalationTask: Task<Void, Never>?
    @ObservationIgnored private var orchestratorToolTask: Task<ToolCallbackResponse, Never>?
    var generation = 0
    /// Status samples for the active orchestrator turn. `TurnSpan` turns these
    /// into elapsed work time without counting the user's typing time. (D12;
    /// the outcome builder itself moved into `AgentSession` with the turn
    /// loop — this stays app-side because it feeds `TurnSummary`'s
    /// `elapsedSeconds`, a view-facing figure.)
    private var turnStatuses: [StatusSnapshot] = []
    // P11 (D4) worker-turn state: everything that exists only while one
    // worker turn is in flight, consolidated into one value (item 1 of the
    // P22 cleanup) so there is exactly one place that creates/clears it —
    // previously six hand-synced properties reset by hand in three places
    // (the restart reset below, `failActiveWorker`, `finishWorkerTurn`).
    // Wraps SwiftStarKit's pure `WorkerTurnState` (the testable id/packet/
    // consult-membership bookkeeping) together with the app-only live
    // handles that cannot leave the app target: the disposable worktree (its
    // file mutations land here, never in the caller's tree — the P10
    // isolation guarantee), the outcome builder, and the watchdog task.
    // Deliberately NOT @ObservationIgnored (unlike memoryTask/process, whose
    // nonisolated deinit access forces that opt-out): `isConsulting` below
    // reads it, and Observation only notifies a view when the property it
    // read is tracked. Same treatment as `outcomeBuilder`, which is mutated
    // just as often (per wire event) and stays tracked.
    var workerTurn = ActiveWorkerTurn()
    /// View-facing "an interrupt is in flight" flag. `AgentSession` tracks its
    /// OWN `sentInterrupt` privately (it needs it to label the outcome record
    /// `.interrupt` when the wire's own stop_reason says something else); this
    /// is the separate, app-side signal `AgentView`/`AgentPoolTurnLoop` read
    /// to disable the interrupt affordance and gate a worker's post-interrupt
    /// tool answers. The orchestrator's own tool-call budget now lives inside
    /// `AgentSession` (`toolBudget`) since tool-request admission moved there.
    private(set) var interruptPending = false
    var buildSHA = "unknown"
    private let logHandle: FileHandle?

    init(settings: AgentSettings = AgentController.defaultSettings()) {
        self.settings = settings
        if let logPath = ProcessInfo.processInfo.environment["SWIFTSTAR_LOG"] {
            let url = URL(fileURLWithPath: logPath)
            if !FileManager.default.fileExists(atPath: logPath) {
                FileManager.default.createFile(atPath: logPath, contents: nil)
            }
            self.logHandle = try? FileHandle(forWritingTo: url)
        } else {
            self.logHandle = nil
        }
        AgentController.shared = self
    }

    isolated deinit {
        // `isolated deinit` (SE-0371) runs this on the MainActor, which is what
        // lets `process`/`memoryTask` drop their `nonisolated(unsafe)` opt-outs
        // and be genuinely checked again.
        process?.terminate()
        memoryTask?.cancel()
        traceTask?.cancel()
        stopEscalationTask?.cancel()
        orchestratorToolTask?.cancel()
        try? logHandle?.close()
    }

    var canSend: Bool { state == .ready }
    var isGenerating: Bool { state == .generating }
    /// The agent is up and serving — the state in which the bottom bar's
    /// telemetry readout (rates, rings) is meaningful.
    var isUp: Bool { state == .ready || state == .generating }
    /// A spawn refusal landed `.failed` — no process is running. The
    /// toolbar's model menu offers a direct start from here so picking a
    /// different (feasible) model has a recovery path outside Settings
    /// (P22 GLM review fix: `.failed` was otherwise a main-window dead end —
    /// `startIfNeeded()` only fires once for `.stopped`, and "Apply this
    /// model" is hidden because `isUp` is false).
    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
    /// True only while a `/chat` consult worker is running (item 2 of the
    /// P22 cleanup). `consult()`'s worker turn runs via `drainQueuedWorkers()`
    /// without ever touching `state` — it stays `.ready` for the whole turn,
    /// on purpose: `sendConsulted`'s delivery requires `canSend`, `interrupt()`
    /// leaves the main controller in `.ready`, because `sendConsulted`'s
    /// delivery requires `canSend` and `ModelMenu` must remain disabled while
    /// the worker is running. This separate signal lets AgentView show a
    /// distinct "consulting" affordance without lying about the main engine
    /// state.
    var isConsulting: Bool {
        guard state == .ready else { return false }
        guard let id = workerTurn.activeId else { return false }
        return workerTurn.isConsult(id)
    }

    /// The model used when nothing else resolves. Laguna S is the app's default
    /// but has no `Variant`, so its path is a literal — and an absolute one, in
    /// a developer's home directory, compiled into the binary. `SWIFTSTAR_MODEL`
    /// overrides it; giving Laguna S a real Variant (P22) retires it.
    ///
    /// Item 5b (P22 cleanup): the literal now lives in
    /// `SwiftStarKit.AgentDefaultSettings.defaultModelFallback(environment:)`
    /// (unit-testable there); this stays the same externally-visible
    /// `static let` so `AgentView`'s `ModelMenu` (the other call site) needs
    /// no change.
    static let defaultModelFallback = AgentDefaultSettings.defaultModelFallback(
        environment: ProcessInfo.processInfo.environment)

    /// The effective `selectedVariantID` for both model resolution
    /// (`defaultSettings()`, inside `AgentDefaultSettings.resolve`) and
    /// pre-spawn admission (`startAgent()`) — the stored choice, or Laguna S's
    /// id when nothing was ever configured (no variant, no legacy `modelPath`,
    /// no `SWIFTSTAR_MODEL` override). A single pure function so the two call
    /// sites can't disagree about which variant (if any) is in play — the
    /// failure mode that would otherwise let `defaultSettings()` resolve
    /// Laguna S's file while `startAgent()`'s gate still saw "no variant
    /// selected" and skipped admission entirely. Delegates to
    /// `SwiftStarKit.AgentDefaultSettings.effectiveSelectedVariantID` (unit-
    /// tested there) with the real `UserDefaults`/environment.
    private static func effectiveSelectedVariantID() -> String? {
        AgentDefaultSettings.effectiveSelectedVariantID(
            defaults: .standard, environment: ProcessInfo.processInfo.environment)
    }

    /// Item 5b (P22 cleanup): a thin wrapper over
    /// `SwiftStarKit.AgentDefaultSettings.resolve` (the pure logic, unit-
    /// tested there — `Sources/SwiftStar` has no test target). Supplies the
    /// three implicit inputs the pure function needs explicitly:
    /// `UserDefaults.standard`, the real process environment, and this app's
    /// own checkout-anchored `projectRoot()` (Bundle.main-dependent, so it
    /// stays here rather than becoming a fourth pure-function parameter that
    /// would just re-implement the same anchoring inside SwiftStarKit).
    static func defaultSettings() -> AgentSettings {
        AgentDefaultSettings.resolve(
            defaults: .standard,
            environment: ProcessInfo.processInfo.environment,
            projectRoot: AgentController.projectRoot())
    }

    /// The checkout containing the running executable, if any: anchored to
    /// the binary's location (`.build/debug/SwiftStar` → the repo), never the
    /// launch cwd — a cwd-derived default would confine the agent to whatever
    /// repo the app happened to be launched from. nil outside a checkout (a
    /// shipped .app) → the workspace falls back to home.
    private static func projectRoot() -> URL? {
        let anchor = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return ProjectRoot.locate(anchor: anchor)
    }

    /// The live-session capture base: the checkout's `captures/live/<ts>` when
    /// launched from a repo, else `~/Library/Application Support/SwiftStar`.
    /// Timestamped per spawn (matches the drive's `yyyyMMdd-HHmmss` convention)
    /// so each session is its own directory, readable after the fact.
    static func captureDirectory() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let name = df.string(from: Date())
        let base: URL
        if let repo = projectRoot() {
            base = repo
        } else {
            base = URL.applicationSupportDirectory.appendingPathComponent("SwiftStar")
        }
        return base.appendingPathComponent("captures/live/\(name)", isDirectory: true)
    }

    // `renderLiveProvenance`/`repoDirty`/`makeSpawnRecord` moved into
    // `AgentSession` (eval-cli task 2, `AgentSession.start()`): it now owns
    // both the `SpawnRecord` assembly and the `provenance.md` render, since it
    // owns the spawn itself.

    func startIfNeeded() {
        if state == .stopped { startAgent() }
    }

    /// The current session's capture URLs (nil when capture is disabled or no
    /// session has started): the wire + trace for Diagnostics' live analysis.
    var liveCaptureURLs: (wire: URL, trace: URL)? {
        guard let tracePath = settings.tracePath else { return nil }
        let wire = tracePath.deletingLastPathComponent().appendingPathComponent("wire.ndjson")
        return (wire, tracePath)
    }

    /// Read complete lines from the append-only trace without doing file I/O on
    /// the MainActor. The trace may not exist until the engine opens it, so the
    /// tailer retries the open and keeps the file handle at its current offset.
    private func startTracePolling(path: URL, generation: Int) {
        traceTask?.cancel()
        traceTask = Task.detached(priority: .utility) { [weak self] in
            var handle: FileHandle?
            var pending = Data()
            var parser = TraceParser()
            var didInitialSeek = false
            while !Task.isCancelled {
                if handle == nil {
                    handle = try? FileHandle(forReadingFrom: path)
                    if handle != nil, !didInitialSeek {
                        // A same-second restart can reuse an append-only
                        // capture directory. Start at this spawn's live tail,
                        // otherwise old compactions would be replayed.
                        _ = try? handle?.seekToEnd()
                        didInitialSeek = true
                    }
                }
                if let handle,
                   let chunk = try? handle.read(upToCount: 64 * 1024),
                   !chunk.isEmpty {
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 0x0A) {
                        let line = pending.prefix(upTo: newline)
                        pending.removeSubrange(...newline)
                        let text = String(decoding: line, as: UTF8.self)
                        if let event = parser.feed(text) {
                            await self?.consumeTrace(event, generation: generation)
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
            try? handle?.close()
        }
    }

    private func consumeTrace(_ event: TraceEvent, generation: Int) {
        guard generation == self.generation else { return }
        guard case .compaction(let reason, let old, let new, let tailStart, let tail) = event else { return }
        transcript.append(.compaction(CompactionSummary(
            reason: reason, oldTokens: old, newTokens: new,
            tailStart: tailStart, tailTokens: tail, observedAt: Date())))
    }

    /// Persist one finished turn's outcome as an appended line in the session's
    /// outcomes.ndjson (P21): captures become self-contained evidence. Item 6
    /// (P22 cleanup): routed through `SafeAppendFile` — a fresh one per call
    /// (this fires once per turn, not worth holding a handle open for the
    /// whole session), which also means it is safe even if the upfront
    /// `startAgent()` create step below were ever removed (construction
    /// itself guarantees the file exists).
    private func appendOutcome(_ outcome: TurnOutcome) {
        guard let url = outcomesURL,
              let data = try? JSONEncoder().encode(outcome) else { return }
        SafeAppendFile(path: url.path).append(Data((String(decoding: data, as: UTF8.self) + "\n").utf8))
    }

    /// The configured subagent-pool size (one orchestrator + N−1 workers),
    /// clamped; the single source of truth for both the spawn argv and the
    /// scheduler's worker capacity (they must agree or the engine hosts fewer
    /// sessions than the scheduler addresses).
    private static func poolSize() -> Int {
        let raw = UserDefaults.standard.integer(forKey: "subagentPoolSize")
        return SubagentPoolSize.clamp(raw == 0 ? 2 : raw)
    }

    /// The admission result for the staged variant at the given context, or
    /// nil when no variant is staged (a custom/unverified model path — like a
    /// fresh launch, no gate exists for it). Shared by `startAgent()` and
    /// `applyModelSelection()` so the two call sites cannot drift about which
    /// variant is in play or which live memory facts back the gate (P22 D2;
    /// the failure mode `effectiveSelectedVariantID`'s own doc warns about).
    private static func admitStagedVariant(contextSize: Int) -> VariantAdmission? {
        guard let variant = VariantResolver.resolveVariant(
            selectedVariantID: AgentController.effectiveSelectedVariantID()) else { return nil }
        return VariantGate.admit(
            variant, contextSize: contextSize,
            availableBytes: VariantAdmissionSource.availableBytes(),
            wiredLimitAdvisoryBytes: VariantAdmissionSource.wiredLimitAdvisoryBytes())
    }

    /// `pinnedSettings` locks the spawn to a target already resolved and
    /// admitted by a caller (P22 `applyModelSelection`) instead of
    /// re-resolving from live `UserDefaults`/env — without it, a selection
    /// change during `restartAgent()`'s async stop window could spawn a
    /// different target than the one that justified stopping the previous
    /// session. The admission gate still re-runs (below) so a memory fact
    /// that changed during the stop window is still caught.
    func startAgent(pinnedSettings: AgentSettings? = nil) {
        switch state {
        case .stopped, .failed: break
        default: return
        }
        // P13: refresh settings so a selected variant applies (mirrors the
        // Chat surface's EngineController, retired 2026-08-26), then admit it
        // before spawn (C1).
        settings = pinnedSettings ?? AgentController.defaultSettings()
        switch AgentController.admitStagedVariant(contextSize: settings.contextSize) {
        case .admitted, nil:
            break
        case .contractMismatch(let mismatches):
            state = .failed(mismatches.map(\.message).joined(separator: "\n"))
            log("variant refusal: \(mismatches)")
            return
        case .infeasible(let reason):
            state = .failed(reason.message)
            log("feasibility refusal: \(reason.message)")
            return
        }
        let binary = AgentCommand.binaryPath(settings: settings)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            state = .failed("agent binary missing at \(binary.path)")
            return
        }
        state = .starting
        generation += 1
        let gen = generation
        // A restart is a fresh wire — a brand-new `AgentSession` below, not a
        // reused one (mirrors the old "reset the parser" invariant). The
        // transcript is deliberately kept (history, like the Chat surface's
        // EngineController, retired 2026-08-26); stderrTail is reset so a
        // failure message never pairs a new session with a stale tail.
        advertisedCaps = []
        stderrTail = []
        stopEscalationTask?.cancel()
        stopEscalationTask = nil
        orchestratorToolTask?.cancel()
        orchestratorToolTask = nil
        interruptPending = false
        lastStatus = nil
        lastPrefillTPS = 0
        lastGenTPS = 0
        lastPlannedBytes = nil
        lastPlannedModel = nil
        lastFootprintBytes = nil
        // A restart is a fresh engine = a fresh pool: stale pending workers and
        // consult bookkeeping must not survive into the new session.
        poolState = PoolState(workerCapacity: SubagentPoolSize.workerCapacity(AgentController.poolSize()))
        workerTurn.cancelToolTask()
        workerTurn.watchdog?.cancel()
        workerTurn = ActiveWorkerTurn()
        traceTask?.cancel()
        traceTask = nil
        turnStatuses = []
        // P24.1 (D3/D5): the pool worker executor is a process-lifetime
        // `static let` (still used by `AgentPoolTurnLoop.swift`), so it cannot
        // take the context size at construction, and its `more` continuations
        // would otherwise outlive the session that made them. `AgentSession`
        // owns its OWN executor instance for the orchestrator turn (below) —
        // deliberately not shared with this static, so a later multi-session
        // caller (the eval CLI) cannot leak one session's read-cache state
        // into another's.
        Self.hostToolExecutor.setContextSize(settings.contextSize)
        Self.hostToolExecutor.resetReadState()
        // D12: the build identification is resolved once per spawn (the
        // submodule SHA — the same fact the capture provenance records, and
        // what `AgentPoolTurnLoop.swift` reads for a worker's own record).
        buildSHA = AgentController.submoduleSHA(settings.engineDir)

        // Live session capture (P7's deferred "live wiring", scoped 2026-08-26):
        // persist the agent's wire + trace + stderr so the session can be read
        // from disk — analysing prompts, tool calls, context — without
        // SWIFTSTAR_LOG. `AgentSession.start()` owns writing the wire/stderr
        // tees and `provenance.md` (binding rule 5: on disk before this
        // type's callbacks ever see a line) — but only when told to.
        //
        // Regression fix (eval-cli task 3): Task 2 made capture unconditional
        // — `AgentSession`'s contract had no toggle, so a user who had
        // switched off "Capture sessions to captures/live/" in Settings
        // (`sessionCaptureEnabled`, default true) got every session written
        // to disk anyway. `AgentSession.init(captureEnabled:)` restores the
        // toggle's effect; `outcomesURL`/`settings.tracePath` stay nil when
        // it's off, so `appendOutcome`/the engine's own `--trace` side-channel
        // are both skipped too — capture is all-or-nothing per session, not a
        // wire tee with a still-live trace file.
        let sessionCaptureEnabled = UserDefaults.standard.object(forKey: "sessionCaptureEnabled") == nil
            ? true : UserDefaults.standard.bool(forKey: "sessionCaptureEnabled")
        pruneStaleCaptures()  // retention policy: see the AgentController extension below
        let captureDir = Self.captureDirectory()
        if sessionCaptureEnabled {
            outcomesURL = captureDir.appendingPathComponent("outcomes.ndjson")
            // The engine's OWN `--trace` side-channel (independent of
            // `AgentSession`'s wire/stderr tee — see `AgentCommand.argv`)
            // still needs a path threaded through `settings` before argv is
            // built; `liveCaptureURLs` (Diagnostics' live-analysis source)
            // reads it back.
            settings.tracePath = captureDir.appendingPathComponent("agent.trace")
        } else {
            outcomesURL = nil
            settings.tracePath = nil
        }

        // P8: stage the Superpowers skills into the workspace (progressive
        // disclosure, D2/D3) and pass the deterministic bootstrap index via
        // -sys (D1/D4). A staging failure is non-fatal — the bootstrap still
        // loads and names skills the agent cannot `read` (the confined `read`
        // refuses a missing file, so no fabrication).
        let skillsDir = AgentController.resolveSkillsDir()
        do {
            _ = try SkillStager.stage(skillsDir: skillsDir, into: settings.workspace)
        } catch {
            log("skill staging failed (non-fatal): \(error)")
        }
        // P20 (D4): the dispatch-preference rule is appended after the skills
        // bootstrap so every agent spawn (agent mode and /orchestrate alike)
        // carries it — it is the always-on counterpart to the orchestrate
        // directive's dispatch guidance.
        settings.systemPrompt = SuperpowersBootstrap.build(skillsDir: skillsDir).indexPrompt
            + "\n\n" + DispatchPreferenceRule.text

        // Regression fix (eval-cli task 3): pass the SAME total pool value
        // (`AgentController.poolSize()`, clamped) that `poolState`'s own
        // `workerCapacity` above is derived from — `AgentSession.start()`
        // spawns `--subagent-pool <poolSize>` so the engine actually hosts
        // the worker sessions the scheduler addresses. Before this fix the
        // session never carried this at all, so `/orchestrate`/`/chat` and
        // `dispatch` were dead in the running app (Task 2's report, "entangle
        // -ment 2").
        let session = AgentSession(
            settings: settings, tools: settings.tools ?? [], captureDirectory: captureDir,
            family: AgentController.runningModelFamily(),
            captureEnabled: sessionCaptureEnabled,
            poolSize: AgentController.poolSize())
        session.onEvent = { [weak self] event in
            guard let self, gen == self.generation else { return }
            self.applyAgentEvent(event)
        }
        session.onOutcome = { [weak self] outcome in
            guard let self, gen == self.generation else { return }
            self.finishTurn(outcome)
        }
        // Regression fix (eval-cli task 3): worker-tagged wire events reach
        // `handleWorkerEvent` (`AgentPoolTurnLoop.swift`, app-side — it needs
        // `workerTurn`'s worktree/watchdog, which cannot leave this target).
        // `handleWorkerEvent` is async (it awaits the host tool executor for
        // a worker's `tool_request`); `onWorkerEvent` itself is sync
        // (`AgentSession`'s own drain loop calls it inline from `consume`),
        // so the async half runs in its own `Task` — the engine blocks on the
        // matching `tool_result` either way (P11's serialized pool mutex), so
        // this cannot race a later line for the SAME worker.
        session.onWorkerEvent = { [weak self] worker, event in
            guard let self, gen == self.generation else { return }
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation else { return }
                await self.handleWorkerEvent(worker: worker, event: event, generation: gen)
            }
        }
        // Regression fix (eval-cli task 3): the `dispatch` tool's admission
        // decision needs `poolState`/`rollingDigest`, which stay app-side —
        // `AgentSession` cannot make it itself. Mutating `poolState` here (a
        // side effect of computing the decision, not a separate callback) is
        // the same shape the pre-task-2 inline `consumeWire` dispatch handler
        // used.
        session.onDispatchDecision = { [weak self] params in
            guard let self, gen == self.generation else { return .refused("session restarted") }
            let decision = DispatchAdmission.decide(
                params: params, digest: self.rollingDigest, loaded: [:],
                implementer: self.settings.modelPath.lastPathComponent,
                poolState: self.poolState,
                dumb: UserDefaults.standard.bool(forKey: "dispatchDumb"))
            switch decision {
            case .refused(let reason):
                self.log("dispatch: refused (\(reason))")
            case .enqueue(let packet, let worker):
                self.poolState = PoolScheduler.apply(self.poolState, .enqueue(packet: packet))
                self.log("dispatch: enqueued worker \(worker.rawValue)")
            }
            return decision
        }
        // Regression fix (eval-cli task 3): restore `rollingDigest`'s
        // host-verdict feed for the orchestrator's own tool calls (Task 2's
        // report, entanglement #4) — it fed the wire-event half
        // (`applyAgentEvent`) but not this half, so a `dispatch` admission
        // decided against a digest that never recorded any file the
        // orchestrator itself had touched.
        session.onToolVerdict = { [weak self] mutations, exitStatus, validationRan in
            guard let self, gen == self.generation else { return }
            self.rollingDigest = RollingDigestReducer.recordHostVerdict(
                self.rollingDigest, mutations: mutations,
                exitStatus: exitStatus, validationRan: validationRan)
        }
        session.onRefusal = { [weak self] line in
            guard let self, gen == self.generation else { return }
            self.state = .failed("wire handshake refused: \(line)")
            self.agentSession?.stop()
        }
        session.onStderrLine = { [weak self] line in
            guard let self, gen == self.generation else { return }
            self.stderrTail.append(line)
            if self.stderrTail.count > 20 { self.stderrTail.removeFirst(self.stderrTail.count - 20) }
        }
        session.onExit = { [weak self] status, tail in
            guard let self, gen == self.generation else { return }
            self.process = nil
            self.memoryTask?.cancel()
            self.traceTask?.cancel()
            self.stopEscalationTask?.cancel()
            self.stopEscalationTask = nil
            self.orchestratorToolTask?.cancel()
            self.orchestratorToolTask = nil
            self.interruptPending = false
            self.lastFootprintBytes = nil
            // The engine's failure mode is exiting (stderr boot lines are
            // normal — the memory plan lives there); a mid-start or mid-turn
            // exit is a failure carrying the stderr tail.
            if self.state == .starting || self.state == .generating {
                self.state = .failed("agent exited (\(status)): \(tail.joined(separator: "\n"))")
            } else if self.state != .stopped {
                self.state = .stopped
            }
        }
        self.agentSession = session
        do {
            _ = try session.start()
        } catch {
            self.agentSession = nil
            state = .failed("spawn failed: \(error)")
            return
        }
        self.process = session.process
        startMemoryPolling()
        if let tracePath = settings.tracePath {
            startTracePolling(path: tracePath, generation: gen)
        }

        startupTimeoutTask?.cancel()
        startupTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled else { return }
            if self.state == .starting {
                self.state = .failed("agent did not handshake within 60s")
                self.agentSession?.stop()
            }
        }
    }

    /// The orchestrator-turn view-state reaction to one parsed wire event
    /// (`AgentSession.onEvent`): state transitions, the telemetry readout, and
    /// the transcript. Was the non-tool-request part of `consumeWire`'s
    /// switch; tool-request handling itself now lives entirely inside
    /// `AgentSession` (it answers the callback itself — the app must not
    /// re-parse or re-answer the wire, which is the duplication eval-cli task
    /// 2 exists to remove).
    private func applyAgentEvent(_ event: AgentEvent) {
        rollingDigest = RollingDigestReducer.apply(
            rollingDigest, event: PoolWireEvent(worker: .orchestrator, event: event))
        switch event {
        case .hello(_, let caps):
            advertisedCaps = Set(caps)
            if state == .starting { state = .ready }
        case .status(let snapshot):
            onTelemetry?(.status(snapshot))
            lastStatus = snapshot
            // D12: the outcome record itself lives in `AgentSession` now, but
            // the elapsed-work-time figure `TurnSummary` shows (`TurnSpan`,
            // below) is view-facing, so this type keeps its own copy of the
            // turn's status samples rather than reaching into the session's
            // private builder. `isGenerating` is this type's own equivalent
            // of "a turn is open" — the orchestrator's outcome builder tracks
            // the identical span 1:1 (opened by `send`, closed by the
            // turn-end `ready`).
            if isGenerating { turnStatuses.append(snapshot) }
            lastPrefillTPS = AgentStatusText.ratchet(previous: lastPrefillTPS, new: snapshot.prefillTPS)
            lastGenTPS = AgentStatusText.ratchet(previous: lastGenTPS, new: snapshot.genTPS)
        case .ready(let plannedBytes, _, _, _):
            if let plannedBytes {
                lastPlannedModel = settings.modelPath.lastPathComponent
                lastPlannedBytes = plannedBytes
            }
            onTelemetry?(.ready(plannedBytes: plannedBytes, stopReason: nil, generated: nil, ctxUsed: nil))
            if state == .starting { state = .ready }
            else if state == .generating { state = .ready }
        case .text, .think, .tool:
            transcript.apply(event)
        case .queued, .ignored, .toolRequest, .toolRequestRefused, .refused:
            break
        }
    }

    /// One finished turn (`AgentSession.onOutcome`): persistence + the
    /// transcript's frozen summary + draining any workers the turn's
    /// `dispatch` calls enqueued. Was the second half of `consumeWire`'s
    /// `.ready` case.
    private func finishTurn(_ outcome: TurnOutcome) {
        lastTurnOutcome = outcome
        completedTurns += 1
        log("turn outcome: \(outcome)")
        appendOutcome(outcome)
        // Freeze the turn's summary onto its reply bubble. Both figures come
        // off the outcome, which computed them together from the status
        // stream `AgentSession` was already being fed — this type keeps no
        // accumulator of its own, so there is no opportunity here to pair a
        // rate with the wrong token count. `promptTPS` is the turn-end
        // ratchet, matching the status bar; a turn with no usable decode work
        // falls back to the engine's last reported rate rather than a
        // fabricated average.
        let summary = TurnSummary(
            promptTPS: lastPrefillTPS,
            decodeTPS: outcome.decodeTPS ?? lastGenTPS,
            generatedTokens: outcome.generatedTokens,
            ctxUsed: outcome.ctxUsed,
            elapsedSeconds: TurnSpan.measure(turnStatuses)?.workSeconds,
            stopReason: outcome.stopReason)
        transcript.attachSummary(summary)
        turnStatuses = []
        // The status bar's Prompt/Decode readout resets at turn end: a
        // permanent "last observed" must not pose as "current" while the
        // agent idles between turns (`AgentSession.send` also zeros at the
        // next turn's start — this covers the idle window).
        lastPrefillTPS = 0
        lastGenTPS = 0
        // `AgentSession.onOutcome` fires only for a genuine turn-end (its own
        // `outcomeBuilder` was open and a closing `ready` arrived) — the
        // precise moment `interruptPending` (this type's own view-facing
        // signal, since `AgentSession`'s `sentInterrupt` stays private) must
        // clear.
        interruptPending = false
        // P11 (D4): the orchestrator's turn ended — run any workers it
        // dispatched.
        drainQueuedWorkers()
    }


    func log(_ s: String) {
        guard let logHandle else { return }
        let data = Data((s + "\n").utf8)
        _ = try? logHandle.seekToEnd()
        try? logHandle.write(contentsOf: data)
    }

    /// Write one `tool_result` line to the engine's stdin (the single sink for
    /// both the P9 responder path and the P11 dispatch path).
    ///
    /// `write(contentsOf:)`, not `write(_:)`: the latter is the ObjC-era
    /// overload that RAISES on a closed/broken pipe, which `try?` cannot catch
    /// — it terminates the app (the same lesson the wire-capture tees document
    /// above). Item 3 (P22 cleanup) made the host `bash` executor genuinely
    /// async, freeing the MainActor for the duration of a tool call — so
    /// `stopAgent()` closing this pipe's write side is now reachable while a
    /// call is in flight. `stopAgent()` does not bump `generation` (only a
    /// restart does), so the caller's post-await generation guard does not
    /// catch a plain Stop; this write must tolerate a closed pipe on its own.
    func writeToolResult(_ response: ToolCallbackResponse) {
        guard let pipe = process?.standardInput as? Pipe else { return }
        try? pipe.fileHandleForWriting.write(
            contentsOf: Data((ToolCallbackResponder.resultLine(response) + "\n").utf8))
    }


    /// A stable string for a `Receipt` (D10: the reason folds back into the
    /// orchestrator's context as prose, not a debug dump).
    static func receiptReason(_ receipt: Receipt) -> String {
        switch receipt {
        case .refusedTool(let path): return "refusedTool: \(path)"
        case .budgetExceeded: return "budgetExceeded"
        case .validationFailed(let exit, _): return "validationFailed (exit \(exit))"
        case .noChanges: return "noChanges"
        case .repairExhausted: return "repairExhausted"
        case .contractNotFollowed: return "the worker produced no labeled files (text contract not followed)"
        }
    }

    /// P8: resolve the Superpowers skills dir — env `SUPERPOWERS_SKILLS_DIR`
    /// if set and non-empty, else the default
    /// `~/.pi/agent/git/github.com/obra/superpowers/skills`. A missing dir is a
    /// non-fatal degrade (staging throws; the bootstrap degrades to "No skills
    /// available in this workspace."; D3).
    private static func resolveSkillsDir() -> URL {
        if let env = ProcessInfo.processInfo.environment["SUPERPOWERS_SKILLS_DIR"],
           !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/git/github.com/obra/superpowers/skills")
    }

    /// The engine build identification (D12): the submodule SHA, resolved
    /// once per spawn — the same fact the capture provenance records.
    private static func submoduleSHA(_ engineDir: URL) -> String {
        guard let result = try? GitProcess.run(["rev-parse", "HEAD"], in: engineDir),
              result.exit == 0, !result.timedOut else { return "unknown" }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// P9: the host's side-effecting tool executor (D3/D6). The pure
    /// `ToolCallbackResponder` handles consent + condensation + the
    /// `tool_result` line; this closure is the app's file/process capability
    /// the responder injects.
    ///
    /// Item 4 (P22 cleanup): the actual six-tool-family implementation now
    /// lives once, in `SwiftStarAppKit.HostToolExecutor`, shared with
    /// `PoolOrchestrator` — this is a thin wrapper selecting the app's policy
    /// (`.app`: no read cache, `bash` just runs since `shellAllowed` was
    /// already checked by `ToolCallbackResponder.consent`, `search` honors
    /// `case_sensitive` and a match-count header, `bash_status`/`bash_stop`
    /// get an explicit refusal). `nonisolated` — touches only the executor
    /// (not `self`); `async` because `bash` awaits `SubprocessRunner`'s async
    /// `run` (item 3), which yields instead of blocking a thread, so a
    /// long-running command no longer freezes the MainActor for up to its
    /// timeout (300s default) — the engine still blocks on the result line
    /// either way (the wire protocol is unchanged), but the app's UI stays
    /// responsive while it waits.
    // Internal, not private: `AgentPoolTurnLoop` (an extension in another file)
    // registers each worker's own context against its worktree root (P24.1) —
    // the same reason P23's extracted methods lost `private`. Not widened to
    // `public`.
    nonisolated static let hostToolExecutor = HostToolExecutor(policy: .app)

    nonisolated static func executeHostTool(
        _ request: ToolExecutionRequest
    ) async -> ToolExecutionResult {
        await hostToolExecutor.execute(request)
    }

    @discardableResult
    func send(_ prompt: String, asUser: Bool = true) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // The composer's own prompts render as user pills; internal traffic
        // (worker receipts injected into the orchestrator's next turn) is a
        // quiet system row — the user never typed it, so it must not look like
        // they did.
        let row: AgentTranscriptRow = asUser
            ? .user(trimmed, stats: UserRowStats.forText(trimmed))
            : .system(trimmed, stats: SystemRowStats())
        return inject(trimmed, row: row)
    }

    /// `/chat`'s answer: injected into the main agent's context with the
    /// `→ consulted:` marker (so the main agent knows its provenance), but
    /// rendered as its own `.consulted` panel — a delegated artifact, not
    /// the main agent's prose.
    @discardableResult
    func sendConsulted(_ answer: String, worker: WorkerId,
                       stats: ConsultedRowStats? = nil) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let wireText = "→ consulted: \(trimmed)"
        return inject(wireText, row: .consulted(worker, trimmed, stats: stats))
    }

    /// Now a thin wrapper: the wire write, the think-override decision, and
    /// the turn's `TurnOutcomeBuilder` all moved into `AgentSession.send`
    /// (eval-cli task 2). This keeps only what stays app-side per that task's
    /// scoping — the transcript row (view state) and the `state` transition —
    /// and only performs them once `agentSession.send` actually accepted the
    /// write, so a refused send never shows a phantom user bubble.
    private func inject(_ wireText: String, row: AgentTranscriptRow,
                        think: ThinkEffort? = nil) -> Bool {
        guard canSend, !wireText.isEmpty, let agentSession,
              agentSession.send(wireText, think: think) else { return false }
        transcript.append(row)
        turnStatuses = []
        // A new turn starts with honest zeros: the previous turn's ratcheted
        // rates would mislead ("Prompt 1200" while prefill is actually 0) in
        // the brief window before fresh status events arrive.
        lastPrefillTPS = 0
        lastGenTPS = 0
        state = .generating
        return true
    }

    /// D5: interrupt = write one ETX byte (0x03) to the child's stdin. The
    /// engine latches it, emits an interrupted `finish` when mid-block, and
    /// returns to idle; the controller reflects that via the wire. Consults
    /// use the same pooled engine input, so they are interruptible too.
    ///
    /// `AgentSession.interrupt()` owns the write for the orchestrator's OWN
    /// turn (it also flips its private `sentInterrupt`, which the outcome
    /// record needs to label the turn `.interrupt` over whatever the wire's
    /// own stop_reason says) — gated there on its own `outcomeBuilder != nil`,
    /// which is nil during a `/chat` consult worker's turn. A consult
    /// interrupt is written here instead, straight to `process` (the same
    /// underlying pipe `AgentSession` holds — mirrored into `self.process` at
    /// `startAgent()`), and marks the worker's own turn state interrupted.
    var isTurnActive: Bool { isGenerating || isConsulting }
    var canInterrupt: Bool { isTurnActive && !interruptPending }

    func clearInterruptPending() {
        interruptPending = false
    }

    func interrupt() {
        guard isTurnActive, !interruptPending else { return }
        if isGenerating {
            agentSession?.interrupt()
            interruptPending = true
            orchestratorToolTask?.cancel()
            return
        }
        guard let process, let pipe = process.standardInput as? Pipe else { return }
        do {
            try pipe.fileHandleForWriting.write(contentsOf: Data([0x03]))
            interruptPending = true
            workerTurn.markInterrupted()
        } catch {
            transcript.appendSystem("→ interrupt failed: \(error.localizedDescription)")
            log("interrupt failed: \(error)")
        }
    }

    func stopAgent() {
        guard state != .stopped || process != nil else { return }
        state = .stopping
        startupTimeoutTask?.cancel()
        stopEscalationTask?.cancel()
        orchestratorToolTask?.cancel()
        workerTurn.cancelToolTask()
        interruptPending = false
        memoryTask?.cancel()
        // `AgentSession.stop()` does the cooperative shutdown (EOF on stdin,
        // then `terminate()`) and `AgentSession.onExit` lands `.stopped` (its
        // guard passes: state is `.stopping`, not `.stopped`) after recording
        // the exit. `terminate()` is only cooperative, though — a wedged
        // engine can leave the toolbar stuck on "Stopping…" forever, which
        // also makes a subsequent session impossible — so give graceful
        // shutdown a short window, then kill the exact child `AgentSession`
        // spawned. `self.process` still mirrors `session.process` (set at
        // `startAgent()`), so it is reachable here without reaching back into
        // the session.
        agentSession?.stop()
        guard process != nil else {
            state = .stopped
            return
        }
        let generation = self.generation
        stopEscalationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self,
                  self.generation == generation,
                  self.state == .stopping,
                  let process = self.process,
                  process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// Stop, wait for the termination handler to land `.stopped`, then start
    /// again. `startAgent()` refuses any state but `.stopped`/`.failed`, so a
    /// restart cannot call it directly after `stopAgent()` (state is still
    /// `.stopping`); it waits on the transition. The Settings escape hatch
    /// (P19.1 D4): the engine lifecycle stays implicit in the main surface.
    func restartAgent(pinnedSettings: AgentSettings? = nil) {
        switch state {
        case .stopped, .failed:
            startAgent(pinnedSettings: pinnedSettings)
        default:
            stopAgent()
            restartTask?.cancel()
            restartTask = Task { @MainActor [weak self] in
                // A wedged child that ignores stdin-EOF and SIGTERM would
                // otherwise poll forever with the UI silently stuck in
                // .stopping and no signal a switch was even attempted.
                let deadline = 100
                var waited = 0
                while self?.state != .stopped && !Task.isCancelled && waited < deadline {
                    try? await Task.sleep(for: .milliseconds(100))
                    waited += 1
                }
                guard !Task.isCancelled, let self else { return }
                guard self.state == .stopped else {
                    self.state = .failed("the previous session did not stop in time")
                    self.transcript.appendSystem(
                        "→ restart failed: the previous session did not stop in time")
                    return
                }
                self.startAgent(pinnedSettings: pinnedSettings)
            }
        }
    }

    /// P22 model switching — the "Apply this model" action. Resolves the staged
    /// selection exactly as the next spawn would, runs the pure switch decision
    /// (admission × generating × consulting × changed), and stops + re-spawns
    /// only when the decision says apply. Refusals and no-ops surface as
    /// transcript system rows; a working session is never killed for an
    /// infeasible or missing target — the admission gate runs before any stop,
    /// and a custom/unverified path (which skips the admission gate entirely —
    /// Settings contract) is still checked to exist. `targetSettings` is
    /// threaded through `restartAgent` so the eventual spawn respawns the
    /// exact target this decision admitted, not whatever
    /// `AgentDefaultSettings.resolve` would return after the async stop
    /// window (D2/TOCTOU fix).
    func applyModelSelection() {
        let targetSettings = AgentController.defaultSettings()
        let admission = AgentController.admitStagedVariant(contextSize: targetSettings.contextSize)
        if admission == nil,
           !FileManager.default.fileExists(atPath: targetSettings.modelPath.path) {
            transcript.appendSystem(
                "→ apply model refused: model file not found at \(targetSettings.modelPath.path)")
            return
        }
        switch ModelSwitchEvaluator.decide(
            isGenerating: isGenerating,
            isConsulting: isConsulting,
            runningSettings: settings,
            targetSettings: targetSettings,
            admission: admission
        ) {
        case .apply:
            transcript.appendSystem(
                "→ apply model: switching to \(targetSettings.modelPath.lastPathComponent)")
            restartAgent(pinnedSettings: targetSettings)
        case .noChange:
            transcript.appendSystem(
                "→ apply model: already running \(targetSettings.modelPath.lastPathComponent)")
        case .refused(let reason):
            transcript.appendSystem("→ apply model refused: \(reason)")
        }
    }

    /// The `/orchestrate` command (P20): run the task as the model-driven
    /// coordination loop. The directive (built from the task + writable scope)
    /// is sent as one user turn through the normal `send` path — the model
    /// decomposes, dispatches phases via the `dispatch` tool, reads receipts,
    /// validates, and writes files; the host's pool/validation machinery is
    /// the substrate. One-shot-first: no host repair loop (D2).
    func orchestrate(task: String, writableFiles: [String]) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            transcript.appendSystem("→ orchestrate: no task given")
            return
        }
        guard canSend else {
            transcript.appendSystem("→ orchestrate: agent not idle")
            return
        }
        let directive = OrchestrateDirective.build(task: trimmed, writableFiles: writableFiles)
        send(directive, asUser: true)
    }

    @ObservationIgnored private var restartTask: Task<Void, Never>?

    /// One 1s poll of the agent process's resident footprint for the memory
    /// ring. A dead pid (or nil) blanks the ring rather than showing a stale
    /// figure. `ProcessStatsCollector` is an actor, so the IOKit sampling
    /// never runs on the main actor.
    private func startMemoryPolling() {
        memoryTask?.cancel()
        memoryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.tickMemory()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tickMemory() async {
        guard let pid = process?.processIdentifier else {
            lastFootprintBytes = nil
            return
        }
        let snapshot = await memoryCollector.collect(pid: pid)
        lastFootprintBytes = snapshot.residentBytes
    }

    /// How long a worker turn may run before the watchdog frees the pool. Well
    /// above a real turn (a deep-context worker turn is tens of seconds); this
    /// is a wedge-breaker, not a budget — the packet's budgets are the budget.
    static let workerTurnTimeoutSeconds = 600.0

    /// `/quick` (P23): one no-think turn. D3 — the app does not offer `/quick`
    /// when the engine did not advertise `think_override`: sending the field
    /// to an engine that does not claim it would be a silent degrade, and a
    /// no-think turn without engine support is not quick at all.
    func quick(task: String) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            transcript.appendSystem("→ quick: no task given")
            return
        }
        guard canSend else {
            transcript.appendSystem("→ quick: agent not idle")
            return
        }
        guard advertisedCaps.contains(TurnThinkPolicy.overrideCap) else {
            transcript.appendSystem(
                "→ /quick unavailable: this engine build does not advertise \(TurnThinkPolicy.overrideCap)")
            return
        }
        _ = inject(trimmed, row: .user(trimmed, stats: UserRowStats.forText(trimmed)), think: .off)
    }

    /// The running model's `ModelFamily` for `TurnThinkPolicy` (P23): from the
    /// staged variant when one exists, else Laguna S's family — the
    /// nothing-configured default. Resolution goes through the selected
    /// variant ID, not the settings' model path — a custom/unverified model
    /// path resolves to the default family's policy (no app-side refusal);
    /// the engine's own loud refusal (D4) is the backstop for a
    /// prefix-busting family the app cannot identify. `internal`, not
    /// `private`: `AgentPoolTurnLoop` (a separate file extension of this
    /// type) consults it at dispatch time, and Swift's `private` is
    /// file-scoped.
    static func runningModelFamily() -> ModelFamily {
        VariantResolver.resolveVariant(
            selectedVariantID: AgentController.effectiveSelectedVariantID())?.family
            ?? VariantRegistry.lagunaS.family
    }

    /// The `/chat` path: run the task as a read-only pool worker and surface
    /// the answer (the glossary's **chat** — formerly the misnamed
    /// `/orchestrate` read-only delegation; the coordination loop keeps the
    /// name and lands with P20).
    func consult(task: String, writableFiles: [String]) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let workerId = PoolScheduler.availableWorker(poolState) else {
            transcript.appendSystem("→ chat refused: subagent pool is busy")
            return
        }
        guard state == .ready else {
            transcript.appendSystem("→ chat refused: agent not idle")
            return
        }
        // A /chat task is still the user's question. Render it as a normal
        // prompt bubble; the worker provenance is shown on the answer row.
        transcript.appendUser(trimmed)
        let packet = HandoffPacket(
            taskText: trimmed, writableFiles: writableFiles, validationCommand: nil,
            baselines: [:], turnBudget: 100_000,
            toolCallBudget: ToolCallBudgetTracker.defaultBudget)
        poolState = PoolScheduler.apply(poolState, .enqueue(packet: packet))
        workerTurn.markConsult(workerId)
        // Run the worker now in the SAME engine (a context-isolated session) —
        // no second model process, so the separate-process hang class is gone.
        // The answer is surfaced in finishWorkerTurn when the worker's turn
        // ends (no watch task — its completed-receipt poll read stale results).
        drainQueuedWorkers()
    }

    /// Resolve the git repo root for `workspace` (`git rev-parse --show-toplevel`)
    /// so `WorktreeDispatcher` can branch a worktree from HEAD. Falls back to
    /// `workspace` on failure (the dispatch then fails at `git worktree add`
    /// with a readable error rather than a guess). `nonisolated` — runs `git`.
    nonisolated static func resolveRepoRoot(from workspace: URL) -> URL {
        if let result = try? GitProcess.run(["rev-parse", "--show-toplevel"], in: workspace),
           result.exit == 0, !result.timedOut {
            let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return URL(fileURLWithPath: trimmed) }
        }
        return workspace
    }
}

// MARK: - Capture retention (pure decision in SwiftStarKit; this is the only
// filesystem-touching side). Kept as its own extension, deliberately away
// from `startAgent()`'s capture-setup block, so the two stay editable
// independently; `startAgent()` itself only gains the single `pruneStaleCaptures()`
// call.
extension AgentController {
    /// The default policy, overridable via `UserDefaults` (the `sessionCaptureEnabled`
    /// pattern): keep the 20 most-recent capture directories per producer
    /// tree, or anything from the last 14 days — see `CaptureRetentionPolicy`'s
    /// doc comment for why those two numbers, combined by union, were chosen.
    static func captureRetentionPolicy() -> CaptureRetentionPolicy {
        let keepCount = UserDefaults.standard.object(forKey: "captureRetentionKeepCount") as? Int ?? 20
        let keepDays = UserDefaults.standard.object(forKey: "captureRetentionKeepDays") as? Int ?? 14
        return CaptureRetentionPolicy(keepCount: keepCount, keepDays: keepDays)
    }

    /// Prune stale session captures across every producer tree under
    /// `captures/` — EXCEPT `captures/evidence/`, which is never enumerated
    /// here (permanently exempt, structurally: this function does not know it
    /// exists). Runs once per `startAgent()` call, before the new session's
    /// capture directory is created. Non-fatal by construction: a missing
    /// `captures/` directory (nothing captured yet) or a stat/delete failure
    /// on one entry just skips that entry — this must never block a session
    /// from starting.
    func pruneStaleCaptures() {
        guard let repo = Self.projectRoot() else { return }
        let capturesRoot = repo.appendingPathComponent("captures", isDirectory: true)
        let policy = Self.captureRetentionPolicy()
        pruneCaptureTree(label: "live", at: capturesRoot.appendingPathComponent("live", isDirectory: true), policy: policy)
        pruneCaptureTree(label: "agenttest", at: capturesRoot.appendingPathComponent("agenttest", isDirectory: true), policy: policy)
        // swiftstar-drive writes directly into `captures/<timestamp>-<model>`
        // (no subdirectory of its own) — treat captures/ itself as a third
        // producer tree, excluding the two named subtrees above and `evidence`.
        pruneCaptureTree(
            label: "captures/ (drive root)", at: capturesRoot, policy: policy,
            excludingNames: ["live", "agenttest", "evidence"])
    }

    /// Stat one producer tree's immediate subdirectories, run the pure
    /// decision, delete what it says to delete, and log exactly what was
    /// deleted (never silently).
    private func pruneCaptureTree(
        label: String, at dir: URL, policy: CaptureRetentionPolicy, excludingNames: Set<String> = []
    ) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        var entries: [CaptureEntry] = []
        for name in names {
            guard !excludingNames.contains(name), !name.hasPrefix(".") else { continue }
            let url = dir.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            entries.append(CaptureEntry(name: name, modified: modified, sizeBytes: Self.directorySizeBytes(url)))
        }
        let toDelete = CaptureRetention.directoriesToDelete(entries: entries, policy: policy)
        guard !toDelete.isEmpty else { return }
        for victim in toDelete {
            try? fm.removeItem(at: dir.appendingPathComponent(victim.name, isDirectory: true))
        }
        let freedBytes = toDelete.reduce(Int64(0)) { $0 + $1.sizeBytes }
        log("capture retention: pruned \(toDelete.count) dir(s) from \(label)/ "
            + "(\(ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)) freed): "
            + toDelete.map(\.name).joined(separator: ", "))
    }

    /// Shallow-enough recursive size for a log line — capture directories are
    /// a handful of NDJSON/text files, never a deep tree, so a full recursive
    /// sum costs nothing meaningful at app-startup time.
    private static func directorySizeBytes(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil)
        else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
