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

    /// One line for the transcript note.
    public var reason: String {
        switch self {
        case .unsupportedSchema(let v): "unsupported schema_version \(v)"
        case .malformed(let m): "unreadable output (\(m))"
        case .failed(let m): m
        case .timedOut: "timed out"
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
            case id, family, path, downloadable, fits
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
            defaultContext = try c.decodeIfPresent(Int.self, forKey: .defaultContext)
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

/// One menu row: a title, the value it selects, whether it is ticked, and, when
/// it cannot be chosen, why (the view shows the reason and disables the row).
/// "Other…" / "Custom…" and dividers are not modelled; the views add them.
public struct MenuChoice<Value: Equatable & Sendable>: Equatable, Sendable {
    public let title: String
    public let value: Value
    public let isChecked: Bool
    public let disabledReason: String?

    public init(title: String, value: Value, isChecked: Bool, disabledReason: String? = nil) {
        self.title = title; self.value = value
        self.isChecked = isChecked; self.disabledReason = disabledReason
    }
}

private func trimmed(_ s: String?) -> String {
    s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private func grouped(_ n: Int) -> String {
    n.formatted(.number.locale(Locale(identifier: "en_US")))
}

public enum ModelMenu {
    /// The first item ("Engine default", value "") is always present. `settingsID`
    /// is the Settings choice ("" = engine default); `loadedID` is shown only in
    /// the fallback so the running model is reachable when no list is known.
    public static func items(
        list: EngineModelList?, settingsID: String, loadedID: String?
    ) -> [MenuChoice<String>] {
        let current = trimmed(settingsID)
        let defaultTitle = list?.defaultModelID.map { "Engine default (\($0))" } ?? "Engine default"
        var out = [MenuChoice(title: defaultTitle, value: "", isChecked: current.isEmpty)]
        guard let list else {
            if !current.isEmpty {
                out.append(MenuChoice(title: current, value: current, isChecked: true))
            }
            if let loaded = loadedID, !loaded.isEmpty, loaded != current {
                out.append(MenuChoice(title: loaded, value: loaded, isChecked: false))
            }
            return out
        }
        for m in list.models {
            let reason: String? =
                if !m.onThisMac { "not on this Mac" }
                else if !m.runsInTUI { "not usable in the TUI" }
                else if m.fits == false { "doesn't fit" }
                else { nil }
            out.append(MenuChoice(
                title: m.displayName, value: m.id, isChecked: m.id == current, disabledReason: reason))
        }
        if !current.isEmpty, list.model(id: current) == nil {
            out.append(MenuChoice(title: current, value: current, isChecked: true))
        }
        return out
    }
}

public enum ContextMenu {
    public static let roundSizes = [8192, 16384, 32768, 65536, 131072]
    public static let fallbackLimit = 65536

    /// The first item ("Engine default", value 0) is always present. Measured
    /// sizes are always listed; round sizes only up to twice the largest
    /// measured size (up to 65,536 without measurements). `settingsContext`
    /// <= 0 means engine default. `loaded` is shown only in the fallback.
    public static func items(
        list: EngineModelList?, modelID: String?, settingsContext: Int, loaded: Int?
    ) -> [MenuChoice<Int>] {
        let id = trimmed(modelID).isEmpty ? list?.defaultModelID : trimmed(modelID)
        let model = id.flatMap { list?.model(id: $0) }
        let measured = model?.measuredContexts ?? []
        let defaultTitle = model?.defaultContext.map { "Engine default (\(grouped($0)))" } ?? "Engine default"
        var out = [MenuChoice(title: defaultTitle, value: 0, isChecked: settingsContext <= 0)]

        let limit = measured.map(\.context).max().map { $0 * 2 } ?? fallbackLimit
        var sizes = Set(measured.map(\.context))
        sizes.formUnion(roundSizes.filter { $0 <= limit })
        if settingsContext > 0 { sizes.insert(settingsContext) }
        if list == nil, let loaded, loaded > 0 { sizes.insert(loaded) }
        for size in sizes.sorted() {
            let plan = measured.first { $0.context == size }
            let title = plan.map { "\(grouped(size)) (\(String(format: "%.1f", $0.planGiB)) GiB)" }
                ?? grouped(size)
            out.append(MenuChoice(title: title, value: size, isChecked: size == settingsContext))
        }
        return out
    }
}

public enum RecentWorkspaces {
    /// Most recent first, deduplicated, capped.
    public static func updated(_ list: [String], adding path: String, cap: Int = 5) -> [String] {
        Array(([path] + list.filter { $0 != path }).prefix(max(0, cap)))
    }

    /// Menu rows for the recent folders; one that no longer exists is disabled.
    public static func items(
        _ list: [String], current: String?, exists: (String) -> Bool
    ) -> [MenuChoice<String>] {
        list.map { path in
            MenuChoice(
                title: PathAbbreviation.leafName(URL(fileURLWithPath: path)), value: path,
                isChecked: path == current,
                disabledReason: exists(path) ? nil : "folder not found")
        }
    }
}
