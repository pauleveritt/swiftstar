import Foundation
import SwiftStarKit

/// Why a session report couldn't be made, as one line for the transcript.
public struct SessionReportFailure: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// Runs AN.1's `session_last.py`, bundled with this target, for one session
/// directory and returns its Markdown (AN.2). At AN.4 the argv becomes
/// `ds4-dogfood last --session`, in `EngineCommand.reportArguments`.
public enum SessionReportLoader {
    public static var bundledScript: URL? {
        Bundle.module.url(forResource: "session_last", withExtension: "py")
    }

    public static func load(
        sessionDirectory: URL, script: URL? = bundledScript, timeout: Duration = .seconds(10)
    ) async -> Result<String, SessionReportFailure> {
        guard let script, FileManager.default.fileExists(atPath: script.path) else {
            return .failure(SessionReportFailure(message: "report script not found"))
        }
        let (executable, arguments) = EngineCommand.reportArguments(script: script, sessionDirectory: sessionDirectory)
        switch await ProcessRunner.run(executable: executable, arguments: arguments, timeout: timeout) {
        case .failure(.timedOut):
            return .failure(SessionReportFailure(message: "the report timed out"))
        case .failure(.launch(let message)):
            return .failure(SessionReportFailure(message: message))
        case .success(let out):
            guard out.code == 0 else {
                let text = String(decoding: out.stderr.suffix(EngineSessionConstants.stderrTailLimit), as: UTF8.self)
                let last = text.split(whereSeparator: \.isNewline).last.map { String($0.prefix(300)) }
                return .failure(SessionReportFailure(message: last ?? "exit code \(out.code)"))
            }
            return .success(String(decoding: out.stdout, as: UTF8.self))
        }
    }
}
