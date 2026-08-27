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
    /// retired EngineController.shared pattern).
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
    private(set) var transcript = AgentTranscript()
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
    /// matches the running model (mirrors EngineController's stale-plan guard).
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
    /// The in-flight turn's decode work, accumulated per generation segment on
    /// the engine's own clock. Reset at each turn's start and end.
    private var decodeAccumulator = DecodeAccumulator()

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
    private(set) var poolState = PoolState(workerCapacity: SubagentPoolSize.workerCapacity(AgentController.poolSize()))
    /// P21: the Metrics tab's live source — fired on each status/ready wire
    /// event (MainActor; consumeWire). A single observer slot (Metrics owns it;
    /// the fixture replay is only the pre-spawn placeholder).
    var onTelemetry: ((AgentEvent) -> Void)?
    /// P11 (D6): the rolling digest — the objective-independent reduced form
    /// of the session, maintained incrementally as host facts arrive.
    private(set) var rollingDigest = RollingDigest()

    /// Mutated only on MainActor; the nonisolated `deinit` terminates it. No
    /// isolation opt-out is needed on this toolchain (the compiler reports
    /// `nonisolated(unsafe)` here as having no effect), and plain `nonisolated`
    /// is illegal on a mutable stored property. Must stay observation-TRACKED:
    /// `runningPid` is computed over it, and `MainView` re-points
    /// Metrics/Diagnostics when that changes.
    private var process: Process?
    private var parser = PoolWireParser()
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var generation = 0
    // D12 turn-outcome state.
    private var outcomeBuilder: TurnOutcomeBuilder?
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
    private var workerTurn = ActiveWorkerTurn()
    private var sentInterrupt = false
    private var buildSHA = "unknown"
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
        try? logHandle?.close()
    }

    var canSend: Bool { state == .ready }
    var isGenerating: Bool { state == .generating }
    /// The agent is up and serving — the state in which the bottom bar's
    /// telemetry readout (rates, rings) is meaningful.
    var isUp: Bool { state == .ready || state == .generating }
    /// True only while a `/chat` consult worker is running (item 2 of the
    /// P22 cleanup). `consult()`'s worker turn runs via `drainQueuedWorkers()`
    /// without ever touching `state` — it stays `.ready` for the whole turn,
    /// on purpose: `sendConsulted`'s delivery requires `canSend`, `interrupt()`
    /// keys off `isGenerating`, and `ModelMenu` disables on `isGenerating` —
    /// all three would break if a worker turn reused `.generating`. This is a
    /// separate signal so AgentView can show a distinct "consulting" affordance
    /// (composer visibly busy, but not the generating/interrupt state) instead
    /// of looking idle while a consult worker is in flight.
    var isConsulting: Bool {
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

    /// The P5-provenance shape, written once at spawn (the manifest that lets a
    /// reader trust and reproduce the capture). Item 6 (P22 cleanup): the
    /// assembly (title + bulleted facts + closing note) is shared with
    /// `swiftstar-drive`'s `CaptureWriter` via `CaptureProvenance`; the facts
    /// themselves (sampler, workspace grant) stay specific to a live app
    /// session.
    private static func renderLiveProvenance(model: String, build: String, workspace: String, contextSize: Int, sampler: String, at dir: URL) throws {
        let text = CaptureProvenance.render(
            title: "Live session provenance",
            facts: [
                .init("Model", "`\(model)`"),
                .init("Build (`external/ds4` SHA)", "`\(build)`"),
                .init("Context", "\(contextSize)"),
                .init("Sampler", sampler),
                .init("Workspace", "`\(workspace)`"),
                CaptureProvenance.startedAtFact(Date()),
            ],
            closingNote: """
            Captured live by the SwiftStar app (agent session). `wire.ndjson` and
            `agent.stderr` are the verbatim raw streams; `agent.trace` is the engine's
            `--trace` channel. Wire `ts` is monotonic-since-boot (deltas only); this
            file anchors wall-clock.
            """)
        try text.write(to: dir.appendingPathComponent("provenance.md"), atomically: true, encoding: .utf8)
    }

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

    func startAgent() {
        switch state {
        case .stopped, .failed: break
        default: return
        }
        // P13: refresh settings so a selected variant applies (mirrors
        // EngineController), then admit it before spawn (C1).
        settings = AgentController.defaultSettings()
        if let variant = VariantResolver.resolveVariant(
            selectedVariantID: AgentController.effectiveSelectedVariantID()) {
            let admission = VariantGate.admit(
                variant, contextSize: settings.contextSize,
                availableBytes: MemorySnapshot.availableBytes())
            switch admission {
            case .admitted:
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
        }
        let binary = AgentCommand.binaryPath(settings: settings)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            state = .failed("agent binary missing at \(binary.path)")
            return
        }
        state = .starting
        generation += 1
        let gen = generation
        // A restart is a fresh wire: the handshake state must reset or the new
        // session's hello is misread as a second handshake (stuck in
        // .starting forever). The transcript is deliberately kept (history,
        // like EngineController); stderrTail is reset so a failure message
        // never pairs a new session with a stale tail.
        parser = PoolWireParser()
        stderrTail = []
        lastStatus = nil
        lastPrefillTPS = 0
        lastGenTPS = 0
        lastPlannedBytes = nil
        lastPlannedModel = nil
        lastFootprintBytes = nil
        decodeAccumulator = DecodeAccumulator()
        outcomeBuilder = nil
        sentInterrupt = false
        // A restart is a fresh engine = a fresh pool: stale pending workers and
        // consult bookkeeping must not survive into the new session.
        poolState = PoolState(workerCapacity: SubagentPoolSize.workerCapacity(AgentController.poolSize()))
        workerTurn.watchdog?.cancel()
        workerTurn = ActiveWorkerTurn()
        // D12: the build identification is resolved once per spawn (the
        // submodule SHA — the same fact the capture provenance records).
        buildSHA = AgentController.submoduleSHA(settings.engineDir)

        // Live session capture (P7's deferred "live wiring", scoped 2026-08-26):
        // persist the agent's wire + trace + stderr so the session can be read
        // from disk — analysing prompts, tool calls, context — without
        // SWIFTSTAR_LOG. The trace is written by the engine itself via
        // `--trace`; the wire/stderr are teed in the drain loops below.
        let captureEnabled = UserDefaults.standard.object(forKey: "sessionCaptureEnabled") as? Bool ?? true
        pruneStaleCaptures()  // retention policy: see the AgentController extension below
        let captureDir = Self.captureDirectory()
        if captureEnabled {
            try? FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
            try? Self.renderLiveProvenance(
                model: settings.modelPath.lastPathComponent, build: buildSHA,
                workspace: settings.workspace.path, contextSize: settings.contextSize,
                sampler: "engine-defaults", at: captureDir)
            settings.tracePath = captureDir.appendingPathComponent("agent.trace")
        }
        outcomesURL = captureEnabled ? captureDir.appendingPathComponent("outcomes.ndjson") : nil
        let captureWireURL = captureDir.appendingPathComponent("wire.ndjson")
        let captureStderrURL = captureDir.appendingPathComponent("agent.stderr")
        // `FileHandle(forWritingAtPath:)` opens an existing file — it does not
        // create one. The drains open it lazily, so create the empty files here
        // or the tees silently write nothing for the whole session. Capture
        // disabled = no files created, so the lazy opens return nil and the
        // tees no-op (P19.1 D3).
        if captureEnabled {
            FileManager.default.createFile(atPath: captureWireURL.path, contents: nil)
            FileManager.default.createFile(atPath: captureStderrURL.path, contents: nil)
            // outcomes.ndjson is appended the same lazy way (appendOutcome opens
            // it per turn), so it needs the same up-front create or every turn
            // outcome is silently dropped for the whole session.
            if let outcomesURL { FileManager.default.createFile(atPath: outcomesURL.path, contents: nil) }
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
        settings.systemPrompt = SuperpowersBootstrap.build(skillsDir: skillsDir).indexPrompt

        let process = Process()
        process.executableURL = binary
        // P11 pool: one orchestrator + one worker session in the SAME engine,
        // so `/orchestrate` (and the model's dispatch tool) run subagents
        // without a second model process. +1 session ≈ +8.7 GB at ctx 50k
        // (Correction 2: N × (KV + ~6.1 GB scratch)); the alternative — a
        // second 48 GB model load — is worse and was the orchestrate hang.
        let pool = AgentController.poolSize()
        process.arguments = AgentCommand.argv(settings: settings) + ["--subagent-pool", String(pool)]
        process.currentDirectoryURL = settings.engineDir
        // Metal shaders load cwd-relative, and the engine chdir's to
        // `--workspace`; point them at absolute paths (F1) so Metal resolves.
        process.environment = AgentCommand.engineEnvironment(
            engineDir: settings.engineDir, lockFile: "/tmp/ds4-agent.lock",
            base: ProcessInfo.processInfo.environment)
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                self.memoryTask?.cancel()
                self.lastFootprintBytes = nil
                // The engine's failure mode is exiting (stderr boot lines are
                // normal — the memory plan lives there); a mid-start or
                // mid-turn exit is a failure carrying the stderr tail.
                if self.state == .starting || self.state == .generating {
                    self.state = .failed("agent exited (\(p.terminationStatus)): \(self.stderrTail.joined(separator: "\n"))")
                } else if self.state != .stopped {
                    self.state = .stopped
                }
            }
        }
        self.process = process
        do {
            try process.run()
        } catch {
            self.process = nil
            state = .failed("spawn failed: \(error)")
            return
        }
        startMemoryPolling()

        // Item 6 (P22 cleanup): both tees route through `SafeAppendFile`
        // (shared with swiftstar-agenttest's own wire.ndjson capture) instead
        // of a raw `FileHandle(forWritingAtPath:)` + manual `write(contentsOf:)`
        // — closing the exact "lazy open against a path that was never
        // created silently no-ops the whole session" bug class at the type
        // level. Gated on `captureEnabled` here (not inside `SafeAppendFile`,
        // which always creates its path): disabled capture must create
        // nothing, and `SafeAppendFile` has no notion of that toggle — only
        // the caller does.
        stdoutTask?.cancel()
        stdoutTask = Task.detached(priority: .utility) { [weak self] in
            let handle = stdoutPipe.fileHandleForReading
            let capture: SafeAppendFile? = captureEnabled ? SafeAppendFile(path: captureWireURL.path) : nil
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }  // EOF: the child closed stdout
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    capture?.append(lineData)
                    capture?.append(Data([0x0A]))
                    let line = String(decoding: lineData, as: UTF8.self)
                    await self?.consumeWire(line, generation: gen)
                }
            }
            capture?.close()
        }

        stderrTask?.cancel()
        stderrTask = Task.detached(priority: .utility) { [weak self] in
            let handle = stderrPipe.fileHandleForReading
            let capture: SafeAppendFile? = captureEnabled ? SafeAppendFile(path: captureStderrURL.path) : nil
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    capture?.append(lineData)
                    capture?.append(Data([0x0A]))
                    let line = String(decoding: lineData, as: UTF8.self)
                    await self?.consumeStderr(line, generation: gen)
                }
            }
            capture?.close()
        }

        startupTimeoutTask?.cancel()
        startupTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled else { return }
            if self.state == .starting {
                self.state = .failed("agent did not handshake within 60s")
                self.process?.terminate()
            }
        }
    }

    private func consumeWire(_ line: String, generation: Int) async {
        guard generation == self.generation else { return }
        guard let poolEvent = parser.feed(line) else { return }
        let event = poolEvent.event

        // P11 (D1/D4): worker-tagged events belong to the in-flight worker
        // turn, not the orchestrator's transcript/outcome.
        if poolEvent.worker != .orchestrator {
            await handleWorkerEvent(worker: poolEvent.worker, event: event, generation: generation)
            return
        }

        // P11 (D6): feed the rolling digest with every wire event (tool-call
        // names) so the packet-maker's Layer 1 input is not empty.
        rollingDigest = RollingDigestReducer.apply(rollingDigest, event: poolEvent)

        // Every event feeds the outcome builder (it ignores what it does not
        // need); the record spans the whole turn, not just tool events.
        outcomeBuilder?.apply(event)
        switch event {
        case .hello:
            if state == .starting { state = .ready }
        case .status(let snapshot):
            // D6: the status line carries the worker's state, but it is NOT
            // the turn-end gate — the turn-end `ready` is (see `.ready`
            // below). Flipping state → .ready here on `state == "idle"`
            // raced that ready: the stdout drain awaits consumeWire per
            // line (separate main-actor hops), so between the idle status
            // and the turn-end ready a send() could overwrite the prior
            // turn's outcomeBuilder before the ready finished it — the
            // record was lost and the delayed ready misattributed. The wire
            // guarantees ready follows idle (json-events.md), and the
            // interrupt path emits ready too, so gating on ready alone is
            // safe. The status event still feeds the outcome builder above.
            // It also feeds the bottom status bar: the snapshot is kept as-is
            // and its rates are ratcheted (never blanked by a zero).
            onTelemetry?(.status(snapshot))
            lastStatus = snapshot
            // P21: the turn's decode work accumulates per generation segment on
            // the engine's own clock (see DecodeAccumulator) — wall time between
            // statuses includes prefill and tool round trips, which is not decode.
            decodeAccumulator.apply(snapshot)
            lastPrefillTPS = AgentStatusText.ratchet(previous: lastPrefillTPS, new: snapshot.prefillTPS)
            lastGenTPS = AgentStatusText.ratchet(previous: lastGenTPS, new: snapshot.genTPS)
            break
        case .ready(let plannedBytes, _, _, _):
            if let plannedBytes {
                lastPlannedModel = settings.modelPath.lastPathComponent
                lastPlannedBytes = plannedBytes
            }
            onTelemetry?(.ready(plannedBytes: plannedBytes, stopReason: nil, generated: nil, ctxUsed: nil))
            if state == .starting { state = .ready }
            else if state == .generating { state = .ready }
            // D12: a turn-end ready finishes the record. The builder is nil
            // at startup, so a startup ready is a no-op; a turn-end ready
            // (after send() opened a builder) finishes unconditionally —
            // TurnOutcomeBuilder.finish defaults a nil wire stop_reason to
            // .eos, so a pre-D12 wire (or any ready omitting the field) still
            // closes the record rather than orphaning it. The app's own
            // interrupt beats the wire's word for the reason.
            if let builder = outcomeBuilder {
                let outcome = builder.finish(appStopReason: sentInterrupt ? .interrupt : nil)
                outcomeBuilder = nil
                lastTurnOutcome = outcome
                completedTurns += 1
                log("turn outcome: \(outcome)")
                appendOutcome(outcome)
                // Freeze the turn's summary onto its reply bubble: the decode
                // average across the turn's generation segments, else the
                // engine-reported rate — never a fabricated average.
                // `promptTPS` is the turn-end ratchet, matching the status bar.
                decodeAccumulator.finish(finalGenerated: outcome.generatedTokens)
                let summary = TurnSummary(
                    promptTPS: lastPrefillTPS,
                    decodeTPS: decodeAccumulator.tokensPerSecond ?? lastGenTPS,
                    // The accumulator's total, not the outcome's: the engine
                    // resets its counter per generation segment, so a turn with
                    // tool rounds reports only its last segment on the wire.
                    generatedTokens: decodeAccumulator.generatedTokens,
                    ctxUsed: outcome.ctxUsed)
                transcript.attachSummary(summary)
                // The status bar's Prompt/Decode readout resets at turn end: a
                // permanent "last observed" must not pose as "current" while
                // the agent idles between turns (send() also zeros at the next
                // turn's start — this covers the idle window).
                lastPrefillTPS = 0
                lastGenTPS = 0
                decodeAccumulator = DecodeAccumulator()
            }
            // P11 (D4): the orchestrator's turn ended — run any workers it
            // dispatched.
            drainQueuedWorkers()
        case .text, .think, .tool:
            transcript.apply(event)
        case .toolRequest(let idx, let name, let params):
            if name == "dispatch" {
                if UserDefaults.standard.bool(forKey: "dispatchDumb") {
                    // Dumb mode keeps the baseline clean: the subagent pool is
                    // the architecture's biggest help, so a "dumb" run must not
                    // secretly dispatch workers and still win. The orchestrator
                    // sees the refusal and does the work itself — with the
                    // minimal packet it was given.
                    writeToolResult(ToolCallbackResponse(
                        idx: idx, ok: false,
                        s: ToolResultCondenser.condense("refused: dispatch is disabled in dumb mode")))
                    outcomeBuilder?.recordHostVerdict(
                        idx: idx, ok: false, mutations: [], exitStatus: nil,
                        outputDigest: nil, validationRan: false)
                    log("dispatch: refused (dumb mode)")
                } else if let packet = DispatchPacketBuilder.build(
                    params: params, digest: rollingDigest, loaded: [:],
                    implementer: settings.modelPath.lastPathComponent) {
                    if let workerId = PoolScheduler.availableWorker(poolState) {
                        poolState = PoolScheduler.apply(poolState, .enqueue(packet: packet))
                        writeToolResult(ToolCallbackResponse(
                            idx: idx, ok: true, s: "dispatched as worker \(workerId.rawValue)"))
                        outcomeBuilder?.recordHostVerdict(
                            idx: idx, ok: true, mutations: [], exitStatus: nil,
                            outputDigest: nil, validationRan: false)
                        log("dispatch: enqueued worker \(workerId.rawValue)")
                    } else {
                        writeToolResult(ToolCallbackResponse(
                            idx: idx, ok: false,
                            s: ToolResultCondenser.condense("refused: subagent pool is full")))
                    }
                } else {
                    writeToolResult(ToolCallbackResponse(
                        idx: idx, ok: false,
                        s: ToolResultCondenser.condense("refused: malformed dispatch")))
                }
            } else {
                // P9: the host owns execution. Route the request through the
                // responder (consent-enforced, condenses via ToolResultCondenser,
                // records the host facts), write the `tool_result` line to the
                // agent's stdin, and feed the host facts into the open
                // TurnOutcomeBuilder. The engine blocks on the result line, so
                // the wire itself is still request→result; but item 3 (P22
                // cleanup) made `execute` genuinely async (a `bash` call awaits
                // `SubprocessRunner`'s async `run`) so a long-running command no
                // longer blocks the MainActor — this `await` is a real
                // suspension point, not just the actor-hop the outer call
                // already had.
                let response = await ToolCallbackResponder.respond(
                    idx: idx, name: name, params: params,
                    workspace: settings.workspace, shellAllowed: settings.shellAllowed,
                    execute: Self.executeHostTool)
                // Reentrancy guard (item 3): freeing the MainActor during the
                // await above means Stop/Restart became reachable mid-tool-call
                // in a way they weren't when this was synchronous. A restart
                // bumps `generation` and resets poolState/outcomeBuilder/
                // rollingDigest for a brand-new session — folding this stale
                // response into that new state (or writing its tool_result to
                // the NEW engine's stdin) would corrupt it, so bail before
                // touching any of it. A plain Stop (no restart) doesn't bump
                // `generation`; `writeToolResult` itself is written to tolerate
                // that (see its doc).
                guard generation == self.generation else { return }
                writeToolResult(response)
                outcomeBuilder?.recordHostVerdict(
                    idx: idx, ok: response.ok,
                    mutations: response.mutations, exitStatus: response.exitStatus,
                    outputDigest: response.outputDigest, validationRan: response.validationRan)
                rollingDigest = RollingDigestReducer.recordHostVerdict(
                    rollingDigest, mutations: response.mutations,
                    exitStatus: response.exitStatus, validationRan: response.validationRan)
            }
        case .queued, .ignored:
            break
        case .toolRequestRefused(let idx, let reason):
            // P9: a malformed tool_request (the engine's protocol violation)
            // must not hang the wire. The engine emits one request then blocks
            // on its result, so skipping the result (as the parser's old
            // `.ignored` did) deadlocks. Write an `ok:false` `tool_result`
            // (idx best-effort, 0 if unparseable) so the engine unblocks and the
            // agent sees the refusal reason; the outcome builder already
            // skipped it (a malformed request is not a real tool call).
            let response = ToolCallbackResponse(
                idx: idx, ok: false, s: ToolResultCondenser.condense(reason),
                mutations: [], exitStatus: nil, outputDigest: nil, validationRan: false)
            if let pipe = process?.standardInput as? Pipe {
                pipe.fileHandleForWriting.write(
                    Data((ToolCallbackResponder.resultLine(response) + "\n").utf8))
            }
        case .refused(let line):
            state = .failed("wire handshake refused: \(line)")
            process?.terminate()
        }
    }

    private func log(_ s: String) {
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
    private func writeToolResult(_ response: ToolCallbackResponse) {
        guard let pipe = process?.standardInput as? Pipe else { return }
        try? pipe.fileHandleForWriting.write(
            contentsOf: Data((ToolCallbackResponder.resultLine(response) + "\n").utf8))
    }

    // MARK: - P11 worker-turn loop (D4)

    /// Start the next queued worker's turn in the pooled engine (D4): send the
    /// `PoolPrompt` for worker N, open its outcome builder, and mark it running.
    private func drainQueuedWorkers() {
        guard let (worker, packet) = PoolScheduler.nextWorker(poolState) else {
            injectPendingReceipts()
            return
        }
        // Prepare the worker's disposable worktree (P10 isolation): its file
        // mutations land here, never in the caller's tree.
        let repo = Self.resolveRepoRoot(from: settings.workspace)
        let worktree: WorktreeDispatcher.Worktree
        do {
            worktree = try WorktreeDispatcher.prepare(packet: packet, in: repo)
        } catch {
            let receipt = DispatchReceipt(worker: worker, ref: nil,
                reason: "worktree preparation failed", summary: "\(error)")
            poolState = PoolScheduler.apply(poolState, .workerFailed(worker, receipt))
            rollingDigest = RollingDigestReducer.record(rollingDigest, receipt: receipt)
            log("worker \(worker.rawValue): worktree prepare failed: \(error)")
            drainQueuedWorkers()
            return
        }
        poolState = PoolScheduler.apply(poolState, .workerStarted(worker))
        workerTurn.start(
            id: worker, packet: packet, worktree: worktree,
            outcomeBuilder: TurnOutcomeBuilder(
                model: settings.modelPath.lastPathComponent,
                build: buildSHA,
                sampler: "engine-defaults",
                task: packet.taskText))
        if let pipe = process?.standardInput as? Pipe {
            pipe.fileHandleForWriting.write(
                Data((PoolPrompt(worker: worker, text: packet.taskText).encode() + "\n").utf8))
        }
        armWorkerWatchdog(worker)
        log("worker \(worker.rawValue): turn started (worktree \(worktree.url.lastPathComponent))")
    }

    /// A worker turn ends on its `ready`; if that never arrives (engine wedged
    /// mid-turn) the scheduler's `running` slot is never freed and every later
    /// `/chat` and dispatch is refused "pool is busy" until a manual restart.
    /// The watchdog is the only bound on that — delivery is edge-triggered, so
    /// there is no poll left to notice.
    private func armWorkerWatchdog(_ worker: WorkerId) {
        workerTurn.watchdog?.cancel()
        let gen = generation
        workerTurn.watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.workerTurnTimeoutSeconds))
            guard !Task.isCancelled, let self,
                  self.generation == gen, self.workerTurn.activeId == worker else { return }
            self.failActiveWorker(worker, reason: "worker turn timed out")
        }
    }

    /// Fold a wedged worker turn into a failure receipt and free the pool — the
    /// same bookkeeping `finishWorkerTurn` does, minus the outcome (there is no
    /// `ready`, so there is nothing to finalize).
    private func failActiveWorker(_ worker: WorkerId, reason: String) {
        guard workerTurn.activeId == worker else { return }
        let isConsult = workerTurn.isConsult(worker)
        if let worktree = workerTurn.worktree {
            WorktreeDispatcher.discard(worktree, in: Self.resolveRepoRoot(from: settings.workspace))
        }
        workerTurn.clearActive()
        let receipt = DispatchReceipt(worker: worker, ref: nil, reason: reason, summary: reason)
        poolState = PoolScheduler.apply(poolState, .workerFailed(worker, receipt))
        if isConsult {
            workerTurn.removeConsult(worker)
            poolState = PoolScheduler.apply(poolState, .receiptInjected(worker))
            transcript.appendSystem("→ chat failed: \(reason)")
        }
        log("worker \(worker.rawValue): \(reason)")
        drainQueuedWorkers()
    }

    /// Route one worker-tagged event through the worker's turn (D4): answer its
    /// tool requests (revision-checked against its packet's writableFiles), and
    /// finish the turn on its `ready`. `generation` is the wire generation this
    /// event was read under (threaded from `consumeWire`); item 3 (P22
    /// cleanup) made the tool executor and `finishWorkerTurn`'s validation
    /// genuinely async, so this — like `consumeWire` — re-checks it after
    /// every await before touching shared controller state.
    private func handleWorkerEvent(worker: WorkerId, event: AgentEvent, generation: Int) async {
        workerTurn.outcomeBuilder?.apply(event)
        switch event {
        case .toolRequest(let idx, let name, let params):
            let response = await ToolCallbackResponder.respond(
                idx: idx, name: name, params: params,
                workspace: workerTurn.worktree?.url ?? settings.workspace,
                shellAllowed: false,
                writableFiles: workerTurn.activePacket?.writableFiles,
                execute: Self.executeHostTool)
            guard generation == self.generation else { return }
            writeToolResult(response)
            workerTurn.outcomeBuilder?.recordHostVerdict(
                idx: idx, ok: response.ok, mutations: response.mutations,
                exitStatus: response.exitStatus, outputDigest: response.outputDigest,
                validationRan: response.validationRan)
            rollingDigest = RollingDigestReducer.recordHostVerdict(
                rollingDigest, mutations: response.mutations,
                exitStatus: response.exitStatus, validationRan: response.validationRan)
        case .toolRequestRefused(let idx, let reason):
            writeToolResult(ToolCallbackResponse(idx: idx, ok: false,
                s: ToolResultCondenser.condense(reason)))
        case .ready:
            if let builder = workerTurn.outcomeBuilder {
                let outcome = builder.finish()
                workerTurn.outcomeBuilder = nil
                await finishWorkerTurn(worker: worker, outcome: outcome, generation: generation)
            }
        default:
            break
        }
    }

    /// Fold a finished worker turn into a `DispatchReceipt`, record it in the
    /// rolling digest (D9) and the scheduler, and run the next worker (or inject
    /// the receipts back into the orchestrator when the queue empties, D4). The
    /// candidate-vs-receipt verdict is the pure `WorktreeDispatch.verdict`; the
    /// candidate *ref* (the worktree commit SHA) is produced by the P10
    /// `WorktreeDispatcher`, which the pooled path will reuse for the commit.
    private func finishWorkerTurn(worker: WorkerId, outcome: TurnOutcome, generation: Int) async {
        workerTurn.watchdog?.cancel()
        let isConsult = workerTurn.isConsult(worker)
        let answerText: String? = isConsult ? outcome.text : nil
        let packet = workerTurn.activePacket ?? HandoffPacket(
            taskText: "", writableFiles: [], validationCommand: nil,
            baselines: [:], turnBudget: 0, toolCallBudget: 0)
        let receipt: DispatchReceipt
        if let worktree = workerTurn.worktree {
            let repo = Self.resolveRepoRoot(from: settings.workspace)
            let relativized = WorktreeDispatch.relativize(outcome: outcome, worktree: worktree.url)
            do {
                // Item 3 (P22 cleanup): async, off the MainActor — this used to
                // freeze the whole app's UI for as long as the validation
                // command ran. `finalize` itself stays sync (no subprocess).
                let validation = try await WorktreeDispatcher.runValidation(packet.validationCommand, in: worktree.url)
                let dispatchOutcome = try WorktreeDispatcher.finalize(
                    worktree, packet: packet, turnOutcome: relativized,
                    validation: validation, in: repo)
                switch dispatchOutcome {
                case .candidate(let ref, _, _):
                    receipt = DispatchReceipt(worker: worker, ref: ref, reason: nil,
                        summary: "candidate: \(relativized.mutations.count) mutation(s), \(relativized.generatedTokens) tokens",
                        answerText: answerText)
                case .receipt(let r):
                    receipt = DispatchReceipt(worker: worker, ref: nil,
                        reason: Self.receiptReason(r), summary: Self.receiptReason(r),
                        answerText: answerText)
                }
            } catch {
                receipt = DispatchReceipt(worker: worker, ref: nil,
                    reason: "infrastructure failure", summary: "\(error)",
                    answerText: answerText)
            }
            WorktreeDispatcher.discard(worktree, in: repo)
        } else {
            // No worktree (prepare failed earlier): fall back to the pure verdict.
            switch WorktreeDispatch.verdict(
                packet: packet, allowedMutations: outcome.mutations,
                turnOutcome: outcome, validation: nil) {
            case .candidate:
                receipt = DispatchReceipt(worker: worker, ref: nil, reason: nil,
                    summary: "candidate: \(outcome.mutations.count) mutation(s), \(outcome.generatedTokens) tokens",
                    answerText: answerText)
            case .receipt(let reason):
                receipt = DispatchReceipt(worker: worker, ref: nil,
                    reason: Self.receiptReason(reason), summary: Self.receiptReason(reason),
                    answerText: answerText)
            }
        }
        // Reentrancy guard (item 3): the worktree above is discarded either
        // way — no leak — but a restart during the `await` above (bumping
        // `generation`) already reset poolState/workerTurn/rollingDigest for a
        // brand-new session; folding this stale turn's receipt into that state
        // (or writing to the new session's wire) would corrupt it, so bail
        // once cleanup is done.
        guard generation == self.generation else { return }
        poolState = PoolScheduler.apply(poolState, .workerFinished(worker, receipt))
        // A consult runs read-only (writableFiles is empty by construction), so
        // its verdict is ALWAYS a refusal. Recording it would leave a phantom
        // "Worker N refused: noChanges" in the facts a later dispatch is planned
        // from — the digest gets implementer receipts only.
        if !isConsult {
            rollingDigest = RollingDigestReducer.record(rollingDigest, receipt: receipt)
        }
        workerTurn.clearActive()
        if isConsult {
            workerTurn.removeConsult(worker)
            // Surface the answer directly; never deliver a consult's receipt as
            // orchestrator prose — the answer IS the delivery. Clear the receipt
            // only when the send lands (at-least-once, matching
            // injectPendingReceipts): if the user started a turn mid-consult the
            // send is refused, and leaving the receipt pending lets the next
            // drain fold the answer in via `injectionPrompt()`.
            let answer = receipt.answerText.flatMap { $0.isEmpty ? nil : $0 } ?? receipt.summary
            if sendConsulted(answer, worker: worker) {
                poolState = PoolScheduler.apply(poolState, .receiptInjected(worker))
            } else {
                transcript.append(.consulted(worker, answer))
            }
        }
        log("worker \(worker.rawValue): \(receipt.summary)")
        drainQueuedWorkers()
    }

    /// Inject any undelivered receipts back into the orchestrator as its next
    /// turn's prompt (D4): the orchestrator sees only the bounded receipts, not
    /// the worker transcripts. Consult workers never reach here — their answer
    /// is delivered directly in `finishWorkerTurn`.
    private func injectPendingReceipts() {
        let receipts = poolState.pendingDelivery.values
            .sorted { $0.worker < $1.worker }
        guard !receipts.isEmpty else { return }
        let text = receipts.map { $0.injectionPrompt() }.joined(separator: "\n")
        // Send first, clear only on success — at-least-once delivery (a dropped
        // send must not silently lose the receipts).
        if send(text, asUser: false) {
            for worker in Array(poolState.pendingDelivery.keys) {
                poolState = PoolScheduler.apply(poolState, .receiptInjected(worker))
            }
        }
    }

    /// A stable string for a `Receipt` (D10: the reason folds back into the
    /// orchestrator's context as prose, not a debug dump).
    private static func receiptReason(_ receipt: Receipt) -> String {
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
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", engineDir.path, "rev-parse", "HEAD"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    private func consumeStderr(_ line: String, generation: Int) {
        guard generation == self.generation else { return }
        stderrTail.append(line)
        if stderrTail.count > 20 { stderrTail.removeFirst(stderrTail.count - 20) }
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
    nonisolated private static let hostToolExecutor = HostToolExecutor(policy: .app)

    nonisolated private static func executeHostTool(
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
        let row: AgentTranscriptRow = asUser ? .user(trimmed) : .system(trimmed)
        return inject(trimmed, row: row)
    }

    /// `/chat`'s answer: injected into the main agent's context with the
    /// `→ consulted:` marker (so the main agent knows its provenance), but
    /// rendered as its own `.consulted` panel — a delegated artifact, not
    /// the main agent's prose.
    @discardableResult
    func sendConsulted(_ answer: String, worker: WorkerId) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let wireText = "→ consulted: \(trimmed)"
        return inject(wireText, row: .consulted(worker, trimmed))
    }

    private func inject(_ wireText: String, row: AgentTranscriptRow) -> Bool {
        guard canSend, !wireText.isEmpty, let process,
              let pipe = process.standardInput as? Pipe else { return false }
        transcript.append(row)
        // A new turn starts with honest zeros: the previous turn's ratcheted
        // rates would mislead ("Prompt 1200" while prefill is actually 0) in
        // the brief window before fresh status events arrive.
        lastPrefillTPS = 0
        lastGenTPS = 0
        // Baseline nil: the decode average starts at the FIRST generating
        // snapshot of this turn (the previous turn's trailing status was the
        // old baseline, which the engine's per-turn counter reset made garbage
        // from turn 2 on).
        decodeAccumulator = DecodeAccumulator()
        state = .generating
        sentInterrupt = false
        // D12: open the turn's outcome record with the app-known facts the
        // wire cannot carry. sampler is "engine-defaults": the app passes no
        // sampler flags (D10's think default is the engine's too).
        outcomeBuilder = TurnOutcomeBuilder(
            model: settings.modelPath.lastPathComponent,
            build: buildSHA,
            sampler: "engine-defaults",
            task: wireText
        )
        // Single escaping choke point: the engine splits stdin on newlines and
        // parses each line as its own prompt (ds4_agent.c), so everything the
        // orchestrator receives goes through PoolPrompt's JSON encoder — a
        // multi-line prompt or consult answer becomes one escaped line.
        let line = PoolPrompt(worker: .orchestrator, text: wireText).encode() + "\n"
        pipe.fileHandleForWriting.write(Data(line.utf8))
        return true
    }

    /// D5: interrupt = write one ETX byte (0x03) to the child's stdin. The
    /// engine latches it, emits an interrupted `finish` when mid-block, and
    /// returns to idle; the controller reflects that via the wire.
    func interrupt() {
        guard isGenerating, let process,
              let pipe = process.standardInput as? Pipe else { return }
        sentInterrupt = true
        pipe.fileHandleForWriting.write(Data([0x03]))
    }

    func stopAgent() {
        guard state != .stopped else { return }
        state = .stopping
        stdoutTask?.cancel()
        stderrTask?.cancel()
        startupTimeoutTask?.cancel()
        memoryTask?.cancel()
        // EOF on stdin first (the same clean-exit shape as swiftstar-drive):        // the engine's non-interactive loop exits on EOF rather than relying
        // on SIGTERM alone.
        if let pipe = process?.standardInput as? Pipe {
            try? pipe.fileHandleForWriting.close()
        }
        process?.terminate()
        // The termination handler lands on .stopped (its guard passes: state
        // is .stopping, not .stopped) after recording the exit.
    }

    /// Stop, wait for the termination handler to land `.stopped`, then start
    /// again. `startAgent()` refuses any state but `.stopped`/`.failed`, so a
    /// restart cannot call it directly after `stopAgent()` (state is still
    /// `.stopping`); it waits on the transition. The Settings escape hatch
    /// (P19.1 D4): the engine lifecycle stays implicit in the main surface.
    func restartAgent() {
        switch state {
        case .stopped, .failed:
            startAgent()
        default:
            stopAgent()
            restartTask?.cancel()
            restartTask = Task { @MainActor [weak self] in
                while self?.state != .stopped && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard !Task.isCancelled, let self else { return }
                self.startAgent()
            }
        }
    }

    func orchestrateStub() {
        transcript.appendSystem("→ orchestrate: the coordination loop lands with P20 (P19.1 ships the command, not the loop)")
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
        transcript.appendSystem("→ consulting: \(trimmed)")
        let packet = HandoffPacket(
            taskText: trimmed, writableFiles: writableFiles, validationCommand: nil,
            baselines: [:], turnBudget: 100_000, toolCallBudget: 64)
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
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", workspace.path, "rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus == 0,
               let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return URL(fileURLWithPath: trimmed) }
            }
        } catch {}
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

