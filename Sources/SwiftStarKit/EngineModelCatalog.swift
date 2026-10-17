import Foundation

// The engine's model list (`ds4-dogfood models --json`, schema_version 1) and
// the pure builders for the toolbar's model, context and folder menus.
// The views render `MenuChoice` values; nothing here touches UI or processes.

public enum CatalogError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case malformed(String)
    /// The command exited non-zero or could not be launched.
    case failed(String)
    case timedOut
    /// An engine older than ds4-engine TUI.35: the subcommand does not exist.
    /// The engine has no such subcommand; the name is the one asked for.
    case commandMissing(String)

    /// One line for the transcript note.
    public var reason: String {
        switch self {
        case .unsupportedSchema(let v): "unsupported schema_version \(v)"
        case .malformed(let m): "unreadable output (\(m))"
        case .failed(let m): m
        case .timedOut: "timed out"
        case .commandMissing(let name):
            "this ds4-dogfood has no `\(name)` command ("
                + (name == "models" ? "needs ds4-engine TUI.35 or later" : "update ds4-engine") + ")"
        }
    }
}

/// `models --json`: the models the engine knows, as ds4-engine sends them
/// (`tui_cli.py:196-222` at `a84b79bd`, EN.2 D7). Keys it never sent
/// (`family`, `default_context`, `measured_contexts`, `runs_in_tui`,
/// `saved_model_id`, `default_model_id`) were dropped in EN.2.
public struct EngineModelList: Decodable, Equatable, Sendable {
    public struct Model: Decodable, Equatable, Sendable {
        public let id: String
        public let displayName: String
        public let onThisMac: Bool
        public let path: String?
        public let downloadable: Bool
        public let fits: Bool?
        /// The context the engine would load it at, the one `planGiB` is for.
        public let context: Int?
        /// The pinned download's size, else the file's.
        public let sizeBytes: Int64?
        /// GPU memory the engine plans for it at `context`.
        public let planGiB: Double?

        enum CodingKeys: String, CodingKey {
            case id, path, downloadable, fits, context
            case displayName = "display_name"
            case onThisMac = "on_this_mac"
            case sizeBytes = "size_bytes"
            case planGiB = "plan_gib"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? id
            onThisMac = try c.decodeIfPresent(Bool.self, forKey: .onThisMac) ?? false
            path = try c.decodeIfPresent(String.self, forKey: .path)
            downloadable = try c.decodeIfPresent(Bool.self, forKey: .downloadable) ?? false
            fits = try c.decodeIfPresent(Bool.self, forKey: .fits)
            context = try c.decodeIfPresent(Int.self, forKey: .context)
            sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes)
            planGiB = try c.decodeIfPresent(Double.self, forKey: .planGiB)
        }
    }

    public let gpuBudgetBytes: Int?
    public let models: [Model]

    enum CodingKeys: String, CodingKey {
        case models
        case gpuBudgetBytes = "gpu_budget_bytes"
    }

    public static let supportedSchemaVersion = 1

    private struct Header: Decodable {
        let schemaVersion: Int
        enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // ds4-engine main (TUI.35) sends no `schema_version` at all yet;
            // its absence means version 1, not a malformed payload.
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        }
    }

    public static func decode(_ data: Data) -> Result<EngineModelList, CatalogError> {
        do {
            let header = try JSONDecoder().decode(Header.self, from: data)
            guard header.schemaVersion == supportedSchemaVersion else {
                return .failure(.unsupportedSchema(header.schemaVersion))
            }
            return .success(try JSONDecoder().decode(EngineModelList.self, from: data))
        } catch {
            return .failure(.malformed(String(describing: error)))
        }
    }

    public func model(id: String) -> Model? { models.first { $0.id == id } }
}


/// Identifies one load of the catalog: the engine path and, when known, its
/// file's modification date. An engine upgraded in place (same path, new
/// binary) changes `modifiedAt`, so it compares unequal to the prior key —
/// unlike comparing the path alone, which would miss the upgrade.
public struct CatalogCacheKey: Equatable, Sendable {
    public let path: String
    public let modifiedAt: Date?
    public init(path: String, modifiedAt: Date?) {
        self.path = path
        self.modifiedAt = modifiedAt
    }
}
