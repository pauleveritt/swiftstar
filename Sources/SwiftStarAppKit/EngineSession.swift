import Foundation
import SwiftStarKit

public enum EngineSessionError: Error, Equatable {
    case notRunning
    case encoding
}

/// Owns one `ds4-dogfood tui --ndjson` subprocess: writes commands to its
/// stdin, decodes its stdout into `EngineEvent`s, and reports exactly one
/// `onExit` once the process has exited and both pipes have reached EOF.
@MainActor
public final class EngineSession {
    public var onEvent: ((EngineEvent) -> Void)?
    /// The exit and the session directory (where the engine left its artifacts).
    public var onExit: ((EngineExit, URL?) -> Void)?
    public private(set) var sessionDirectory: URL?

    /// True from a successful `start()` until the process has exited.
    public var isRunning: Bool { process != nil && !exited }

    private static let stderrTailLimit = 4096

    private let executable: String
    private let arguments: [String]
    private let environment: [String: String]?
    private let workingDirectory: URL?

    private var process: Process?
    private var stdin: FileHandle?
    private var parser = EngineWireParser()
    private var sawReady = false
    private var failedProtocol = false
    private var stdoutLines = LineBuffer()
    private var stderrLines = LineBuffer()
    private var stderrTail = Data()

    private var exited = false
    private var exitStatus: Int32 = 0
    private var stdoutDone = false
    private var stderrDone = false
    private var exitFired = false

    public init(
        executable: String, arguments: [String],
        environment: [String: String]? = nil, workingDirectory: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    public func start() throws {
        guard process == nil else { return }
        // A write to a dead engine must surface as a thrown error, not SIGPIPE.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Handlers run off the main actor. Each feeds an AsyncStream (ordered,
        // thread-safe); a main-actor task drains it, so chunks are processed
        // in arrival order and EOF is delivered after the last chunk.
        let outStream = Self.stream(from: stdoutPipe.fileHandleForReading)
        let errStream = Self.stream(from: stderrPipe.fileHandleForReading)
        process.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            Task { @MainActor in self?.processExited(status) }
        }

        try process.run()
        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting
        // The child holds its own copies; drop ours so EOF can arrive.
        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        Task { @MainActor [weak self] in
            for await data in outStream { self?.consumeStdout(data) }
            self?.stdoutReachedEOF()
        }
        Task { @MainActor [weak self] in
            for await data in errStream { self?.consumeStderr(data) }
            self?.stderrReachedEOF()
        }
    }

    public func send(prompt: String) throws {
        try write(Self.command(["kind": "prompt", "text": prompt]))
    }

    public func stop() throws {
        try write(Self.command(["kind": "stop"]))
    }

    /// Writes ETX (0x03), the terminal interrupt the engine also honours.
    public func interrupt() throws {
        try write(Data([0x03]))
    }

    /// Asks the engine to quit, closes stdin, and SIGTERMs it if it is still
    /// running after `timeout`.
    public func quit(timeout: Duration = .seconds(5)) {
        guard let process, !exited else { return }
        if let data = try? Self.command(["kind": "quit"]) {
            try? stdin?.write(contentsOf: data)
        }
        try? stdin?.close()
        stdin = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !self.exited, self.process === process else { return }
            process.terminate()
        }
    }

    // MARK: - Private

    private static func stream(from handle: FileHandle) -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                try? h.close()
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        return stream
    }

    private static func command(_ object: [String: String]) throws -> Data {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { throw EngineSessionError.encoding }
        data.append(0x0A)
        return data
    }

    private func write(_ data: Data) throws {
        guard isRunning, let stdin else { throw EngineSessionError.notRunning }
        try stdin.write(contentsOf: data)
    }

    private func consumeStdout(_ data: Data) {
        for lineData in stdoutLines.append(data) {
            let line = String(decoding: lineData, as: UTF8.self)
            // The parser treats a blank line as a protocol error; it is noise.
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if failedProtocol { continue }
            handle(parser.parse(line))
        }
    }

    private func handle(_ event: EngineEvent) {
        switch event {
        case .ignored:
            return
        case .ready:
            sawReady = true
        case .closed(let capturePath):
            if let capturePath, !capturePath.isEmpty {
                let base = workingDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                sessionDirectory = URL(fileURLWithPath: capturePath, relativeTo: base)
                    .deletingLastPathComponent().standardizedFileURL
            }
        case .protocolError:
            failedProtocol = true
            onEvent?(event)
            if let process, !exited { process.terminate() }
            return
        default:
            break
        }
        onEvent?(event)
    }

    private func consumeStderr(_ data: Data) {
        stderrTail.append(data)
        if stderrTail.count > Self.stderrTailLimit {
            stderrTail = Data(stderrTail.suffix(Self.stderrTailLimit))
        }
        for lineData in stderrLines.append(data) {
            noteStderrLine(String(decoding: lineData, as: UTF8.self))
        }
    }

    private func noteStderrLine(_ line: String) {
        let marker = "Session artifacts:"
        guard sessionDirectory == nil, let range = line.range(of: marker) else { return }
        let path = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        let base = workingDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        sessionDirectory = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
    }

    private func stdoutReachedEOF() {
        _ = stdoutLines.finish()
        stdoutDone = true
        finishIfComplete()
    }

    private func stderrReachedEOF() {
        if let rest = stderrLines.finish() { noteStderrLine(String(decoding: rest, as: UTF8.self)) }
        stderrDone = true
        finishIfComplete()
    }

    private func processExited(_ status: Int32) {
        exited = true
        exitStatus = status
        finishIfComplete()
    }

    private func finishIfComplete() {
        guard exited, stdoutDone, stderrDone, !exitFired else { return }
        exitFired = true
        try? stdin?.close()
        stdin = nil
        process = nil
        let exit = EngineExit.describe(
            code: exitStatus, stderrTail: String(decoding: stderrTail, as: UTF8.self), sawReady: sawReady)
        onExit?(exit, sessionDirectory)
    }
}
