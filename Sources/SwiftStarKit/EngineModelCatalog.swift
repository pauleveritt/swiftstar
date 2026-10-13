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
    case commandMissing

    /// One line for the transcript note.
    public var reason: String {
        switch self {
        case .unsupportedSchema(let v): "unsupported schema_version \(v)"
        case .malformed(let m): "unreadable output (\(m))"
        case .failed(let m): m
        case .timedOut: "timed out"
        case .commandMissing:
            "this ds4-dogfood has no `models` command (needs ds4-engine TUI.35 or later)"
        }
    }
}

public struct EngineModelList: Decodable, Equatable, Sendable {
    public struct MeasuredContext: Equatable, Sendable {
        public let context: Int
        public let planGiB: Double
        public init(context: Int, planGiB: Double) {
            self.context = context; self.planGiB = planGiB
        }
    }

    public struct Model: Decodable, Equatable, Sendable {
        public let id: String
        public let displayName: String
        public let family: String
        public let onThisMac: Bool
        public let path: String?
        public let downloadable: Bool
        public let fits: Bool?
        public let defaultContext: Int?
        public let measuredContexts: [MeasuredContext]
        public let runsInTUI: Bool

        enum CodingKeys: String, CodingKey {
            case id, family, path, downloadable, fits, context
            case runsInTUI = "runs_in_tui"
            case displayName = "display_name"
            case onThisMac = "on_this_mac"
            case defaultContext = "default_context"
            case measuredContexts = "measured_contexts"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? id
            family = try c.decodeIfPresent(String.self, forKey: .family) ?? ""
            onThisMac = try c.decodeIfPresent(Bool.self, forKey: .onThisMac) ?? false
            path = try c.decodeIfPresent(String.self, forKey: .path)
            downloadable = try c.decodeIfPresent(Bool.self, forKey: .downloadable) ?? false
            fits = try c.decodeIfPresent(Bool.self, forKey: .fits)
            // ds4-engine main (TUI.35) sends the model's context as `context`,
            // not `default_context`; prefer the richer key, fall back to it.
            defaultContext = try c.decodeIfPresent(Int.self, forKey: .defaultContext)
                ?? c.decodeIfPresent(Int.self, forKey: .context)
            runsInTUI = try c.decodeIfPresent(Bool.self, forKey: .runsInTUI) ?? true
            let pairs = try c.decodeIfPresent([[Double]].self, forKey: .measuredContexts) ?? []
            measuredContexts = pairs.compactMap {
                $0.count == 2 ? MeasuredContext(context: Int($0[0]), planGiB: $0[1]) : nil
            }
        }
    }

    public let gpuBudgetBytes: Int?
    public let savedModelID: String?
    public let defaultModelID: String?
    public let models: [Model]

    enum CodingKeys: String, CodingKey {
        case models
        case gpuBudgetBytes = "gpu_budget_bytes"
        case savedModelID = "saved_model_id"
        case defaultModelID = "default_model_id"
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


/// The "Model list unavailable" note is shown once per engine path, however
/// many loads, starts or restarts follow.
public struct CatalogNoteGate: Sendable {
    private var noted: Set<String> = []
    public init() {}

    /// True the first time `path` is claimed.
    public mutating func claim(path: String) -> Bool { noted.insert(path).inserted }
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
