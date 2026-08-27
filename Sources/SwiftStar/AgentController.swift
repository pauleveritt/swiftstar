import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit
import CryptoKit
import Darwin

/// The agent child's lifecycle + turn state. Unlike the server's `Supervisor`
/// state machine, the agent wire carries no explicit turn-end event: the
/// turn-end `ready` is the single gate (D6) — `status.state → idle` is a
/// precursor, not the gate (see consumeWire).
@MainActor
@Observable
final class AgentController {
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
    /// `nonisolated(unsafe)`: mutated only on MainActor; deinit (nonisolated in
    /// Swift 6) reads it to cancel the poll.
    nonisolated(unsafe) private var memoryTask: Task<Void, Never>?
    /// The `lastStatus` captured when a turn starts: the denominator of the
    /// turn's decode-rate average (Δgenerated / Δts over the turn). nil when
    /// the turn started before any status event (no fabricated average).
    private var turnBaselineStatus: StatusSnapshot?

    /// The running agent's pid, if the child process is alive.
    var runningPid: pid_t? { process?.processIdentifier }
    /// The last completed turn's outcome record (D12); the full trail goes to
    /// the SWIFTSTAR_LOG file. Persistence beyond that is P9/P10 work.
    private(set) var lastTurnOutcome: TurnOutcome?
    /// P10: the last dispatched attempt's outcome (candidate ref or receipt),
    /// the error on infrastructure failure, and the dispatching flag. The
    /// Dispatch tab observes these; `dispatchAttempt` runs the turn on a
    /// detached task (the wire drain blocks) and marshals the result back.
    private(set) var dispatchOutcome: DispatchOutcome?
    private(set) var dispatchError: String?
    private(set) var isDispatching = false
    @ObservationIgnored private var dispatchTask: Task<Void, Never>?
    var settings: AgentSettings
    /// P11 (D1): the pool scheduler state — enqueued workers, the running
    /// worker, and receipts awaiting delivery back into the orchestrator.
    private(set) var poolState = PoolState(workerCapacity: 1)
    /// P11 (D6): the rolling digest — the objective-independent reduced form
    /// of the session, maintained incrementally as host facts arrive.
    private(set) var rollingDigest = RollingDigest()

    nonisolated(unsafe) private var process: Process?
    private var parser = PoolWireParser()
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var generation = 0
    // D12 turn-outcome state.
    private var outcomeBuilder: TurnOutcomeBuilder?
    // P11 (D4) worker-turn state: the in-flight worker's packet (its
    // writableFiles confine the worker's mutations), outcome builder, and id.
    private var activeWorkerPacket: HandoffPacket?
    private var workerOutcomeBuilder: TurnOutcomeBuilder?
    private var activeWorkerId: WorkerId?
    /// P11: the in-flight worker's disposable worktree — its file mutations
    /// land here, never in the caller's tree (the P10 isolation guarantee).
    private var activeWorkerWorktree: WorktreeDispatcher.Worktree?
    private var sentInterrupt = false
    private var buildSHA = "unknown"
    nonisolated(unsafe) private let logHandle: FileHandle?

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
    }

    deinit {
        // @MainActor deinit is nonisolated; Process.terminate is safe off-main.
        process?.terminate()
        memoryTask?.cancel()
        try? logHandle?.close()
    }

    var canSend: Bool { state == .ready }
    var isGenerating: Bool { state == .generating }
    /// The agent is up and serving — the state in which the bottom bar's
    /// telemetry readout (rates, rings) is meaningful.
    var isUp: Bool { state == .ready || state == .generating }

    static func defaultSettings() -> AgentSettings {
        let defaults = UserDefaults.standard
        let engineDir: URL
        if let dir = defaults.string(forKey: "engineDir"), !dir.isEmpty {
            engineDir = URL(fileURLWithPath: dir)
        } else if let dir = ProcessInfo.processInfo.environment["DS4_DIR"] {
            engineDir = URL(fileURLWithPath: dir)
        } else {
            engineDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("external/ds4")
        }
        // P13: resolve the model through the shared resolver, so a selected
        // variant takes precedence over the legacy path (M1), with the hardcoded
        // Laguna default only as the final fallback.
        let modelPath = VariantResolver.resolveModelFile(
            selectedVariantID: defaults.string(forKey: "selectedVariantID"),
            modelPath: defaults.string(forKey: "modelPath"),
            envModel: ProcessInfo.processInfo.environment["SWIFTSTAR_MODEL"],
            fallback: URL(fileURLWithPath: "/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf")
        ).url
        let contextSize = defaults.object(forKey: "contextSize") as? Int ?? 51_200
        let workspace: URL
        if let dir = defaults.string(forKey: "agentWorkspace"), !dir.isEmpty {
            workspace = URL(fileURLWithPath: dir)
        } else if let project = AgentController.projectRoot() {
            // During development the app is launched from the checkout; confine
            // the agent to the repo by default instead of the whole home dir.
            workspace = project
        } else {
            workspace = FileManager.default.homeDirectoryForCurrentUser
        }
        // D2: the app's default posture is deny — shell off until granted.
        let shellAllowed = defaults.bool(forKey: "agentShellAllowed")
        return AgentSettings(
            engineDir: engineDir,
            modelPath: modelPath,
            contextSize: contextSize,
            workspace: workspace,
            shellAllowed: shellAllowed
        )
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
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("SwiftStar")
        }
        return base.appendingPathComponent("captures/live/\(name)", isDirectory: true)
    }

    /// The P5-provenance shape, written once at spawn (the manifest that lets a
    /// reader trust and reproduce the capture).
    private static func renderLiveProvenance(model: String, build: String, workspace: String, at dir: URL) throws {
        let iso = ISO8601DateFormatter().string(from: Date())
        let text = """
        # Live session provenance

        - Model: `\(model)`
        - Build (`external/ds4` SHA): `\(build)`
        - Workspace: `\(workspace)`
        - Started (wall-clock): \(iso)

        Captured live by the SwiftStar app (agent session). `wire.ndjson` and
        `agent.stderr` are the verbatim raw streams; `agent.trace` is the engine's
        `--trace` channel. Wire `ts` is monotonic-since-boot (deltas only); this
        file anchors wall-clock.
        """
        try text.write(to: dir.appendingPathComponent("provenance.md"), atomically: true, encoding: .utf8)
    }

    func startIfNeeded() {
        if state == .stopped { startAgent() }
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
            selectedVariantID: UserDefaults.standard.string(forKey: "selectedVariantID")) {
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
        turnBaselineStatus = nil
        outcomeBuilder = nil
        sentInterrupt = false
        // D12: the build identification is resolved once per spawn (the
        // submodule SHA — the same fact the capture provenance records).
        buildSHA = AgentController.submoduleSHA(settings.engineDir)

        // Live session capture (P7's deferred "live wiring", scoped 2026-08-26):
        // persist the agent's wire + trace + stderr so the session can be read
        // from disk — analysing prompts, tool calls, context — without
        // SWIFTSTAR_LOG. The trace is written by the engine itself via
        // `--trace`; the wire/stderr are teed in the drain loops below.
        let captureDir = Self.captureDirectory()
        try? FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
        try? Self.renderLiveProvenance(
            model: settings.modelPath.lastPathComponent, build: buildSHA,
            workspace: settings.workspace.path, at: captureDir)
        settings.tracePath = captureDir.appendingPathComponent("agent.trace")
        let captureWireURL = captureDir.appendingPathComponent("wire.ndjson")
        let captureStderrURL = captureDir.appendingPathComponent("agent.stderr")
        // `FileHandle(forWritingAtPath:)` opens an existing file — it does not
        // create one. The drains open it lazily, so create the empty files here
        // or the tees silently write nothing for the whole session.
        FileManager.default.createFile(atPath: captureWireURL.path, contents: nil)
        FileManager.default.createFile(atPath: captureStderrURL.path, contents: nil)

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
        process.arguments = AgentCommand.argv(settings: settings) + ["--subagent-pool", "2"]
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

        stdoutTask?.cancel()
        stdoutTask = Task.detached(priority: .utility) { [weak self] in
            let handle = stdoutPipe.fileHandleForReading
            let capture = FileHandle(forWritingAtPath: captureWireURL.path)
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }  // EOF: the child closed stdout
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    try? capture?.seekToEnd()
                    try? capture?.write(lineData)
                    try? capture?.write(Data([0x0A]))
                    let line = String(decoding: lineData, as: UTF8.self)
                    await self?.consumeWire(line, generation: gen)
                }
            }
            try? capture?.close()
        }

        stderrTask?.cancel()
        stderrTask = Task.detached(priority: .utility) { [weak self] in
            let handle = stderrPipe.fileHandleForReading
            let capture = FileHandle(forWritingAtPath: captureStderrURL.path)
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    try? capture?.seekToEnd()
                    try? capture?.write(lineData)
                    try? capture?.write(Data([0x0A]))
                    let line = String(decoding: lineData, as: UTF8.self)
                    await self?.consumeStderr(line, generation: gen)
                }
            }
            try? capture?.close()
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

    private func consumeWire(_ line: String, generation: Int) {
        guard generation == self.generation else { return }
        guard let poolEvent = parser.feed(line) else { return }
        let event = poolEvent.event

        // P11 (D1/D4): worker-tagged events belong to the in-flight worker
        // turn, not the orchestrator's transcript/outcome.
        if poolEvent.worker != .orchestrator {
            handleWorkerEvent(worker: poolEvent.worker, event: event)
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
            lastStatus = snapshot
            lastPrefillTPS = AgentStatusText.ratchet(previous: lastPrefillTPS, new: snapshot.prefillTPS)
            lastGenTPS = AgentStatusText.ratchet(previous: lastGenTPS, new: snapshot.genTPS)
            break
        case .ready(let plannedBytes, _, _, _):
            if let plannedBytes {
                lastPlannedModel = settings.modelPath.lastPathComponent
                lastPlannedBytes = plannedBytes
            }
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
                log("turn outcome: \(outcome)")
                // Freeze the turn's summary onto its reply bubble: the decode
                // average over the turn (Δgenerated/Δts) when the counters
                // advanced, else the engine-reported rate — never a fabricated
                // average. `promptTPS` is the turn-end ratchet, matching the
                // status bar's readout.
                let decodeTPS: Double?
                if let first = turnBaselineStatus, let last = lastStatus {
                    decodeTPS = TurnSummary.averageDecodeTPS(first: first, last: last)
                } else {
                    decodeTPS = nil
                }
                let summary = TurnSummary(
                    promptTPS: lastPrefillTPS,
                    decodeTPS: decodeTPS ?? lastGenTPS,
                    generatedTokens: outcome.generatedTokens,
                    ctxUsed: outcome.ctxUsed)
                transcript.attachSummary(summary)
                turnBaselineStatus = nil
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
                // this is synchronous (the stdout drain awaits consumeWire per
                // line; the engine emits one request then blocks).
                let response = ToolCallbackResponder.respond(
                    idx: idx, name: name, params: params,
                    workspace: settings.workspace, shellAllowed: settings.shellAllowed,
                    execute: Self.executeHostTool)
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
        try? logHandle.seekToEnd()
        try? logHandle.write(contentsOf: data)
    }

    /// Write one `tool_result` line to the engine's stdin (the single sink for
    /// both the P9 responder path and the P11 dispatch path).
    private func writeToolResult(_ response: ToolCallbackResponse) {
        if let pipe = process?.standardInput as? Pipe {
            pipe.fileHandleForWriting.write(
                Data((ToolCallbackResponder.resultLine(response) + "\n").utf8))
        }
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
        activeWorkerId = worker
        activeWorkerPacket = packet
        activeWorkerWorktree = worktree
        workerOutcomeBuilder = TurnOutcomeBuilder(
            model: settings.modelPath.lastPathComponent,
            build: buildSHA,
            sampler: "engine-defaults",
            task: packet.taskText)
        if let pipe = process?.standardInput as? Pipe {
            pipe.fileHandleForWriting.write(
                Data((PoolPrompt(worker: worker, text: packet.taskText).encode() + "\n").utf8))
        }
        log("worker \(worker.rawValue): turn started (worktree \(worktree.url.lastPathComponent))")
    }

    /// Route one worker-tagged event through the worker's turn (D4): answer its
    /// tool requests (revision-checked against its packet's writableFiles), and
    /// finish the turn on its `ready`.
    private func handleWorkerEvent(worker: WorkerId, event: AgentEvent) {
        workerOutcomeBuilder?.apply(event)
        switch event {
        case .toolRequest(let idx, let name, let params):
            let response = ToolCallbackResponder.respond(
                idx: idx, name: name, params: params,
                workspace: activeWorkerWorktree?.url ?? settings.workspace,
                shellAllowed: false,
                writableFiles: activeWorkerPacket?.writableFiles,
                execute: Self.executeHostTool)
            writeToolResult(response)
            workerOutcomeBuilder?.recordHostVerdict(
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
            if let builder = workerOutcomeBuilder {
                let outcome = builder.finish()
                workerOutcomeBuilder = nil
                finishWorkerTurn(worker: worker, outcome: outcome)
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
    private func finishWorkerTurn(worker: WorkerId, outcome: TurnOutcome) {
        // Stash the worker's text: `/orchestrate` surfaces it as the answer
        // (for a read-only worker the text IS the value, not the verdict).
        workerAnswers[worker] = outcome.text
        let packet = activeWorkerPacket ?? HandoffPacket(
            taskText: "", writableFiles: [], validationCommand: nil,
            baselines: [:], turnBudget: 0, toolCallBudget: 0)
        let receipt: DispatchReceipt
        if let worktree = activeWorkerWorktree {
            let repo = Self.resolveRepoRoot(from: settings.workspace)
            let relativized = WorktreeDispatch.relativize(outcome: outcome, worktree: worktree.url)
            do {
                let validation = try WorktreeDispatcher.runValidation(packet.validationCommand, in: worktree.url)
                let dispatchOutcome = try WorktreeDispatcher.finalize(
                    worktree, packet: packet, turnOutcome: relativized,
                    validation: validation, in: repo)
                switch dispatchOutcome {
                case .candidate(let ref, _, _):
                    receipt = DispatchReceipt(worker: worker, ref: ref, reason: nil,
                        summary: "candidate: \(relativized.mutations.count) mutation(s), \(relativized.generatedTokens) tokens")
                case .receipt(let r):
                    receipt = DispatchReceipt(worker: worker, ref: nil,
                        reason: Self.receiptReason(r), summary: Self.receiptReason(r))
                }
            } catch {
                receipt = DispatchReceipt(worker: worker, ref: nil,
                    reason: "infrastructure failure", summary: "\(error)")
            }
            WorktreeDispatcher.discard(worktree, in: repo)
        } else {
            // No worktree (prepare failed earlier): fall back to the pure verdict.
            switch WorktreeDispatch.verdict(
                packet: packet, allowedMutations: outcome.mutations,
                turnOutcome: outcome, validation: nil) {
            case .candidate:
                receipt = DispatchReceipt(worker: worker, ref: nil, reason: nil,
                    summary: "candidate: \(outcome.mutations.count) mutation(s), \(outcome.generatedTokens) tokens")
            case .receipt(let reason):
                receipt = DispatchReceipt(worker: worker, ref: nil,
                    reason: Self.receiptReason(reason), summary: Self.receiptReason(reason))
            }
        }
        poolState = PoolScheduler.apply(poolState, .workerFinished(worker, receipt))
        rollingDigest = RollingDigestReducer.record(rollingDigest, receipt: receipt)
        activeWorkerId = nil
        activeWorkerPacket = nil
        activeWorkerWorktree = nil
        log("worker \(worker.rawValue): \(receipt.summary)")
        drainQueuedWorkers()
    }

    /// Inject any undelivered receipts back into the orchestrator as its next
    /// turn's prompt (D4): the orchestrator sees only the bounded receipts, not
    /// the worker transcripts.
    private func injectPendingReceipts() {
        // Orchestrate-initiated workers surface their text directly (see
        // `orchestrate`); skip their receipts so the orchestrator isn't sent
        // both a verdict AND the text.
        let receipts = poolState.pendingDelivery.values
            .filter { !orchestrateWorkers.contains($0.worker) }
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
    /// the responder injects. It runs the six tool families under the
    /// consent-cleared grant: `read`/`more`/`write`/`list`/`edit`/`search` read
    /// or mutate files at `request.resolvedPath` (already confined by the
    /// consent check); `bash` runs the command in the workspace cwd. The `ok`
    /// verdict is the executor's own (true = ran, false = could not run); a
    /// consent refusal never calls this. For `bash` the host facts ride along:
    /// the exit status, a SHA-256 digest of stdout, and `validationRan` (the
    /// host ran the command and can report its exit). `bash_status`/`bash_stop`
    /// are not yet implemented in host mode (a fresh `Process` would re-run /
    /// re-stop instead of polling / stopping a job) — the executor refuses them
    /// with `ok:false` rather than mis-executing; the real job protocol is
    /// P10+ hardening.
    /// `nonisolated` — touches only `FileManager`/`Process` (not `self`); the
    /// synchronous run blocks the main actor during a `bash` call, which P9's
    /// scope accepts (the engine blocks on the result line anyway).
    nonisolated private static func executeHostTool(
        _ request: ToolExecutionRequest
    ) -> ToolExecutionResult {
        switch request.name {
        case "read", "more":
            guard let path = AgentController.confinedRealPath(request) else {
                return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
            }
            guard let data = FileManager.default.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8) else {
                return ToolExecutionResult(ok: false, text: "error: could not read \(path)")
            }
            return ToolExecutionResult(ok: true, text: text)

        case "list":
            guard let path = AgentController.confinedRealPath(request) else {
                return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
            }
            do {
                let entries = try FileManager.default.contentsOfDirectory(atPath: path)
                return ToolExecutionResult(ok: true, text: entries.sorted().joined(separator: "\n"))
            } catch {
                return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
            }

        case "search":
            guard let path = AgentController.confinedRealPath(request) else {
                return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
            }
            let query = request.params.first(where: { $0.name == "query" })?.value ?? ""
            var caseSensitive = true
            if let v = request.params.first(where: { $0.name == "case_sensitive" })?.value {
                caseSensitive = v != "false" && v != "0"
            }
            let matches = AgentController.searchRecursive(
                root: path, query: query, caseSensitive: caseSensitive, maxResults: 50)
            if matches.isEmpty {
                return ToolExecutionResult(ok: true, text: "No matches\n")
            }
            let header = "\(matches.count) match\(matches.count == 1 ? "" : "es") shown\n\n"
            return ToolExecutionResult(ok: true, text: header + matches.joined(separator: "\n"))

        case "write":
            guard let path = AgentController.confinedRealPath(request) else {
                return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
            }
            let content = request.params.first(where: { $0.name == "content" })?.value ?? ""
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                return ToolExecutionResult(ok: true, text: "wrote \(path)", mutations: [path])
            } catch {
                return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
            }

        case "edit":
            guard let path = AgentController.confinedRealPath(request) else {
                return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
            }
            let old = request.params.first(where: { $0.name == "old" })?.value ?? ""
            let new = request.params.first(where: { $0.name == "new" })?.value ?? ""
            guard !old.isEmpty else {
                return ToolExecutionResult(ok: false, text: "error: edit requires non-empty old text")
            }
            guard let data = FileManager.default.contents(atPath: path),
                  var text = String(data: data, encoding: .utf8) else {
                return ToolExecutionResult(ok: false, text: "error: could not read \(path)")
            }
            guard let range = text.range(of: old) else {
                return ToolExecutionResult(ok: false, text: "error: old text not found in \(path)")
            }
            text.replaceSubrange(range, with: new)
            do {
                try text.write(toFile: path, atomically: true, encoding: .utf8)
                return ToolExecutionResult(ok: true, text: "edited \(path)", mutations: [path])
            } catch {
                return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
            }

        case "bash":
            let command = request.params.first(where: { $0.name == "command" })?.value ?? ""
            guard !command.isEmpty else {
                return ToolExecutionResult(ok: false, text: "error: bash requires command")
            }
            // SubprocessRunner drains stdout/stderr concurrently and enforces a
            // timeout (F1: waitUntilExit-before-read deadlocks on a full pipe).
            let r: SubprocessRunner.Result
            do {
                r = try SubprocessRunner.run(command, in: request.workspace)
            } catch {
                return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
            }
            let combined = r.stdout + (r.stderr.isEmpty ? "" : r.stderr)
            let digest = "sha256:" + SHA256.hash(data: Data(r.stdout.utf8))
                .map { String(format: "%02x", $0) }.joined()
            return ToolExecutionResult(
                ok: r.exit == 0 && !r.timedOut,
                text: combined,
                exitStatus: Int(r.exit),
                outputDigest: digest, validationRan: true)

        case "bash_status", "bash_stop":
            // Not yet implemented in host mode: a fresh `Process` would re-run
            // the command (bash_status) or re-run instead of stopping
            // (bash_stop) — mis-execution, not a real poll/stop. Refuse loudly
            // (ok:false) so the agent sees the limitation and can fall back to a
            // plain `bash` with a short timeout. The real job protocol
            // (long-lived bash jobs + status/stop) is P10+ hardening.
            return ToolExecutionResult(
                ok: false,
                text: "bash_status/bash_stop are not yet implemented in host mode; use a plain bash with a short timeout")

        default:
            return ToolExecutionResult(ok: false, text: "error: unknown tool \(request.name)")
        }
    }

    /// Belt-and-suspenders re-confinement for the executor: the pure `consent`
    /// check resolves `..` but not symlinks (no I/O); the engine's confinement
    /// uses `realpath`, which does. A symlink under the workspace that points
    /// outside would pass the pure check but escape the grant on execution — this
    /// resolves symlinks on both the workspace and the file and refuses when the
    /// real path is outside the real workspace root. The same rules P7 put in
    /// the engine (D1), enforced host-side. Returns the symlink-resolved
    /// absolute path, or nil on refusal.
    nonisolated private static func confinedRealPath(_ request: ToolExecutionRequest) -> String? {
        guard let path = request.resolvedPath else { return nil }
        let wsReal = request.workspace.resolvingSymlinksInPath()
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard resolved.path == wsReal.path || resolved.path.hasPrefix(wsReal.path + "/") else {
            return nil
        }
        return resolved.path
    }

    /// Recursive grep for the `search` executor: walks `root` depth-first, reads
    /// each regular file as UTF-8, and collects `path:lineNo:line` for lines
    /// containing `query` (substring; case-sensitive unless `caseSensitive` is
    /// false), capped at `maxResults` matches. Skips unreadable/binary files.
    nonisolated private static func searchRecursive(
        root: String, query: String, caseSensitive: Bool, maxResults: Int
    ) -> [String] {
        guard !query.isEmpty else { return [] }
        let fm = FileManager.default
        var results: [String] = []
        let enumerator = fm.enumerator(atPath: root)
        while let entry = enumerator?.nextObject() as? String {
            if results.count >= maxResults { break }
            let full = (root as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir),
                  !isDir.boolValue else { continue }
            guard let data = fm.contents(atPath: full),
                  let text = String(data: data, encoding: .utf8) else { continue }
            let needle = caseSensitive ? query : query.lowercased()
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if results.count >= maxResults { break }
                let hay = caseSensitive ? String(line) : String(line).lowercased()
                if hay.contains(needle) {
                    results.append("\(entry):\(i + 1):\(line)")
                }
            }
        }
        return results
    }

    @discardableResult
    func send(_ prompt: String, asUser: Bool = true) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !trimmed.isEmpty, let process,
              let pipe = process.standardInput as? Pipe else { return false }
        // The composer's own prompts render as user pills; internal traffic
        // (worker receipts injected into the orchestrator's next turn) is a
        // quiet system row — the user never typed it, so it must not look like
        // they did.
        if asUser {
            transcript.appendUser(trimmed)
        } else {
            transcript.appendSystem(trimmed)
        }
        // A new turn starts with honest zeros: the previous turn's ratcheted
        // rates would mislead ("Prompt 1200" while prefill is actually 0) in
        // the brief window before fresh status events arrive.
        lastPrefillTPS = 0
        lastGenTPS = 0
        // Capture the turn's start counters for the decode-rate average.
        turnBaselineStatus = lastStatus
        state = .generating
        sentInterrupt = false
        // D12: open the turn's outcome record with the app-known facts the
        // wire cannot carry. sampler is "engine-defaults": the app passes no
        // sampler flags (D10's think default is the engine's too).
        outcomeBuilder = TurnOutcomeBuilder(
            model: settings.modelPath.lastPathComponent,
            build: buildSHA,
            sampler: "engine-defaults",
            task: trimmed
        )
        pipe.fileHandleForWriting.write(Data((trimmed + "\n").utf8))
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

    // MARK: - P10 dispatched attempt (D2/D3/D4)

    /// The wall-clock safety net for a dispatched turn (the packet's token/tool
    /// budgets are a post-hoc verdict; this catches a runaway that never emits
    /// a turn-end `ready`). `cancelDispatch()` is the responsive path.
    private nonisolated static let dispatchTurnTimeout: TimeInterval = 600

    func dispatchAttempt(packet: HandoffPacket) {
        guard !isDispatching else { return }
        isDispatching = true
        dispatchOutcome = nil
        dispatchError = nil
        let baseSettings = settings
        let workspace = settings.workspace
        dispatchTask = Task.detached { [weak self] in
            let repo = Self.resolveRepoRoot(from: workspace)
            do {
                let outcome = try WorktreeDispatcher.dispatch(
                    packet: packet, in: repo) { enrichedPacket, worktree in
                    try Self.runDispatchedTurn(
                        packet: enrichedPacket, worktree: worktree, baseSettings: baseSettings)
                }
                await MainActor.run {
                    self?.dispatchOutcome = outcome
                    self?.dispatchError = nil
                    self?.isDispatching = false
                }
            } catch {
                await MainActor.run {
                    self?.dispatchError = "\(error)"
                    self?.isDispatching = false
                }
            }
        }
    }

    @ObservationIgnored private var orchestrateWatchTask: Task<Void, Never>?
    /// Workers enqueued by `/orchestrate`: their result is surfaced as the
    /// worker's text (not a receipt), and their receipt is not auto-injected
    /// into the orchestrator (the text is the value, not a verdict).
    private var orchestrateWorkers: Set<WorkerId> = []
    /// The worker's final text per completed turn, for orchestrate surfacing.
    private var workerAnswers: [WorkerId: String] = [:]

    func orchestrate(task: String, writableFiles: [String]) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let workerId = PoolScheduler.availableWorker(poolState) else {
            transcript.appendSystem("→ orchestrate refused: subagent pool is busy")
            return
        }
        guard state == .ready else {
            transcript.appendSystem("→ orchestrate refused: agent not idle")
            return
        }
        transcript.appendSystem("→ orchestrating: \(trimmed)")
        let packet = HandoffPacket(
            taskText: trimmed, writableFiles: writableFiles, validationCommand: nil,
            baselines: [:], turnBudget: 100_000, toolCallBudget: 64)
        poolState = PoolScheduler.apply(poolState, .enqueue(packet: packet))
        orchestrateWorkers.insert(workerId)
        // Run the worker now in the SAME engine (a context-isolated session) —
        // no second model process, so the dispatchAttempt hang class is gone.
        drainQueuedWorkers()
        orchestrateWatchTask?.cancel()
        orchestrateWatchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.poolState.completed[workerId] == nil && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            let answer = self.workerAnswers[workerId]
                ?? self.poolState.completed[workerId]?.summary
                ?? "done"
            self.orchestrateWorkers.remove(workerId)
            if self.poolState.pendingDelivery[workerId] != nil {
                self.poolState = PoolScheduler.apply(self.poolState, .receiptInjected(workerId))
            }
            let message = "→ orchestrated: \(answer)"
            if !self.send(message, asUser: false) {
                self.transcript.appendSystem(message)
            }
        }
    }

    /// Cancel an in-flight dispatch: cancel the detached task (the drain's
    /// `Task.isCancelled` check aborts within the 1s poll window) and let the
    /// task's catch land the error. The worktree is removed by `dispatch`'s
    /// defer; the agent process is terminated by `runDispatchedTurn`'s defer.
    func cancelDispatch() {
        dispatchTask?.cancel()
    }

    /// Run one dispatched turn in `worktree` (D2): spawn a fresh, ephemeral
    /// `ds4-agent` at `--workspace <worktree>` with shell off and host-tools on
    /// (P9), send `packet.taskText` as the prompt, drain the wire answering each
    /// `.toolRequest` through the responder with the `writableFiles` revision
    /// check, and return the P9 `TurnOutcome` carrying the observed mutations —
    /// relativized to the worktree so the pure verdict can compare them against
    /// `packet.writableFiles` (which are worktree-relative). The first `ready`
    /// is the idle handshake (send the prompt); a subsequent `ready` is the
    /// turn end (finish the record). `nonisolated` — touches only `Process`/
    /// `FileManager` (not `self`); the synchronous drain blocks the detached
    /// task, which is the point (the wire is synchronous per request).
    nonisolated static func runDispatchedTurn(
        packet: HandoffPacket, worktree: URL, baseSettings: AgentSettings
    ) throws -> TurnOutcome {
        let settings = AgentSettings(
            engineDir: baseSettings.engineDir,
            modelPath: baseSettings.modelPath,
            contextSize: baseSettings.contextSize,
            workspace: worktree,
            shellAllowed: false,        // D2: shell off for the dispatched attempt
            systemPrompt: nil)          // minimal: the task text carries the instructions
        let binary = AgentCommand.binaryPath(settings: settings)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw DispatchAttemptError.agentBinaryMissing(binary.path)
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = AgentCommand.argv(settings: settings)
        process.currentDirectoryURL = settings.engineDir
        process.environment = AgentCommand.engineEnvironment(
            engineDir: settings.engineDir, lockFile: "/tmp/ds4-agent-dispatch.lock",
            base: ProcessInfo.processInfo.environment)
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        defer {
            try? stdinPipe.fileHandleForWriting.close()
            process.terminate()
        }

        let stdin = stdinPipe.fileHandleForWriting
        let fd = stdoutPipe.fileHandleForReading.fileDescriptor
        let deadline = Date().addingTimeInterval(dispatchTurnTimeout)
        var parser = AgentWireParser()
        var builder: TurnOutcomeBuilder?
        var seenHello = false
        var result: TurnOutcome?
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        loop: while Date() < deadline {
            if Task.isCancelled { throw DispatchAttemptError.cancelled }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pr = Darwin.poll(&pfd, 1, 1000)
            guard pr >= 0 else { continue }  // EINTR; retry
            guard (pfd.revents & Int16(POLLIN)) != 0 || (pfd.revents & Int16(POLLHUP)) != 0 else { continue }
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n <= 0 { break loop }  // EOF: the agent exited (early or cleanly)
            buffer.append(contentsOf: chunk[0..<n])
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                guard let event = parser.feed(line) else { continue }
                builder?.apply(event)
                switch event {
                case .hello:
                    seenHello = true
                case .ready:
                    if builder == nil {
                        // The first `ready` is the idle handshake: the engine
                        // blocks on stdin after emitting it, so the prompt is
                        // the first input. Open the turn's outcome record and
                        // send the task text.
                        builder = TurnOutcomeBuilder(
                            model: settings.modelPath.lastPathComponent,
                            build: "dispatched",
                            sampler: "engine-defaults",
                            task: packet.taskText)
                        let prompt = packet.taskText.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
                        stdin.write(Data(prompt.utf8))
                    } else {
                        // A subsequent `ready` is the turn end. Finish the
                        // record (the wire's stop_reason; nil defaults to .eos)
                        // and relativize the mutations to the worktree so the
                        // pure verdict compares them against `writableFiles`
                        // (which are worktree-relative).
                        let outcome = builder!.finish(appStopReason: nil)
                        result = WorktreeDispatch.relativize(
                            outcome: outcome, worktree: worktree)
                        break loop
                    }
                case .toolRequest(let idx, let name, let params):
                    // P9 host execution + P10 revision check: the responder
                    // confines mutating tools to `packet.writableFiles` (an
                    // out-of-set write is refused, not executed) and records
                    // the host facts; write the `tool_result` line back.
                    let response = ToolCallbackResponder.respond(
                        idx: idx, name: name, params: params,
                        workspace: worktree, shellAllowed: false,
                        writableFiles: packet.writableFiles,
                        execute: Self.executeHostTool)
                    stdin.write(Data((ToolCallbackResponder.resultLine(response) + "\n").utf8))
                    builder?.recordHostVerdict(
                        idx: idx, ok: response.ok,
                        mutations: response.mutations, exitStatus: response.exitStatus,
                        outputDigest: response.outputDigest, validationRan: response.validationRan)
                case .toolRequestRefused(let idx, let reason):
                    // A malformed request must not hang the wire (the engine
                    // blocks on its result): answer `ok:false` so it unblocks.
                    let response = ToolCallbackResponse(
                        idx: idx, ok: false, s: ToolResultCondenser.condense(reason))
                    stdin.write(Data((ToolCallbackResponder.resultLine(response) + "\n").utf8))
                case .refused(let line):
                    throw DispatchAttemptError.handshakeRefused(line)
                default:
                    break
                }
            }
        }
        if Task.isCancelled { throw DispatchAttemptError.cancelled }
        guard let result else {
            throw seenHello ? DispatchAttemptError.turnDidNotEnd : DispatchAttemptError.agentDidNotHandshake
        }
        return result
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

/// Errors thrown by a dispatched attempt on infrastructure failure (a missing
/// agent binary, a wire handshake refusal, the turn never ending, or a
/// cancellation); a validation command exiting non-zero is a `Receipt`, not
/// this error, and a git failure from `WorktreeDispatcher` surfaces as its
/// own `WorktreeDispatcherError`.
enum DispatchAttemptError: Error, Sendable {
    case agentBinaryMissing(String)
    case agentDidNotHandshake
    case handshakeRefused(String)
    case turnDidNotEnd
    case cancelled
}
