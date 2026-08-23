import Foundation

/// Runs one shell command to completion, draining stdout/stderr concurrently so
/// a verbose command can never deadlock on a full pipe, and enforcing a timeout.
/// The two call sites (validation in `WorktreeDispatcher`, host `bash` in
/// `AgentController`) both used `waitUntilExit()` before reading the pipes —
/// a command that wrote more than the pipe buffer (64 KiB) blocked forever.
public enum SubprocessRunner {
    public struct Result: Equatable, Sendable {
        public let stdout: String
        public let stderr: String
        public let exit: Int32
        public let timedOut: Bool
    }

    /// Runs `command` via `/bin/bash -c` in `cwd`, returning the captured
    /// stdout/stderr and exit status. Never deadlocks on a full pipe: each pipe
    /// is drained by a `readabilityHandler` as bytes arrive, while the main
    /// thread only waits. A command still running after `timeout` seconds is
    /// terminated (its partial output is kept; `timedOut` is set).
    public static func run(
        _ command: String,
        in cwd: URL,
        timeout: TimeInterval = 300
    ) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = cwd
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Lock-protected accumulation: readabilityHandler runs on a background
        // queue, so appends must not race.
        final class Buffer: @unchecked Sendable {
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

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        var timedOut = false
        if process.isRunning {
            process.terminate()
            timedOut = true
        }
        process.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        let out = String(decoding: outBuf.value, as: UTF8.self)
        let err = String(decoding: errBuf.value, as: UTF8.self)
        return Result(stdout: out, stderr: err, exit: process.terminationStatus, timedOut: timedOut)
    }
}
