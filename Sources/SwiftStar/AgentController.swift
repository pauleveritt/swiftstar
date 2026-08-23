import Foundation
import Observation
import SwiftStarKit

/// The agent child's lifecycle + turn state. Unlike the server's `Supervisor`
/// state machine, the agent wire carries no explicit turn-end event: turn end
/// is inferred from `status.state → idle` (D6).
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
    var settings: AgentSettings

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
        case .status(let s):
            // D6: turn end is inferred from the idle state transition (state
            // changes bypass the 200ms status throttle, so this is reliable).
            if state == .generating && s.state == "idle" {
                state = .ready
            }
        case .ready(_, let stopReason, _, _):
            if state == .starting { state = .ready }
            // D12: the turn-end ready carries the stop reason — finish the
            // record. The app's own interrupt beats the wire's word for it.
            if stopReason != nil, let builder = outcomeBuilder {
                let outcome = builder.finish(appStopReason: sentInterrupt ? .interrupt : nil)
                outcomeBuilder = nil
                lastTurnOutcome = outcome
                log("turn outcome: \(outcome)")
            }
        case .text, .think, .tool:
            transcript.apply(event)
        case .queued, .ignored:
            break
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
}
