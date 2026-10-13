import Foundation
import SwiftStarKit

/// Runs `<ds4-dogfood> models --json` and decodes the list. Any failure
/// comes back as a `CatalogError`; callers fall back.
public enum EngineModelCatalogLoader {
    public static func load(
        executable: String, timeout: Duration = .seconds(10),
        environment: [String: String]? = nil
    ) async -> Result<EngineModelList, CatalogError> {
        await EngineJSONCommand.run(
            executable: executable, arguments: ["models", "--json"], timeout: timeout, environment: environment
        ).flatMap(EngineModelList.decode)
    }
}
