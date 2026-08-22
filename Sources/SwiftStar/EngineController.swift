import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit

@MainActor
@Observable
final class EngineController {
    /// Single reachable controller, so the app delegate can stop the engine
    /// on quit even though the controller is owned by the Chat view.
    static weak var shared: EngineController?

    var state: SupervisorState = .stopped
    private(set) var transcript = ChatTranscript()
    private(set) var stderrTail: [String] = []

    var settings: EngineSettings
    /// `nonisolated(unsafe)`: mutated only on MainActor; deinit (nonisolated in
    /// Swift 6) reads it for teardown.
    nonisolated(unsafe) private var process: Process?
    private var parser = SSEParser()
    nonisolated(unsafe) private let logHandle: FileHandle?
    /// Exit status recorded by the termination handler; the stderr drain reads
    /// it at EOF (after a yield so the handler's MainActor hop has run) so the
    /// failure carries the complete stderr tail, not a stale one.
    private var pendingExitCode: Int32?

    /// Bumped on every launch; the stderr/stdout drain tasks capture their own
    /// generation and ignore lines once it is stale (a dying process's late
    /// lines must not leak into the next instance's state).
    private var launchGeneration = 0
    private var stderrTask: Task<Void, Never>?
    private var stdoutTask: Task<Void, Never>?
    private var turnTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var stopTimeoutTask: Task<Void, Never>?

    init(settings: EngineSettings = EngineController.defaultSettings()) {
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
        EngineController.shared = self
    }

    deinit {
        // @MainActor deinit is nonisolated; Process.terminate is safe off-main.
        process?.terminate()
        try? logHandle?.close()
    }

    static func defaultSettings() -> EngineSettings {
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
            // Development-machine default (P1 weights). Override via Settings or
            // SWIFTSTAR_MODEL; a missing model surfaces as an engine-exited failure.
            modelPath = URL(fileURLWithPath: "/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf")
        }
        let contextSize = defaults.object(forKey: "contextSize") as? Int ?? 32768
        let savedPort = defaults.object(forKey: "port") as? Int ?? 0
        return EngineSettings(
            engineDir: engineDir,
            modelPath: modelPath,
            port: savedPort > 0 ? savedPort : EngineController.probeFreePort()
        )
    }

    /// The engine's own startup memory plan from the last run (boot line), so
    /// a future launch can refuse infeasibly before spawning. Persisted.
    static var lastKnownPlannedBytes: Int64? {
        get {
            let v = UserDefaults.standard.object(forKey: "lastKnownPlannedBytes") as? Int64
            return v
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastKnownPlannedBytes")
        }
    }

    /// The model (last path component) the persisted plan was measured on.
    static var lastKnownPlannedModel: String? {
        get {
            UserDefaults.standard.string(forKey: "lastKnownPlannedModel")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastKnownPlannedModel")
        }
    }

    static func probeFreePort() -> Int {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(s) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard r == 0 else { return 8000 }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var got = sockaddr_in()
        let g = withUnsafeMutablePointer(to: &got) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(s, $0, &len)
            }
        }
        guard g == 0 else { return 8000 }
        return Int(got.sin_port.bigEndian)
    }

    /// A turn may only start when the engine is ready: single-user chat means
    /// one turn at a time, and a request must never race engine startup.
    var canSend: Bool { state == .ready }

    /// Starts the engine if it is stopped (auto-start on Chat appear; a failed
    /// state stays visible for the user to retry deliberately).
    func startIfNeeded() {
        if state == .stopped { startEngine() }
    }

    func startEngine() {
        // Idempotency: launch only from .stopped/.failed. .starting/.ready/
        // .generating/.stopping already have a process in flight.
        switch state {
        case .stopped, .failed: break
        default: return
        }
        // Feasibility: refuse before spawning with a computed, actionable
        // message (P3). plannedBytes comes from the engine's own boot line,
        // persisted with the model it was measured on; a changed model
        // invalidates the stale plan (a refusal must never pair an old model's
        // bytes with a new model's name). Unknown plans defer to the engine.
        if EngineController.lastKnownPlannedModel != settings.modelPath.lastPathComponent {
            EngineController.lastKnownPlannedBytes = nil
        }
        if let planned = EngineController.lastKnownPlannedBytes {
            let verdict = Feasibility.check(
                plannedBytes: planned,
                availableBytes: MemorySnapshot.availableBytes(),
                modelName: settings.modelPath.lastPathComponent
            )
            if case .infeasible(let reason) = verdict {
                state = .failed(.infeasible(reason.message))
                log("feasibility refusal: \(reason.message)")
                return
            }
        }
        // Settings apply when the engine next starts (Settings pane caption).
        settings = EngineController.defaultSettings()

        let binary = ServerCommand.binaryPath(settings: settings)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            state = Supervisor.transition(from: state, event: .engineMissing(binary))
            return
        }
        state = Supervisor.transition(from: state, event: .launchRequested)
        launchGeneration += 1
        let generation = launchGeneration

        let process = Process()
        process.executableURL = binary
        process.arguments = ServerCommand.argv(settings: settings)
        process.currentDirectoryURL = settings.engineDir  // metal/*.metal resolve relative to CWD
        process.environment = ProcessInfo.processInfo.environment
        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe
        process.terminationHandler = { [weak self] p in
            Task { @MainActor in
                // Record the status; the .exit transition is driven by the
                // stderr drain at EOF (so the tail is complete), which yields
                // once to let this hop run first.
                self?.pendingExitCode = p.terminationStatus
                self?.process = nil
            }
        }
        self.process = process
        do {
            try process.run()
        } catch {
            self.process = nil
            state = .failed(.exited(code: -1, stderrTail: "\(error)"))
            return
        }

        stderrTask?.cancel()
        stderrTask = Task.detached(priority: .utility) { [weak self] in
            // Blocking drain (no runloop dependence — AsyncBytes.bytes.lines is
            // unreliable here). Splits complete lines off a buffer as they arrive.
            let handle = stderrPipe.fileHandleForReading
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }  // EOF: the child closed stderr
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    let line = String(decoding: lineData, as: UTF8.self)
                    await self?.consumeStderr(line, generation: generation)
                }
            }
            await self?.completeExit(generation: generation)
        }

        stdoutTask?.cancel()
        stdoutTask = Task.detached(priority: .utility) { [weak self] in
            // Drain stdout so a chatty engine can never block on a full pipe.
            let handle = stdoutPipe.fileHandleForReading
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)
                if let nl = buffer.firstIndex(of: 0x0A) {
                    buffer.removeSubrange(buffer.startIndex...nl)
                }
            }
        }

        startupTimeoutTask?.cancel()
        startupTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled else { return }
            if self.state == .starting {
                self.state = Supervisor.transition(from: self.state, event: .timeoutFired)
                self.process?.terminate()
            }
        }
    }

    private func consumeStderr(_ line: String, generation: Int) {
        guard generation == launchGeneration else { return }
        stderrTail.append(line)
        if stderrTail.count > 20 { stderrTail.removeFirst(stderrTail.count - 20) }
        log(line)
        // Persist the engine's own startup memory plan (keyed by the model it
        // was measured on) so future launches can refuse infeasibly before
        // spawning (P3).
        if let planned = BootLineParser.plannedBytes(from: line) {
            EngineController.lastKnownPlannedBytes = planned
            EngineController.lastKnownPlannedModel = settings.modelPath.lastPathComponent
        }
        state = Supervisor.transition(from: state, event: .stderrLine(line), port: settings.port, stderrTail: stderrTail)
    }

    /// Runs when the stderr drain hits EOF: the process has exited and every
    /// stderr line has been consumed, so the failure carries a complete tail.
    private func completeExit(generation: Int) async {
        guard generation == launchGeneration else { return }
        await Task.yield()  // let the termination handler record the status first
        let code = pendingExitCode ?? -1
        state = Supervisor.transition(from: state, event: .exit(code), port: settings.port, stderrTail: stderrTail)
    }

    func send(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !trimmed.isEmpty else { return }
        transcript.appendSystem("> \(trimmed)")
        turnTask?.cancel()
        turnTask = Task { await streamTurn(trimmed) }
    }

    private func streamTurn(_ message: String) async {
        let url = URL(string: "http://\(settings.host):\(settings.port)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "messages": [["role": "user", "content": message]],
            "stream": true,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300  // seconds between bytes; a stall fails the turn
        let session = URLSession(configuration: config)
        do {
            let (bytes, _) = try await session.bytes(for: request)
            state = Supervisor.transition(from: state, event: .generationStarted)
            for try await line in bytes.lines {
                if let event = parser.feed(line) {
                    transcript.apply(event)
                    if case .finish = event {
                        state = Supervisor.transition(from: state, event: .generationFinished)
                    }
                }
            }
        } catch is CancellationError {
            // A cancelled turn (engine stop) is not a stream failure.
        } catch {
            log("stream error: \(error)")
            transcript.appendSystem("stream error: \(error.localizedDescription)")
            state = Supervisor.transition(from: state, event: .generationFinished)
        }
    }

    func stopEngine() {
        guard state == .starting || state == .ready || state == .generating || state == .stopping else { return }
        state = Supervisor.transition(from: state, event: .stopRequested)
        turnTask?.cancel()
        stderrTask?.cancel()
        stdoutTask?.cancel()
        process?.terminate()
        stopTimeoutTask?.cancel()
        stopTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            if self.state == .stopping {
                if let pid = self.process?.processIdentifier {
                    Darwin.kill(pid, SIGKILL)  // EOF then drives (.stopping, .exit) -> .stopped
                }
            }
        }
    }

    private func log(_ s: String) {
        guard let logHandle else { return }
        var data = Data((s + "\n").utf8)
        try? logHandle.seekToEnd()
        try? logHandle.write(contentsOf: data)
    }
}
