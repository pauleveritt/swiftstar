import Foundation
import SwiftStarKit

public enum EngineSessionError: Error, Equatable, LocalizedError {
    case notRunning
    case encoding
    case alreadyStarted

    public var errorDescription: String? {
        switch self {
        case .notRunning: "The engine is not running."
        case .encoding: "The command could not be encoded."
        case .alreadyStarted: "The engine session was already started."
        }
    }
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

    private var started = false
    private var process: Process?
    private var stdin: FileHandle?
    private var parser = EngineWireParser()
    private var sawReady = false
    private var failedProtocol = false
    private var stderrTail = Data()

    private var exited = false
    private var exitStatus: Int32 = 0
    private var stdoutDone = false
    private var stderrDone = false
    private var exitFired = false
    private var exitReason: Process.TerminationReason = .exit

    /// True from the first `.prompt` until the next `.awaitingInput`, `.turnEnded` or `.closed`.
    private var inTurn = false
    private var quitting = false
    private var forced = false
    private var terminated = false
    private var quitTask: Task<Void, Never>?
    private let stopGrace: Duration
    private let termGrace: Duration
    private let killGrace: Duration

    public init(
        executable: String, arguments: [String],
        environment: [String: String]? = nil, workingDirectory: URL? = nil,
        stopGrace: Duration = .seconds(10), termGrace: Duration = .seconds(5),
        killGrace: Duration = .seconds(10)
    ) {
        self.stopGrace = stopGrace
        self.termGrace = termGrace
        self.killGrace = killGrace
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    public func start() throws {
        // One-shot: a finished session's state is not reset; make a new one.
        guard !started else { throw EngineSessionError.alreadyStarted }
        started = true
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

        process.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            let reason = p.terminationReason
            Task { @MainActor in self?.processExited(status, reason) }
        }

        try process.run()
        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting
        // The child holds its own copies; drop ours so EOF can arrive.
        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        // Each pipe gets its own non-blocking readabilityHandler-fed byte
        // stream, framed into lines by Foundation's AsyncLineSequence (via
        // ChunkBytes below). NOT FileHandle.bytes: on Darwin it funnels every
        // pipe's reads through one shared, process-wide blocking IO actor, so
        // two concurrent `.bytes` readers (stdout and stderr here) can starve
        // each other — the quiet one's blocking read holds the actor while
        // the busy one's data sits unread. Confirmed by thread-sampling a
        // real stall and reproduced outside any test harness; see the P32
        // Backlog entry and docs/superpowers/specs/2026-10-04-p32-structure-cleanup-design.md.
        let outBytes = Self.byteStream(from: stdoutPipe.fileHandleForReading)
        let errBytes = Self.byteStream(from: stderrPipe.fileHandleForReading)
        Task { @MainActor [weak self] in
            for await line in outBytes.lines { self?.consumeStdoutLine(line) }
            self?.stdoutReachedEOF()
        }
        Task { @MainActor [weak self] in
            for await line in errBytes.lines { self?.consumeStderrLine(line) }
            self?.stderrReachedEOF()
        }
    }

    /// Bytes of a pipe as they arrive, via `readabilityHandler` (non-blocking,
    /// independent per pipe) rather than `FileHandle.bytes` (see `start()`).
    private static func byteStream(from handle: FileHandle) -> ChunkBytes {
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
        return ChunkBytes(chunks: stream)
    }

    /// Flattens a stream of `Data` chunks into a byte sequence, so Foundation's
    /// `AsyncLineSequence` (`.lines`) can frame them without a hand-rolled buffer.
    private struct ChunkBytes: AsyncSequence {
        typealias Element = UInt8
        let chunks: AsyncStream<Data>
        func makeAsyncIterator() -> AsyncIterator { AsyncIterator(inner: chunks.makeAsyncIterator()) }
        struct AsyncIterator: AsyncIteratorProtocol {
            var inner: AsyncStream<Data>.AsyncIterator
            var current: Data.Iterator?
            mutating func next() async -> UInt8? {
                while true {
                    if let byte = current?.next() { return byte }
                    guard let data = await inner.next() else { return nil }
                    current = data.makeIterator()
                }
            }
        }
    }

    /// Dropping a still-running session must not orphan the engine (model and
    /// GPU memory): close stdin, then terminate.
    isolated deinit {
        quitTask?.cancel()
        try? stdin?.close()
        if let process, process.isRunning { process.terminate() }
    }

    public func send(prompt: String) throws {
        try write(Self.command(["kind": "prompt", "text": prompt]))
    }

    public func stop() throws {
        try write(Self.command(["kind": "stop"]))
    }

    /// Ends the engine. In a turn: `stop` and `quit` back to back (the relay
    /// handles `quit` before its queue, so a queued prompt cannot start), then
    /// close stdin; SIGTERM after `stopGrace`. Idle: `quit`, close stdin,
    /// SIGTERM after `termGrace`. SIGKILL `killGrace` after SIGTERM.
    /// Idempotent: a second call while quitting is a no-op.
    public func quit() {
        guard process != nil, !exited, !quitting else { return }
        quitting = true
        let grace = inTurn ? stopGrace : termGrace
        if inTurn, let data = try? Self.command(["kind": "stop"]) { try? stdin?.write(contentsOf: data) }
        if let data = try? Self.command(["kind": "quit"]) { try? stdin?.write(contentsOf: data) }
        try? stdin?.close()
        stdin = nil
        quitTask = Task { @MainActor [self] in await escalate(after: grace) }
    }

    private func escalate(after grace: Duration) async {
        if await waitUntil(grace, { false }) { return }
        guard !exited, let process, process.isRunning else { return }
        terminated = true
        process.terminate()
        if await waitUntil(killGrace, { false }) { return }
        guard !exited, let process = self.process, process.isRunning else { return }
        forced = true
        kill(process.processIdentifier, SIGKILL)
    }

    /// Polls until `condition` holds or the process has exited (true), or the
    /// duration elapses (false). Cancellation (set on exit) ends it at once.
    private func waitUntil(_ duration: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while !exited, !Task.isCancelled, !condition() {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    // MARK: - Private

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

    private func consumeStdoutLine(_ line: String) {
        // The parser treats a blank line as a protocol error; it is noise.
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if failedProtocol { return }
        handle(parser.parse(line))
    }

    private func handle(_ event: EngineEvent) {
        switch event {
        case .ignored:
            return
        case .ready:
            sawReady = true
        case .prompt:
            inTurn = true
        case .awaitingInput, .turnEnded:
            inTurn = false
        case .closed(let capturePath):
            inTurn = false
            if let capturePath, !capturePath.isEmpty {
                sessionDirectory = resolve(capturePath).deletingLastPathComponent().standardizedFileURL
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

    private func consumeStderrLine(_ line: String) {
        stderrTail.append(Data((line + "\n").utf8))
        if stderrTail.count > Self.stderrTailLimit {
            stderrTail = Data(stderrTail.suffix(Self.stderrTailLimit))
        }
        noteStderrLine(line)
    }

    private func noteStderrLine(_ line: String) {
        let marker = "Session artifacts:"
        guard sessionDirectory == nil, let range = line.range(of: marker) else { return }
        let path = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        sessionDirectory = resolve(path).standardizedFileURL
    }

    /// Absolute paths as-is; relative ones against the working directory.
    /// (`URL(relativeTo:)` needs a trailing-slash base, so append explicitly.)
    private func resolve(_ path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        let base = workingDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return base.appendingPathComponent(path)
    }

    private func stdoutReachedEOF() {
        stdoutDone = true
        finishIfComplete()
    }

    private func stderrReachedEOF() {
        stderrDone = true
        finishIfComplete()
    }

    private func processExited(_ status: Int32, _ reason: Process.TerminationReason) {
        exited = true
        exitStatus = status
        exitReason = reason
        quitTask?.cancel()
        finishIfComplete()
    }

    private func finishIfComplete() {
        guard exited, stdoutDone, stderrDone, !exitFired else { return }
        exitFired = true
        try? stdin?.close()
        stdin = nil
        process = nil
        let exit = EngineExit.describe(
            code: exitStatus, stderrTail: String(decoding: stderrTail, as: UTF8.self), sawReady: sawReady,
            reason: exitReason == .uncaughtSignal ? .signal : .exit, forced: forced, terminated: terminated)
        quitTask = nil
        onExit?(exit, sessionDirectory)
    }
}
