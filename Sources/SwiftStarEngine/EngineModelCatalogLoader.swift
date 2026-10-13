import Foundation
import SwiftStarKit

/// Runs `<ds4-dogfood> models --json` and decodes the list. Any failure
/// (older engine without the command, non-zero exit, timeout, undecodable
/// output) comes back as a `CatalogError`; callers fall back.
public enum EngineModelCatalogLoader {
    public static func load(
        executable: String, timeout: Duration = .seconds(10),
        environment: [String: String]? = nil
    ) async -> Result<EngineModelList, CatalogError> {
        let ran = await ProcessRunner.run(
            executable: executable, arguments: ["models", "--json"],
            timeout: timeout, environment: environment)
        switch ran {
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
            return EngineModelList.decode(out.stdout)
        }
    }
}
