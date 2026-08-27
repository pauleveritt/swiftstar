import Foundation

/// Runs one shell command to completion, draining stdout/stderr concurrently so
/// a verbose command can never deadlock on a full pipe, and enforcing a timeout.
/// The two call sites (validation in `WorktreeDispatcher`, host `bash` in
/// `AgentController`) both used `waitUntilExit()` before reading the pipes —
/// a command that wrote more than the pipe buffer (64 KiB) blocked forever.
///
/// Item 3 (P22 cleanup): two entry points share the same launch/drain/finish
/// machinery — a synchronous `run` (blocks the calling thread) and an async
/// `run` (yields via `Task.sleep` instead of `Thread.sleep`, so it never
/// blocks the MainActor). `PoolOrchestrator.runPhase` is a deliberately
/// synchronous poll-loop harness (used by `swiftstar-agenttest`) and keeps
/// using the sync entry point; `AgentController`'s host `bash` tool and
/// `WorktreeDispatcher`'s async `runValidation` (both MainActor call sites
/// that used to freeze the app's UI for up to `timeout` seconds) use the
/// async one.
public enum SubprocessRunner {
    public struct Result: Equatable, Sendable {
        public let stdout: String
        public let stderr: String
        public let exit: Int32
        public let timedOut: Bool
    }

    /// Runs `command` via `/bin/bash -c` in `cwd`, blocking the calling thread
    /// until it completes or `timeout` elapses. Used by
    /// `PoolOrchestrator.runPhase`, a deliberately synchronous poll-loop
    /// harness — blocking there is intentional, not an oversight.
    public static func run(
        _ command: String,
        in cwd: URL,
        timeout: TimeInterval = 300
    ) throws -> Result {
        let launched = try launch(command, in: cwd)
        let deadline = Date().addingTimeInterval(timeout)
        while launched.process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return finish(launched)
    }

    /// The async twin of `run` (item 3, P22 cleanup): identical behavior and
    /// result, but waits by yielding on `Task.sleep` instead of blocking the
    /// thread with `Thread.sleep` — real async/await, not a `Task` wrapped
    /// around the blocking poll loop. `AgentController`'s host `bash` tool and
    /// `WorktreeDispatcher.runValidation`'s async overload call this so a
    /// long-running command no longer freezes the MainActor (no repaint, no
    /// Stop button) for up to `timeout` seconds.
    public static func run(
        _ command: String,
        in cwd: URL,
        timeout: TimeInterval = 300
    ) async throws -> Result {
        let launched = try launch(command, in: cwd)
        let deadline = Date().addingTimeInterval(timeout)
        while launched.process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return finish(launched)
    }

    // MARK: - shared launch/drain/finish

    /// Lock-protected accumulation: readabilityHandler runs on a background
    /// queue, so appends must not race.
    private final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ d: Data) {
            lock.lock(); data.append(d); lock.unlock()
        }
        var value: Data {
            lock.lock(); defer { lock.unlock() }
            return data
        }
    }

    private struct Launched {
        let process: Process
        let outPipe: Pipe
        let errPipe: Pipe
        let outBuf: Buffer
        let errBuf: Buffer
    }

    /// Spawn the process with both pipes draining via `readabilityHandler` (so
    /// neither can deadlock on a full 64 KiB buffer) and return the running
    /// handle. Shared by both `run` overloads — only the wait-for-completion
    /// loop differs (blocking vs. yielding).
    private static func launch(_ command: String, in cwd: URL) throws -> Launched {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = cwd
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outBuf = Buffer()
        let errBuf = Buffer()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            if d.isEmpty { handle.readabilityHandler = nil } else { outBuf.append(d) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            if d.isEmpty { handle.readabilityHandler = nil } else { errBuf.append(d) }
        }

        try process.run()
        return Launched(process: process, outPipe: outPipe, errPipe: errPipe,
                        outBuf: outBuf, errBuf: errBuf)
    }

    /// Terminate a still-running process (the deadline elapsed), reap it, stop
    /// draining, and assemble the `Result`. Shared tail of both `run`
    /// overloads. `waitUntilExit()` blocks here regardless of which `run`
    /// called it, but only for the bounded, fast reap after `terminate()` —
    /// not the up-to-`timeout` wait, which each overload does its own way
    /// above.
    private static func finish(_ launched: Launched) -> Result {
        var timedOut = false
        if launched.process.isRunning {
            launched.process.terminate()
            timedOut = true
        }
        launched.process.waitUntilExit()
        launched.outPipe.fileHandleForReading.readabilityHandler = nil
        launched.errPipe.fileHandleForReading.readabilityHandler = nil

        let out = String(decoding: launched.outBuf.value, as: UTF8.self)
        let err = String(decoding: launched.errBuf.value, as: UTF8.self)
        return Result(stdout: out, stderr: err, exit: launched.process.terminationStatus, timedOut: timedOut)
    }
}
