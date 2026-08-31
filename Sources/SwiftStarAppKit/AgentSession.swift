import Foundation
import SwiftStarKit

/// The app's single-turn agent loop, lifted out of `AgentController` (eval-cli
/// task 2) so the CLI can spawn and drive a real `ds4-agent` turn without
/// linking SwiftUI. `AgentController` was the ONLY place this loop lived —
/// three eval harnesses each re-implemented it independently and drifted from
/// the app (BRIEF.md). Moving it here means a divergence between what the app
/// runs and what an eval runs becomes a compile error, not a silent
/// difference.
///
/// **Scope (deliberate):** spawn, one turn, the capture. The pool
/// (worker-tagged wire, `dispatch`) loop is NOT here yet — it stays behind
/// `AgentController`'s own `PoolWireParser`/`AgentPoolTurnLoop.swift` until a
/// later task seams it in (`AgentSession.dispatch`, `onWorkerEvent`). Until
/// then this type parses with the plain `AgentWireParser` (no worker tag) and
/// answers `tool_request` itself — including a bare `dispatch` call, which
/// admits (per `ToolCallbackResponder`) but enqueues nothing, since there is
/// no pool state here to enqueue into.
///
/// **Isolation:** `@MainActor`, not because this type touches AppKit/SwiftUI
/// (it does not) but because the loop's post-`await` guards on a tool
/// request's turn-still-current check lean on MainActor serialization for
/// correctness — the same reason `AgentController`'s loop needed it
/// (`AgentController.swift`, historically `:723`). Changing that is a
/// concurrency re-architecture, not a move. `SwiftStarAppKit` sets no
/// `defaultIsolation` (only the `SwiftStar` app target does, in
/// `Package.swift`), so the annotation here is explicit. A CLI host therefore
/// needs an async `main` and must never block the main thread — unlike
/// `swiftstar-drive`/`swiftstar-agenttest`, which block on FDs.
///
/// **The callback surface hands over PARSED events, never raw wire lines**
/// (`onEvent: ((AgentEvent) -> Void)?`): a caller that had to re-parse the
/// wire would have rebuilt the exact duplication this design exists to
/// remove. `onRefusal` exists because a wire-level `.refused` (binding rule
/// 7 — a first line that is not a valid v1 handshake) is a distinct,
/// terminal failure a caller must be able to surface without groveling
/// through `onEvent` for it.
///
/// One instance = one spawn. A restart is a new `AgentSession`, not a reused
/// one (mirrors `AgentController.startAgent`'s "a restart is a fresh wire"
/// invariant) — so there is no `generation` counter to thread through async
/// gaps; `stopped` alone tells a resumed `await` whether it is still safe to
/// touch this session's state.
@MainActor
public final class AgentSession {
    /// Every parsed wire event, in arrival order — hello, status, ready,
    /// text/think/tool (transcript-shaped), and the host-tools
    /// `toolRequest`/`toolRequestRefused` pair (informational here: this type
    /// already answers them before or regardless of notifying — see
    /// `consume`).
    public var onEvent: ((AgentEvent) -> Void)?
    /// Fires once per finished turn — the same `TurnOutcome` `AgentController`
    /// used to build and append to `outcomes.ndjson` itself; that persistence
    /// is now this type's job (see `start`), so a caller need only react.
    public var onOutcome: ((TurnOutcome) -> Void)?
    /// A wire-level refusal (binding rule 7): the first line was not a valid
    /// v1 handshake. Terminal — `stop()` runs before this fires.
    public var onRefusal: ((String) -> Void)?
    public var onStderrLine: ((String) -> Void)?
    /// The child exited — cleanly or not — carrying its exit status and the
    /// last 20 stderr lines (mirrors `AgentController`'s pre-move
    /// `terminationHandler`, which folded the stderr tail into `.failed`).
    /// Not one of the four callbacks the brief names; `AgentController` still
    /// needs to know a spawn died to reproduce its existing failure surface
    /// now that it no longer owns the `Process` itself.
    public var onExit: ((Int32, [String]) -> Void)?
    /// Eval-cli task 3: a worker-tagged wire event (any `worker != .orchestrator`
    /// line). Fired for EVERY event on that worker's stream — hello/status/
    /// text/tool/ready alike, mirroring `onEvent`'s "everything" contract for
    /// the orchestrator — so the app's `AgentPoolTurnLoop` (which stays
    /// app-side: `ActiveWorkerTurn`, the watchdog `Task`, and the worktree
    /// handles cannot leave this target) can drive its own outcome builder,
    /// answer the worker's tool requests, and finish the worker's turn. This
    /// session never answers a worker's `tool_request` itself — only the
    /// orchestrator's own requests are auto-answered in `consume`.
    public var onWorkerEvent: ((WorkerId, AgentEvent) -> Void)?
    /// The `dispatch` tool is a host-control tool, not a normal one (P11 D5):
    /// admitting it means enqueuing a worker into `PoolState`, which stays
    /// app-side (this session owns no scheduler). When the orchestrator's own
    /// wire emits a `dispatch` `tool_request`, `consume` asks this closure for
    /// the admission decision (the app makes it, using its own `poolState`/
    /// `rollingDigest`, and mutates `poolState` itself as a side effect of
    /// computing it) and then answers the wire from the returned `Decision`
    /// via `DispatchAdmission.apply` — which also records the outcome verdict
    /// into this session's own `outcomeBuilder`, since neither half may be
    /// written without the other (the 2026-08-30 dead-letter bug
    /// `DispatchAdmission` exists to prevent). nil (no pool wired to this
    /// session) refuses every dispatch — the sole-turn/CLI default.
    public var onDispatchDecision: ((_ params: [ToolParam]) -> DispatchAdmission.Decision)?
    /// Regression fix (eval-cli task 3): the orchestrator's own tool-answer
    /// verdict (mutations/exitStatus/validationRan), fired right after this
    /// session records it into its own `outcomeBuilder` — mirrors what it
    /// already records there, for the app's `rollingDigest`
    /// (`RollingDigestReducer.recordHostVerdict`), which stays app-side (it
    /// backs `DispatchAdmission.decide`'s own `poolState`-dependent gate).
    /// Task 2 fed `rollingDigest` from every wire event (`applyAgentEvent`)
    /// but never from a tool-answer verdict, since a verdict is only
    /// available from inside this session's own async tool-answer flow — this
    /// callback is that missing feed. Not fired for `dispatch` itself (which
    /// never touched the file digest even pre-move) or for a budget-refused
    /// call routed through `dispatch`'s own branch above.
    public var onToolVerdict: ((_ mutations: [String], _ exitStatus: Int?, _ validationRan: Bool) -> Void)?

    /// The engine's advertised handshake capabilities (P23 D3), recorded so a
    /// per-turn feature field is only ever sent when the engine claimed it —
    /// `send`'s own think-override decision reads this.
    public private(set) var advertisedCaps: Set<String> = []
    /// The spawned child. Exposed (not part of the headless contract the
    /// brief names) only because `AgentPoolTurnLoop.swift` — the app-only
    /// pool loop this task deliberately does not touch (see the type doc) —
    /// still writes worker prompts directly to `AgentController.process`'s
    /// stdin. A later task moves that loop behind this seam and can retire
    /// this property to `private`.
    public private(set) var process: Process?

    private let settings: AgentSettings
    private let tools: [String]
    private let captureDirectory: URL
    private let family: ModelFamily
    /// Eval-cli task 3: `AgentController`'s `sessionCaptureEnabled`
    /// `UserDefaults` toggle, threaded through explicitly rather than read
    /// here (this type touches no `UserDefaults` of its own — the app reads
    /// its own setting and passes the resolved bool). `false` skips creating
    /// `captureDirectory` and every file under it (`wire.ndjson`,
    /// `agent.stderr`, `provenance.md`) — Task 2 had made capture
    /// unconditional, silently re-enabling it for a user who had turned the
    /// app's toggle off.
    private let captureEnabled: Bool
    /// Eval-cli task 3: when set, `start()` spawns the engine with
    /// `--subagent-pool <poolSize>` (`PoolEngine.argv`) instead of the plain
    /// single-session argv, and the wire is parsed with the pool's `worker`
    /// tag. nil (the eval-cli task 2 default) is a plain single-session spawn
    /// — every existing caller is unaffected.
    private let poolSize: Int?
    /// Always a `PoolWireParser`, even outside pool mode: a wire line with no
    /// `worker` field parses as `.orchestrator` (`PoolWireParser.worker(of:)`),
    /// so this is a superset of the old plain `AgentWireParser`, not a
    /// behavior change for a non-pool session — see the type doc.
    private var parser = PoolWireParser()
    private var outcomeBuilder: TurnOutcomeBuilder?
    /// Per-turn cap on host tool calls (P22 GLM review: a runaway model
    /// otherwise loops the host forever). Reset by `send` for each new turn —
    /// verbatim port of `AgentController`'s pre-move `orchestratorToolBudget`.
    private var toolBudget = ToolCallBudgetTracker(budget: ToolCallBudgetTracker.defaultBudget)
    private var sentInterrupt = false
    /// Set once by `stop()`. Every async resumption point (the tool-callback
    /// await in `consume`) re-checks this before touching `outcomeBuilder` or
    /// writing to `process` — the same reentrancy hazard
    /// `AgentController.consumeWire`'s `generation` guard existed for, scoped
    /// to a single instance instead of a restart counter (see the type doc).
    private var stopped = false
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private let hostToolExecutor: HostToolExecutor
    private var stderrTail: [String] = []
    private var buildSHA = "unknown"

    /// `tools` is separate from `settings.tools` on purpose: `settings.tools`
    /// (optional) is what actually reaches argv via `AgentCommand.argv`;
    /// `tools` is the caller's already-resolved list for the `SpawnRecord`'s
    /// `tools` field (eval-cli task 1's declared variable) — a caller building
    /// an eval arm should not have to round-trip through the optional to
    /// describe what it asked for.
    ///
    /// `family` defaults to Laguna S — the same "nothing configured" default
    /// `AgentController.runningModelFamily()` falls back to — and only
    /// matters for `send`'s per-turn think-override decision
    /// (`TurnThinkPolicy.decide`); a caller that resolves a real variant
    /// selection (an app, via `UserDefaults`) passes its own.
    public init(
        settings: AgentSettings, tools: [String], captureDirectory: URL,
        family: ModelFamily = .lagunaS,
        captureEnabled: Bool = true,
        poolSize: Int? = nil
    ) {
        self.settings = settings
        self.tools = tools
        self.captureDirectory = captureDirectory
        self.family = family
        self.captureEnabled = captureEnabled
        self.poolSize = poolSize
        self.hostToolExecutor = HostToolExecutor(policy: .app, contextSize: settings.contextSize)
    }

    /// Spawn the engine and start draining its wire. Returns the `SpawnRecord`
    /// this spawn resolved to (eval-cli task 1's shape — the only thing an
    /// arm-to-arm diff compares); the caller decides what to do with it (the
    /// app renders `provenance.md` itself before this call today — that
    /// responsibility moves here too, see below).
    ///
    /// Binding rule 5: the wire/stderr capture files are created and the
    /// drain tasks tee every line to disk BEFORE `consume`/`consumeStderr` are
    /// ever invoked on that line — a reader of `wire.ndjson` never races a
    /// line that is only in-flight to a callback.
    @discardableResult
    public func start() throws -> SpawnRecord {
        buildSHA = Self.submoduleSHA(settings.engineDir)
        let record = Self.makeSpawnRecord(
            settings: settings, tools: tools, buildSHA: buildSHA,
            captureDirectory: captureDirectory, startedAt: Date())
        // Regression fix (eval-cli task 3): capture is conditional again — a
        // session started with `captureEnabled: false` creates neither the
        // directory nor any file under it, and the drain loops below tee
        // nothing (see `wireCapture`/`stderrCapture` below).
        if captureEnabled {
            try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
            try Self.renderProvenance(record, at: captureDirectory)
        }

        let wireURL = captureDirectory.appendingPathComponent("wire.ndjson")
        let stderrURL = captureDirectory.appendingPathComponent("agent.stderr")
        if captureEnabled {
            FileManager.default.createFile(atPath: wireURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        }

        let binary = AgentCommand.binaryPath(settings: settings)
        let process = Process()
        process.executableURL = binary
        // Regression fix (eval-cli task 3): pool/dispatch was dead because
        // this always spawned the plain single-session argv, never
        // `--subagent-pool` — the engine never hosted a worker session for
        // `dispatch` to address. `poolSize` set threads the same
        // `PoolEngine.argv` the pre-move `PoolOrchestrator` used.
        process.arguments = poolSize.map { PoolEngine.argv(settings: settings, workers: $0) }
            ?? AgentCommand.argv(settings: settings)
        process.currentDirectoryURL = settings.engineDir
        process.environment = AgentCommand.engineEnvironment(
            engineDir: settings.engineDir,
            lockFile: "/tmp/ds4-agent-session-\(ObjectIdentifier(self).hashValue).lock",
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
                self.onExit?(p.terminationStatus, self.stderrTail)
            }
        }
        self.process = process
        try process.run()

        let wireCapture = captureEnabled ? SafeAppendFile(path: wireURL.path) : nil
        let stderrCapture = captureEnabled ? SafeAppendFile(path: stderrURL.path) : nil
        stdoutTask?.cancel()
        stdoutTask = Task.detached(priority: .utility) { [weak self] in
            let handle = stdoutPipe.fileHandleForReading
            var lines = LineBuffer()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }  // EOF: the child closed stdout
                for lineData in lines.append(data) {
                    // The tee happens BEFORE the parse/callback below (binding
                    // rule 5) — see this method's doc. Skipped entirely when
                    // capture is disabled.
                    wireCapture?.append(lineData)
                    wireCapture?.append(Data([0x0A]))
                    let line = String(decoding: lineData, as: UTF8.self)
                    await self?.consume(line)
                }
            }
            _ = lines.finish()
            wireCapture?.close()
        }

        stderrTask?.cancel()
        stderrTask = Task.detached(priority: .utility) { [weak self] in
            let handle = stderrPipe.fileHandleForReading
            var lines = LineBuffer()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                for lineData in lines.append(data) {
                    stderrCapture?.append(lineData)
                    stderrCapture?.append(Data([0x0A]))
                    await self?.consumeStderr(String(decoding: lineData, as: UTF8.self))
                }
            }
            _ = lines.finish()
            stderrCapture?.close()
        }

        return record
    }

    /// Send one prompt as the orchestrator's next turn (`worker` 0 on the
    /// wire, matching `PoolPrompt`'s single authority). Opens this turn's
    /// `TurnOutcomeBuilder` before the write, so every wire event from this
    /// point — including a `ready` that arrives before the write's own bytes
    /// are even flushed — has somewhere to land.
    ///
    /// Deliberately does NOT gate on having seen a prior `hello`/`ready`:
    /// readiness is a UI/product concern (`AgentController.canSend`, driven by
    /// the `state` it tracks off `onEvent`), not this type's — a low-level
    /// engine wrapper should let its owner decide when "ready enough to send"
    /// means, not assume the app's own posture. The only hard requirement is
    /// a live process.
    @discardableResult
    public func send(_ prompt: String, think: ThinkEffort? = nil) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stopped, !trimmed.isEmpty, let process,
              let pipe = process.standardInput as? Pipe else { return false }
        sentInterrupt = false
        let decision = TurnThinkPolicy.decide(
            requested: think, family: family,
            capAdvertised: advertisedCaps.contains(TurnThinkPolicy.overrideCap))
        let effort: ThinkEffort?
        switch decision {
        case .useDefault: effort = nil
        case .override(let e): effort = e
        case .refused: effort = nil
        }
        outcomeBuilder = TurnOutcomeBuilder(
            model: settings.modelPath.lastPathComponent, build: buildSHA,
            task: trimmed, think: effort)
        // A new turn gets a fresh tool-call budget — matches
        // `AgentController.inject`'s pre-move reset exactly.
        toolBudget = ToolCallBudgetTracker(budget: ToolCallBudgetTracker.defaultBudget)
        let line = PoolPrompt(worker: .orchestrator, text: trimmed, think: effort).encode() + "\n"
        pipe.fileHandleForWriting.write(Data(line.utf8))
        return true
    }

    /// Send one `HandoffPacket` as `worker`'s turn on the pooled wire (P11 D4)
    /// — the wire-write half of `AgentPoolTurnLoop.drainQueuedWorkers`, moved
    /// here because it is this session's `Pipe`/`advertisedCaps` that the
    /// write needs. Mirrors `send`'s own per-turn think-override decision
    /// (`TurnThinkPolicy.decide`, gated on `advertisedCaps`) and adds the
    /// worker context clamp (`WorkerContextPolicy.clamp`, D8) `send` has no
    /// analog for, since only a pool worker's context is ever sized
    /// independently of the parent's.
    ///
    /// Deliberately does NOT open an `outcomeBuilder`, and does NOT gate on
    /// `poolSize`/pool mode: a worker's own `TurnOutcomeBuilder`, worktree,
    /// and watchdog stay app-side (`ActiveWorkerTurn`) — this call is only
    /// the raw wire write, the same seam `writeToolResult` already is for
    /// tool results.
    @discardableResult
    public func dispatch(_ packet: HandoffPacket, worker: WorkerId) -> Bool {
        guard !stopped, let process,
              let pipe = process.standardInput as? Pipe else { return false }
        let capAdvertised = advertisedCaps.contains(TurnThinkPolicy.overrideCap)
        let decision = TurnThinkPolicy.decide(
            requested: TurnThinkPolicy.effort(for: packet.sampling.think),
            family: family, capAdvertised: capAdvertised)
        let effort: ThinkEffort?
        switch decision {
        case .useDefault: effort = nil
        case .override(let e): effort = e
        case .refused: effort = nil
        }
        // Sent only when the cap is advertised: an engine that never claimed
        // the ctx key would treat the envelope's extra field as unknown and
        // run at the parent's context, which is a silent budget overrun.
        let workerCtx: Int? = capAdvertised
            ? WorkerContextPolicy.clamp(requested: settings.workerContextSize,
                                        parentContext: settings.contextSize)
            : nil
        let line = PoolPrompt(worker: worker, text: packet.taskText,
                              think: effort, contextSize: workerCtx).encode() + "\n"
        pipe.fileHandleForWriting.write(Data(line.utf8))
        return true
    }

    /// Write one `tool_result` line to the engine's stdin — the single sink
    /// for a host-answered `tool_request`. `write(contentsOf:)`, not
    /// `write(_:)`: the latter RAISES on a closed/broken pipe, which `try?`
    /// cannot catch (`AgentController`'s original doc comment on this exact
    /// method — the lesson carries over unchanged).
    public func writeToolResult(_ response: ToolCallbackResponse) {
        guard let pipe = process?.standardInput as? Pipe else { return }
        try? pipe.fileHandleForWriting.write(
            contentsOf: Data((ToolCallbackResponder.resultLine(response) + "\n").utf8))
    }

    /// D5: interrupt = one ETX byte (0x03) on the child's stdin. Gated on a
    /// turn actually being open (`outcomeBuilder != nil`) — the local
    /// equivalent of `AgentController.isGenerating`, since this type tracks no
    /// broader `state`.
    public func interrupt() {
        guard !stopped, outcomeBuilder != nil, let process,
              let pipe = process.standardInput as? Pipe else { return }
        sentInterrupt = true
        pipe.fileHandleForWriting.write(Data([0x03]))
    }

    /// EOF on stdin, then terminate — the same clean-exit shape as
    /// `swiftstar-drive` and the pre-move `AgentController.stopAgent`. Safe to
    /// call more than once.
    public func stop() {
        guard !stopped else { return }
        stopped = true
        stdoutTask?.cancel()
        stderrTask?.cancel()
        if let pipe = process?.standardInput as? Pipe {
            try? pipe.fileHandleForWriting.close()
        }
        process?.terminate()
    }

    // MARK: - wire consumption (the single-turn loop)

    private func consume(_ line: String) async {
        guard !stopped, let poolEvent = parser.feed(line) else { return }
        let worker = poolEvent.worker
        let event = poolEvent.event
        // P11 (D1/D4): a worker-tagged event belongs to that worker's own
        // turn, not the orchestrator's — hand it to `onWorkerEvent` and stop.
        // This session never auto-answers a worker's `tool_request` (that
        // needs the worker's worktree/writableFiles, which live in
        // `ActiveWorkerTurn`, app-side); the app answers via
        // `writeToolResult` from inside its own `onWorkerEvent` handler.
        guard worker == .orchestrator else {
            onWorkerEvent?(worker, event)
            return
        }
        if case .hello = event {
            // P23 (D3): record what the engine advertised so `send`'s
            // per-turn override never assumes a capability the handshake
            // didn't claim.
            advertisedCaps = parser.optionalCaps
        }
        onEvent?(event)
        // Every event feeds the outcome builder (it ignores what it does not
        // need); the record spans the whole turn, not just tool events.
        outcomeBuilder?.apply(event)
        switch event {
        case .ready:
            // D12/D6: the turn-end `ready` is the single gate — a builder
            // opened by `send` and still open when a `ready` arrives is a
            // finished turn, full stop. (A `ready` with no builder open — the
            // engine's own pre-turn handshake ready — is a no-op here.)
            if let builder = outcomeBuilder {
                let outcome = builder.finish(appStopReason: sentInterrupt ? .interrupt : nil)
                outcomeBuilder = nil
                sentInterrupt = false
                onOutcome?(outcome)
            }
        case .toolRequest(let idx, let name, let params):
            guard toolBudget.admit() else {
                let response = ToolCallbackResponder.budgetExceeded(idx: idx)
                writeToolResult(response)
                outcomeBuilder?.recordHostVerdict(
                    idx: idx, ok: false, mutations: [], exitStatus: nil,
                    outputDigest: nil, validationRan: false)
                onToolVerdict?([], nil, false)
                return
            }
            // Regression fix (eval-cli task 3): `dispatch` is a host-control
            // tool (P11 D5), not a normal one — admitting it means enqueuing
            // a worker into `PoolState`, which lives app-side. Task 2 routed
            // every tool name (including `dispatch`) through the generic
            // `ToolCallbackResponder.respond`, whose own `dispatch` branch
            // answers `ok:true, s:"dispatched"` WITHOUT enqueueing anything —
            // a `/orchestrate` dispatch call always "succeeded" on the wire
            // and never ran a worker. `onDispatchDecision` is how the app
            // (which owns `poolState`) makes the real admission call;
            // `DispatchAdmission.apply` composes the wire answer and this
            // session's own outcome verdict together, so neither can be
            // written without the other (the 2026-08-30 dead-letter bug it
            // exists to prevent).
            if name == "dispatch" {
                let decision = onDispatchDecision?(params) ?? .refused("dispatch is not available")
                let response = DispatchAdmission.apply(decision, idx: idx, into: &outcomeBuilder)
                writeToolResult(response)
                return
            }
            // P9: the host owns execution. `respond` consent-checks,
            // executes, condenses, and returns the wire response; the
            // `await` below is a real suspension point (a `bash` call awaits
            // `SubprocessRunner`), so re-check `stopped` after it before
            // touching `outcomeBuilder` or writing to a possibly-closed pipe
            // — `stop()` is reachable during a long-running tool call.
            let response = await ToolCallbackResponder.respond(
                idx: idx, name: name, params: params,
                workspace: settings.workspace, shellAllowed: settings.shellAllowed,
                execute: hostToolExecutor.execute)
            guard !stopped else { return }
            writeToolResult(response)
            outcomeBuilder?.recordHostVerdict(
                idx: idx, ok: response.ok,
                mutations: response.mutations, exitStatus: response.exitStatus,
                outputDigest: response.outputDigest, validationRan: response.validationRan)
            onToolVerdict?(response.mutations, response.exitStatus, response.validationRan)
        case .toolRequestRefused(let idx, let reason):
            // P9: a malformed `tool_request` still blocks the engine on a
            // result — write one so it unblocks, matching
            // `AgentController`'s pre-move handling exactly.
            writeToolResult(ToolCallbackResponse(
                idx: idx, ok: false, s: ToolResultCondenser.condense(reason)))
        case .refused(let raw):
            onRefusal?(raw)
            stop()
        case .hello, .status, .queued, .text, .think, .tool, .ignored:
            break
        }
    }

    private func consumeStderr(_ line: String) {
        guard !stopped else { return }
        stderrTail.append(line)
        if stderrTail.count > 20 { stderrTail.removeFirst(stderrTail.count - 20) }
        onStderrLine?(line)
    }

    // MARK: - spawn-record assembly (moved from AgentController.makeSpawnRecord)

    /// Whether `dir`'s git working tree has uncommitted changes. Best-effort:
    /// a non-repo or unreadable tree reads as clean rather than failing the
    /// spawn — this is provenance, not a gate. (Verbatim port of
    /// `AgentController.repoDirty`.)
    private static func repoDirty(_ dir: URL) -> Bool {
        guard let result = try? GitProcess.run(["status", "--porcelain"], in: dir),
              result.exit == 0, !result.timedOut else { return false }
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The engine build identification (D12): the submodule SHA, resolved
    /// once per spawn — the same fact the capture provenance records.
    /// (Verbatim port of `AgentController.submoduleSHA`.)
    private static func submoduleSHA(_ dir: URL) -> String {
        guard let result = try? GitProcess.run(["rev-parse", "HEAD"], in: dir),
              result.exit == 0, !result.timedOut else { return "unknown" }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Assemble this spawn's `SpawnRecord`. Was `AgentController.makeSpawnRecord`
    /// — moved verbatim except for two app-only notions that don't generalize
    /// to a headless caller: the harness root is now located from the current
    /// working directory (`ProjectRoot.locate`), not `Bundle.main`'s
    /// executable (there is no app bundle for a CLI), and the variant
    /// selection is still read through `AgentDefaultSettings
    /// .effectiveSelectedVariantID` — that function already takes its
    /// `UserDefaults`/environment explicitly, so it carries over unchanged.
    private static func makeSpawnRecord(
        settings: AgentSettings, tools: [String], buildSHA: String,
        captureDirectory: URL, startedAt: Date
    ) -> SpawnRecord {
        let env = ProcessInfo.processInfo.environment
        var allowlistedEnv: [String: String] = [:]
        for key in SpawnRecord.environmentAllowlist {
            if let value = env[key] { allowlistedEnv[key] = value }
        }
        var allowlistedDefaults: [String: String] = [:]
        for key in SpawnRecord.userDefaultsKeys {
            if let value = UserDefaults.standard.string(forKey: key) {
                allowlistedDefaults[key] = value
            } else if UserDefaults.standard.object(forKey: key) != nil {
                allowlistedDefaults[key] = String(UserDefaults.standard.bool(forKey: key))
            }
        }
        let modelBytes = try? FileManager.default.attributesOfItem(
            atPath: settings.modelPath.path)[.size] as? Int64
        let harnessRoot = ProjectRoot.locate(
            anchor: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        return SpawnRecord.from(
            settings: settings,
            engineSHA: buildSHA, engineDirty: repoDirty(settings.engineDir),
            engineBinaryHash: "",
            swiftstarSHA: harnessRoot.map { submoduleSHA($0) } ?? "unknown",
            swiftstarDirty: harnessRoot.map { repoDirty($0) } ?? false,
            harnessBinaryHash: "",
            systemPromptHash: settings.systemPrompt.map { ToolDigest.sha256($0) } ?? "",
            modelBytes: modelBytes ?? 0, modelHash: "",
            variantID: AgentDefaultSettings.effectiveSelectedVariantID(defaults: .standard, environment: env),
            tools: tools, osBuild: ProcessInfo.processInfo.operatingSystemVersionString,
            wiredLimitBytes: VariantAdmissionSource.wiredLimitAdvisoryBytes(),
            workspaceRef: "",
            environment: allowlistedEnv, userDefaults: allowlistedDefaults,
            captureDirectory: captureDirectory.path, startedAt: startedAt, runIndex: 0)
    }

    /// The P5-provenance shape, written once at spawn. (Port of
    /// `AgentController.renderLiveProvenance`, generalized: the closing note
    /// no longer names "the SwiftStar app" specifically, since this type now
    /// runs headless too.)
    private static func renderProvenance(_ record: SpawnRecord, at dir: URL) throws {
        let text = CaptureProvenance.render(
            title: "Live session provenance",
            facts: record.provenanceFacts,
            closingNote: """
            Captured by an `AgentSession` (agent session). `wire.ndjson` and
            `agent.stderr` are the verbatim raw streams; `agent.trace` is the
            engine's `--trace` channel when requested. Wire `ts` is
            monotonic-since-boot (deltas only); this file anchors wall-clock.
            """)
        try text.write(to: dir.appendingPathComponent("provenance.md"), atomically: true, encoding: .utf8)
    }
}
