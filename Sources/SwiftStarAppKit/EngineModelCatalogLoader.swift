import Foundation
import SwiftStarKit

/// Runs `<ds4-dogfood> models --json` off the main actor and decodes the list.
/// Any failure (older engine without the command, non-zero exit, timeout,
/// undecodable output) comes back as a `CatalogError`; callers fall back.
public enum EngineModelCatalogLoader {
    public static func load(
        executable: String, timeout: Duration = .seconds(10),
        environment: [String: String]? = nil
    ) async -> Result<EngineModelList, CatalogError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run(
                    executable: executable, timeout: timeout, environment: environment))
            }
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        var value: Data { lock.lock(); defer { lock.unlock() }; return data }
    }

    private static func run(
        executable: String, timeout: Duration, environment: [String: String]?
    ) -> Result<EngineModelList, CatalogError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["models", "--json"]
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        let err = Pipe()
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(.failed("could not launch \(executable): \(error.localizedDescription)"))
        }
        let timedOut = Flag()
        let seconds = Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1e18
        let pid = process.processIdentifier
        let killer = DispatchWorkItem {
            timedOut.set()
            if process.isRunning { process.terminate() }
            // A child that ignores SIGTERM is killed a second later.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: killer)
        // Read on its own thread so a pipe held open by a grandchild cannot
        // outlive the bound: the wait below gives up and closes the read end.
        let box = DataBox()
        let done = DispatchSemaphore(value: 0)
        let handle = out.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            box.set(handle.readDataToEndOfFile())
            done.signal()
        }
        let errBox = DataBox()
        let errDone = DispatchSemaphore(value: 0)
        let errHandle = err.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            errBox.set(errHandle.readDataToEndOfFile())
            errDone.signal()
        }
        if done.wait(timeout: .now() + seconds + 2) == .timedOut {
            timedOut.set()
            try? handle.close()
            return .failure(.timedOut)
        }
        process.waitUntilExit()
        killer.cancel()
        let data = box.value
        if timedOut.isSet { return .failure(.timedOut) }
        guard process.terminationStatus == 0 else {
            _ = errDone.wait(timeout: .now() + 1)
            let text = String(decoding: errBox.value.prefix(4096), as: UTF8.self)
            if process.terminationStatus == 2,
               text.contains("invalid choice") || text.contains("unknown command") {
                return .failure(.commandMissing)
            }
            let last = text.split(whereSeparator: \.isNewline).last.map { String($0.prefix(200)) }
            return .failure(.failed(
                "exit code \(process.terminationStatus)" + (last.map { ": \($0)" } ?? "")))
        }
        return EngineModelList.decode(data)
    }
}
