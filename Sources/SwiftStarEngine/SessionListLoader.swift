import Foundation
import SwiftStarKit

/// Runs `<ds4-dogfood> sessions --json --source <root> --limit <n>` (SU.7a):
/// the repository's earlier sessions, newest first.
public enum SessionListLoader {
    public static func load(
        executable: String, source: URL, limit: Int = 50, timeout: Duration = .seconds(10),
        environment: [String: String]? = nil
    ) async -> Result<[EngineSessionEntry], CatalogError> {
        await EngineJSONCommand.run(
            executable: executable,
            arguments: ["sessions", "--json", "--source", source.path, "--limit", String(limit)],
            timeout: timeout, environment: environment
        ).flatMap(EngineSessionEntry.decodeList)
    }

    /// `sessions --json --all --limit <n>` (SU.7b): every repository's
    /// sessions, newest first, for the Recent menus' labels.
    public static func loadAll(
        executable: String, limit: Int = 200, timeout: Duration = .seconds(10),
        environment: [String: String]? = nil
    ) async -> Result<[EngineSessionEntry], CatalogError> {
        await EngineJSONCommand.run(
            executable: executable, arguments: ["sessions", "--json", "--all", "--limit", String(limit)],
            timeout: timeout, environment: environment
        ).flatMap(EngineSessionEntry.decodeList)
    }
}
