import Foundation
import SwiftStarKit

/// Runs `<ds4-dogfood> <arguments>` for a JSON command (`models --json`,
/// `sessions --json`) and returns its stdout. Any failure (an older engine
/// without the command, a non-zero exit, a timeout) comes back as a
/// `CatalogError`; callers fall back.
///
/// Nothing here blocks a thread: output arrives through `readabilityHandler`
/// streams (as in `EngineSession`), the exit through `terminationHandler`,
/// and a task group races them against the timeout.
enum EngineJSONCommand {
    static func run(
        executable: String, arguments: [String], timeout: Duration, environment: [String: String]?
    ) async -> Result<Data, CatalogError> {
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
            return .failure(.failed("could not launch \(executable): \(error.localizedDescription)"))
        }
        // The child holds its own copies; drop ours so EOF can arrive.
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()

        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                let stdout = await outData.value, stderr = await errData.value
                var code: Int32 = -1
                for await c in status { code = c }
                return .finished(stdout: stdout, stderr: stderr, code: code)
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
                if process.isRunning { process.terminate() }
                try? await Task.sleep(for: .seconds(1))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                for end in [outEnd, errEnd] { end() }
            }
            group.cancelAll()
            return first
        }

        switch outcome {
        case .timedOut:
            return .failure(.timedOut)
        case .finished(let stdout, let stderr, let code):
            guard code == 0 else {
                let text = String(decoding: stderr.suffix(EngineSessionConstants.stderrTailLimit), as: UTF8.self)
                if code == 2, text.contains("invalid choice") || text.contains("unknown command") {
                    return .failure(.commandMissing)
                }
                let last = text.split(whereSeparator: \.isNewline).last.map { String($0.prefix(200)) }
                return .failure(.failed("exit code \(code)" + (last.map { ": \($0)" } ?? "")))
            }
            return .success(stdout)
        }
    }

    private enum Outcome: Sendable {
        case finished(stdout: Data, stderr: Data, code: Int32)
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
