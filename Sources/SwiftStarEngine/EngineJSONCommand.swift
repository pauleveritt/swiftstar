import Foundation
import SwiftStarKit

/// Runs `<ds4-dogfood> <arguments>` for a JSON command (`models --json`,
/// `sessions --json`) and returns its stdout. Any failure (an older engine
/// without the command, a non-zero exit, a timeout) comes back as a
/// `CatalogError`; callers fall back. The process itself is `ProcessRunner`'s.
enum EngineJSONCommand {
    static func run(
        executable: String, arguments: [String], timeout: Duration, environment: [String: String]?
    ) async -> Result<Data, CatalogError> {
        switch await ProcessRunner.run(
            executable: executable, arguments: arguments, timeout: timeout, environment: environment) {
        case .failure(.timedOut):
            return .failure(.timedOut)
        case .failure(.launch(let message)):
            return .failure(.failed(message))
        case .success(let out):
            guard out.code == 0 else {
                let text = String(decoding: out.stderr.suffix(EngineSessionConstants.stderrTailLimit), as: UTF8.self)
                if out.code == 2, text.contains("invalid choice") || text.contains("unknown command") {
                    return .failure(.commandMissing)
                }
                let last = text.split(whereSeparator: \.isNewline).last.map { String($0.prefix(200)) }
                return .failure(.failed("exit code \(out.code)" + (last.map { ": \($0)" } ?? "")))
            }
            return .success(out.stdout)
        }
    }
}
