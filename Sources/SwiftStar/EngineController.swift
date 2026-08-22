import Foundation
import Observation
import SwiftStarKit

@MainActor
@Observable
final class EngineController {
    var state: SupervisorState = .stopped
    private(set) var transcript = ChatTranscript()
    private(set) var stderrTail: [String] = []

    var settings: EngineSettings
    private var process: Process?
    private var parser = SSEParser()
    private let logURL: URL?

    init(settings: EngineSettings = EngineController.defaultSettings()) {
        self.settings = settings
        if let logPath = ProcessInfo.processInfo.environment["SWIFTSTAR_LOG"] {
            self.logURL = URL(fileURLWithPath: logPath)
        } else {
            self.logURL = nil
        }
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
        } else {
            modelPath = URL(fileURLWithPath: "/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf")
        }
        let contextSize = defaults.object(forKey: "contextSize") as? Int ?? 32768
        let savedPort = defaults.object(forKey: "port") as? Int ?? 0
        return EngineSettings(
            engineDir: engineDir,
            modelPath: modelPath,
            contextSize: contextSize,
            port: savedPort > 0 ? savedPort : EngineController.probeFreePort()
        )
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

    var canSend: Bool { state == .ready || state == .generating }

    /// Starts the engine if it is stopped (auto-start on Chat appear; a
    /// failed state stays visible for the user to retry deliberately).
    func startIfNeeded() {
        if state == .stopped { startEngine() }
    }

    func startEngine() {
        let binary = URL(fileURLWithPath: ServerCommand.binaryPath(settings: settings))
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            state = Supervisor.transition(from: state, event: .engineMissing(binary))
            return
        }
        state = Supervisor.transition(from: state, event: .launchRequested)
        let process = Process()
        process.executableURL = binary
        process.arguments = ServerCommand.argv(settings: settings)
        process.currentDirectoryURL = settings.engineDir  // metal/*.metal resolve relative to CWD
        process.environment = ProcessInfo.processInfo.environment
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()  // SSE arrives over HTTP, not stdout
        process.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                self.state = Supervisor.transition(from: self.state, event: .exit(p.terminationStatus), stderrTail: self.stderrTail)
            }
        }
        self.process = process
        do {
            try process.run()
        } catch {
            state = .failed(.exited(code: -1, stderrTail: "\(error)"))
        }
        Task {
            for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                self.consumeStderr(line)
            }
        }
    }

    private func consumeStderr(_ line: String) {
        stderrTail.append(line)
        if stderrTail.count > 20 { stderrTail.removeFirst(stderrTail.count - 20) }
        log(line)
        state = Supervisor.transition(from: state, event: .stderrLine(line), port: settings.port, stderrTail: stderrTail)
    }

    func send(_ message: String) {
        transcript.appendSystem("> \(message)")
        if state != .ready, state != .generating { startEngine() }
        Task { await streamTurn(message) }
    }

    private func streamTurn(_ message: String) async {
        guard let url = URL(string: "http://127.0.0.1:\(settings.port)/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "messages": [["role": "user", "content": message]],
            "stream": true,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            state = Supervisor.transition(from: state, event: .generationStarted)
            for try await line in bytes.lines {
                if let event = parser.feed(line) {
                    transcript.apply(event)
                    if case .finish = event {
                        state = Supervisor.transition(from: state, event: .generationFinished)
                    }
                }
            }
        } catch {
            log("stream error: \(error)")
            transcript.appendSystem("stream error: \(error.localizedDescription)")
            state = Supervisor.transition(from: state, event: .generationFinished)
        }
    }

    func stopEngine() {
        state = Supervisor.transition(from: state, event: .stopRequested)
        process?.terminate()
    }

    private func log(_ s: String) {
        guard let logURL else { return }
        let data = Data((s + "\n").utf8)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
