import Foundation

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
    s?.trimmedOrNil ?? ""
}

/// What a model-menu pick does (EN.1, D3).
public enum ModelMenuAction: Equatable, Sendable {
    /// Send `/model ID` and honour the relaunch: new conversation, files kept.
    case sendModelCommand
    /// Save the choice; the next (or a restarted) session starts with it.
    case restart
}

public enum ModelMenu {
    /// The toolbar label: the loaded model, else the choice ("Engine default"
    /// when there is none). A choice that differs from what's loaded, such as
    /// a skipped restart, reads "loaded → chosen".
    public static func label(loaded: String?, chosen: String) -> String {
        guard let loaded else { return chosen.isEmpty ? "Engine default" : chosen }
        return chosen.isEmpty || chosen == loaded ? loaded : "\(loaded) → \(chosen)"
    }

    /// A pick while a session runs goes through the engine's `/model`; any
    /// other phase just saves it for a fresh start.
    public static func selectionAction(phase: EngineSessionPhase) -> ModelMenuAction {
        phase == .running ? .sendModelCommand : .restart
    }

    /// The model id to start with: a saved id the engine's list no longer
    /// offers is cleared, with a notice saying so (as the engine does for its
    /// own config.toml). Without a list the saved id is kept.
    public static func validated(saved: String, list: EngineModelList?) -> (modelID: String, notice: String?) {
        let id = trimmed(saved)
        guard !id.isEmpty, let list, list.model(id: id) == nil else { return (id, nil) }
        return ("", "\(id) isn't offered by the engine; using the engine default")
    }

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
    /// The toolbar label, as for the model: "8192 ctx", "Default ctx", or
    /// "8192 → 4096 ctx" when the choice differs from what's loaded.
    public static func label(loaded: Int?, chosen: Int) -> String {
        let plain = { (n: Int) in n.formatted(.number.grouping(.never)) }
        guard let loaded else { return chosen > 0 ? "\(plain(chosen)) ctx" : "Default ctx" }
        return chosen > 0 && chosen != loaded ? "\(plain(loaded)) → \(plain(chosen)) ctx" : "\(plain(loaded)) ctx"
    }

    /// A typed custom size: a positive whole number, else nil.
    public static func parseCustom(_ text: String) -> Int? {
        guard let n = text.trimmedOrNil.flatMap({ Int($0) }), n > 0 else { return nil }
        return n
    }

    public static let roundSizes = [8192, 16384, 32768, 65536, 131072]
    public static let fallbackLimit = 65536

    /// The first item ("Engine default", value 0) is always present. Measured
    /// sizes are always listed; round sizes only up to twice the largest
    /// measured size (up to 65,536 without measurements). `settingsContext`
    /// <= 0 means engine default. `loaded` is shown only in the fallback.
    public static func items(
        list: EngineModelList?, modelID: String?, settingsContext: Int, loaded: Int?,
        locale: Locale = .current
    ) -> [MenuChoice<Int>] {
        let grouped = { (n: Int) in MetricsFormatting.number(n, locale: locale) }
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
            let title = plan.map { "\(grouped(size)) (\(MetricsFormatting.gib($0.planGiB, locale: locale)))" }
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
                title: URL(fileURLWithPath: path).leafName, value: path,
                isChecked: path == current,
                disabledReason: exists(path) ? nil : "folder not found")
        }
    }
}
