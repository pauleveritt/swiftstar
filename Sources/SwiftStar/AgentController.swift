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
    private(set) var poolState = PoolState()
    /// P11 (D6): the rolling digest — the objective-independent reduced form
    /// of the session, maintained incrementally as host facts arrive.
    private(set) var rollingDigest = RollingDigest()

    nonisolated(unsafe) private var process: Process?
    private var parser = AgentWireParser()
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var generation = 0
    // D12 turn-outcome state.
    private var outcomeBuilder: TurnOutcomeBuilder?
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
        process?.terminate()
        try? logHandle?.close()
    }

    var canSend: Bool { state == .ready }
    var isGenerating: Bool { state == .generating }

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
        let modelPath: URL
        if let path = defaults.string(forKey: "modelPath"), !path.isEmpty {
            modelPath = URL(fileURLWithPath: path)
        } else if let env = ProcessInfo.processInfo.environment["SWIFTSTAR_MODEL"], !env.isEmpty {
            modelPath = URL(fileURLWithPath: env)
        } else {
            modelPath = URL(fileURLWithPath: "/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf")
        }
        let contextSize = defaults.object(forKey: "contextSize") as? Int ?? 32768
        let workspace: URL
        if let dir = defaults.string(forKey: "agentWorkspace"), !dir.isEmpty {
            workspace = URL(fileURLWithPath: dir)
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

    func startIfNeeded() {
        if state == .stopped { startAgent() }
    }

    func startAgent() {
        switch state {
        case .stopped, .failed: break
        default: return
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
        parser = AgentWireParser()
        stderrTail = []
        outcomeBuilder = nil
        sentInterrupt = false
        // D12: the build identification is resolved once per spawn (the
        // submodule SHA — the same fact the capture provenance records).
        buildSHA = AgentController.submoduleSHA(settings.engineDir)

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
        process.arguments = AgentCommand.argv(settings: settings)
        process.currentDirectoryURL = settings.engineDir  // metal/*.metal resolve relative to CWD
        process.environment = ProcessInfo.processInfo.environment
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

        stdoutTask?.cancel()
        stdoutTask = Task.detached(priority: .utility) { [weak self] in
            let handle = stdoutPipe.fileHandleForReading
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }  // EOF: the child closed stdout
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    let line = String(decoding: lineData, as: UTF8.self)
                    await self?.consumeWire(line, generation: gen)
                }
            }
        }

        stderrTask?.cancel()
        stderrTask = Task.detached(priority: .utility) { [weak self] in
            let handle = stderrPipe.fileHandleForReading
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    let line = String(decoding: lineData, as: UTF8.self)
                    await self?.consumeStderr(line, generation: gen)
                }
            }
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
        guard let event = parser.feed(line) else { return }
        // Every event feeds the outcome builder (it ignores what it does not
        // need); the record spans the whole turn, not just tool events.
        outcomeBuilder?.apply(event)
        switch event {
        case .hello:
            if state == .starting { state = .ready }
        case .status(_):
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
            break
        case .ready:
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
            }
        case .text, .think, .tool:
            transcript.apply(event)
        case .toolRequest(let idx, let name, let params):
            if name == "dispatch" {
                // P11 (D3/D5): dispatch is a host-control tool. Build the
                // packet's prepared context from the model's objective + the
                // rolling digest, enqueue it, and answer "dispatched as worker
                // N" (the worker turn runs after this turn ends, D4).
                if let packet = DispatchPacketBuilder.build(
                    params: params, digest: rollingDigest, loaded: [:],
                    implementer: settings.modelPath.lastPathComponent) {
                    let workerId = WorkerId(poolState.nextId)
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

    func send(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !trimmed.isEmpty, let process,
              let pipe = process.standardInput as? Pipe else { return }
        transcript.appendSystem("> \(trimmed)")
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
        // EOF on stdin first (the same clean-exit shape as swiftstar-drive):
        // the engine's non-interactive loop exits on EOF rather than relying
        // on SIGTERM alone.
        if let pipe = process?.standardInput as? Pipe {
            try? pipe.fileHandleForWriting.close()
        }
        process?.terminate()
        // The termination handler lands on .stopped (its guard passes: state
        // is .stopping, not .stopped) after recording the exit.
    }

    // MARK: - P10 dispatched attempt (D2/D3/D4)

    /// The wall-clock safety net for a dispatched turn (the packet's token/tool
    /// budgets are a post-hoc verdict; this catches a runaway that never emits
    /// a turn-end `ready`). `cancelDispatch()` is the responsive path.
    private nonisolated static let dispatchTurnTimeout: TimeInterval = 600

    /// Dispatch `packet` into a disposable worktree of the current workspace's
    /// git repo (D2): the agent is spawned at `--workspace <worktree>` with
    /// shell off and host-tools on (P9), the responder revision-checks each
    /// `write`/`edit` against `packet.writableFiles` (an out-of-set mutation
    /// is refused host-side, not executed), and the pure `WorktreeDispatch`
    /// verdict returns a candidate ref (committed) or a typed receipt. Runs on
    /// a detached task (the wire drain blocks); the outcome/error land on the
    /// main actor for the Dispatch tab. The caller's tree is never touched.
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
        process.environment = ProcessInfo.processInfo.environment
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
