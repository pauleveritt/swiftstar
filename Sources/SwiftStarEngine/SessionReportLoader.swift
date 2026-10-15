import Foundation
import SwiftStarKit

/// Why a session report couldn't be made, as one line for the transcript.
public struct SessionReportFailure: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// Runs `<ds4-dogfood> report <dir> --json` (AN.4) for one session
/// directory and returns `SessionReport`'s Markdown (AN.2's report card and
/// the fork's prompt).
public enum SessionReportLoader {
    public static func load(
        executable: String, sessionDirectory: URL, timeout: Duration = .seconds(10),
        environment: [String: String]? = nil
    ) async -> Result<String, SessionReportFailure> {
        await EngineJSONCommand.run(
            executable: executable, arguments: EngineCommand.reportArguments(sessionDirectory: sessionDirectory),
            timeout: timeout, environment: environment
        )
        .flatMap(SessionReport.decode)
        .map { $0.markdown() }
        .mapError { SessionReportFailure(message: $0.reason) }
    }
}
