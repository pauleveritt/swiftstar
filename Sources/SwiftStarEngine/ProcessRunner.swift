import Foundation
import SwiftStarKit

/// What a finished child process left.
public struct ProcessOutput: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let code: Int32
}

public enum ProcessFailure: Error, Equatable {
    case launch(String)
    case timedOut
}

/// Runs one short-lived child and collects its output, racing it against a
/// timeout (extracted from `EngineModelCatalogLoader`, AN.2).
///
/// Nothing here blocks a thread: output arrives through `readabilityHandler`
/// streams (as in `EngineSession`), the exit through `terminationHandler`,
/// and a task group races them against the timeout.
public enum ProcessRunner {
    /// How long a finished child's pipes may keep delivering output (as
    /// `EngineSession`'s drain limit).
    static let drainLimit: Duration = .milliseconds(500)

    public static func run(
        executable: String, arguments: [String], timeout: Duration,
        environment: [String: String]? = nil
    ) async -> Result<ProcessOutput, ProcessFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let (status, statusEnd) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { p in
            statusEnd.yield(p.terminationStatus)
            statusEnd.finish()
        }
        let (outData, outEnd) = collect(out.fileHandleForReading)
        let (errData, errEnd) = collect(err.fileHandleForReading)
        do {
            try process.run()
        } catch {
            for end in [outEnd, errEnd] { end() }
            return .failure(.launch("could not launch \(executable): \(error.localizedDescription)"))
        }
        // The child holds its own copies; drop ours so EOF can arrive.
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()

        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                var code: Int32 = -1
                for await c in status { code = c }
                // The child has exited; a grandchild may still hold a pipe
                // (SU.6g, D4). Give the pipes `drainLimit` to finish, then
                // stop reading, so it can't stretch the call to the timeout.
                let drain = Task {
                    try? await Task.sleep(for: drainLimit)
                    for end in [outEnd, errEnd] { end() }
                }
                let stdout = await outData.value, stderr = await errData.value
                drain.cancel()
                return .finished(ProcessOutput(stdout: stdout, stderr: stderr, code: code))
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            if case .timedOut = first {
                // Kill the child (SIGKILL a second later if it ignores
                // SIGTERM), and stop reading a pipe a grandchild may hold,
                // so the collector above can finish.
                // Wait only as long as it takes to die (SU.6g, D4).
                if process.isRunning { process.terminate() }
                let deadline = ContinuousClock.now + .seconds(1)
                while process.isRunning, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                for end in [outEnd, errEnd] { end() }
            }
            group.cancelAll()
            return first
        }
        switch outcome {
        case .timedOut: return .failure(.timedOut)
        case .finished(let output): return .success(output)
        }
    }

    private enum Outcome: Sendable {
        case finished(ProcessOutput)
        case timedOut
    }

    /// Everything a pipe delivers until EOF, and a way to stop reading early.
    private static func collect(_ handle: FileHandle) -> (Task<Data, Never>, @Sendable () -> Void) {
        let (chunks, continuation) = AsyncStream<Data>.makeStream()
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
        let task = Task {
            var all = Data()
            for await chunk in chunks { all.append(chunk) }
            return all
        }
        let end: @Sendable () -> Void = { PipeReading.stop(handle, continuation) }
        return (task, end)
    }
}
