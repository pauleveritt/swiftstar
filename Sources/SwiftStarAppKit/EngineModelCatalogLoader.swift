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

    private static func run(
        executable: String, timeout: Duration, environment: [String: String]?
    ) -> Result<EngineModelList, CatalogError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["models", "--json"]
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(.failed("could not launch \(executable): \(error.localizedDescription)"))
        }
        let timedOut = Flag()
        let seconds = Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1e18
        let killer = DispatchWorkItem {
            timedOut.set()
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        if timedOut.isSet { return .failure(.timedOut) }
        guard process.terminationStatus == 0 else {
            return .failure(.failed("exit code \(process.terminationStatus)"))
        }
        return EngineModelList.decode(data)
    }
}
