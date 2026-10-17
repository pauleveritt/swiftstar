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
        list: EngineModelList?, settingsID: String, loadedID: String?, locale: Locale = .current
    ) -> [MenuChoice<String>] {
        let current = trimmed(settingsID)
        var out = [MenuChoice(title: "Engine default", value: "", isChecked: current.isEmpty)]
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
                else if m.fits == false { "doesn't fit" }
                else { nil }
            out.append(MenuChoice(
                title: title(m, locale: locale), value: m.id, isChecked: m.id == current, disabledReason: reason))
        }
        if !current.isEmpty, list.model(id: current) == nil {
            out.append(MenuChoice(title: current, value: current, isChecked: true))
        }
        return out
    }

    /// "Qwen3.8 27B — 15.7 GiB, plans 24.7 GiB": the file and what the engine
    /// plans to load it in (EN.2, D7); the name alone when it sends neither.
    static func title(_ m: EngineModelList.Model, locale: Locale) -> String {
        let parts = [
            m.sizeBytes.map { MetricsFormatting.gib(bytes: $0, locale: locale) },
            m.planGiB.map { "plans \(MetricsFormatting.gib($0, locale: locale))" },
        ].compactMap { $0 }
        return parts.isEmpty ? m.displayName : "\(m.displayName) — " + parts.joined(separator: ", ")
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

    /// The first item ("Engine default", value 0) is always present, naming
    /// the model's context and plan when the engine sends them (EN.2, D7).
    /// Round sizes up to 65,536 are listed, plus the model's context. `settingsContext`
    /// <= 0 means engine default. `loaded` is shown only in the fallback.
    public static func items(
        list: EngineModelList?, modelID: String?, settingsContext: Int, loaded: Int?,
        locale: Locale = .current
    ) -> [MenuChoice<Int>] {
        let grouped = { (n: Int) in MetricsFormatting.number(n, locale: locale) }
        let id = trimmed(modelID)
        let model = id.isEmpty ? nil : list?.model(id: id)
        let named = [
            model?.context.map(grouped),
            model?.planGiB.map { MetricsFormatting.gib($0, locale: locale) },
        ].compactMap { $0 }
        let defaultTitle = named.isEmpty ? "Engine default" : "Engine default (\(named.joined(separator: " · ")))"
        var out = [MenuChoice(title: defaultTitle, value: 0, isChecked: settingsContext <= 0)]

        var sizes = Set(roundSizes.filter { $0 <= fallbackLimit })
        if let context = model?.context, context > 0 { sizes.insert(context) }
        if settingsContext > 0 { sizes.insert(settingsContext) }
        if list == nil, let loaded, loaded > 0 { sizes.insert(loaded) }
        for size in sizes.sorted() {
            out.append(MenuChoice(title: grouped(size), value: size, isChecked: size == settingsContext))
        }
        return out
    }
}

public enum RecentWorkspaces {
    /// Most recent first, deduplicated, capped.
    public static func updated(_ list: [String], adding path: String, cap: Int = 5) -> [String] {
        Array(([path] + list.filter { $0 != path }).prefix(max(0, cap)))
    }
}

/// A Recent folder, with its project's newest conversation it can resume
/// (SU.7b, D2).
public struct RecentProject: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let title: String
    public let isCurrent: Bool
    public let disabledReason: String?
    /// Nil for the current project (its conversations are in the sidebar),
    /// a missing folder, or a project with nothing to resume.
    public let latest: Conversation?
    /// "Hello · 12m ago".
    public let latestLabel: String?

    /// The project row: "beta · Add a menu · 12m ago", or "beta — folder
    /// not found".
    public var menuTitle: String {
        let base = latestLabel.map { "\(title) · \($0)" } ?? title
        return disabledReason.map { "\(base) — \($0)" } ?? base
    }

    /// The resume item under it: `Resume "Add a menu" · 12m ago`.
    public var resumeTitle: String? {
        guard let label = latestLabel else { return nil }
        guard let dot = label.range(of: " · ", options: .backwards) else { return "Resume \"\(label)\"" }
        return "Resume \"\(label[..<dot.lowerBound])\" · \(label[dot.upperBound...])"
    }

    public init(path: String, title: String, isCurrent: Bool, disabledReason: String?,
                latest: Conversation?, latestLabel: String?) {
        self.path = path; self.title = title; self.isCurrent = isCurrent
        self.disabledReason = disabledReason; self.latest = latest; self.latestLabel = latestLabel
    }
}

public enum RecentProjects {
    /// One row per Recent folder, in order. A folder's sessions are those
    /// whose `source` is its git root (`rootOf`, else the folder itself),
    /// compared after resolving symlinks: the engine records the path a
    /// session started from, unresolved.
    public static func items(
        recents: [String], entries: [EngineSessionEntry], current: String?,
        exists: (String) -> Bool, rootOf: (URL) -> URL?, now: Date, locale: Locale = .current
    ) -> [RecentProject] {
        let bySource = Dictionary(grouping: entries.filter { $0.source != nil }) { normalized($0.source!) }
        return recents.map { path in
            let url = URL(fileURLWithPath: path)
            let isCurrent = path == current
            let disabledReason = exists(path) ? nil : "folder not found"
            var latest: Conversation?
            if !isCurrent, disabledReason == nil {
                let root = rootOf(url) ?? url
                latest = Conversations.group(bySource[normalized(root.path)] ?? []).first(where: \.resumable)
            }
            return RecentProject(
                path: path, title: url.leafName, isCurrent: isCurrent, disabledReason: disabledReason,
                latest: latest, latestLabel: latest.map { label($0, now: now, locale: locale) })
        }
    }

    /// The title, cut at 40 characters, then " · " and how long ago.
    public static func label(_ c: Conversation, now: Date, locale: Locale) -> String {
        let title = c.title.count > 40 ? String(c.title.prefix(40)) + "…" : c.title
        let when = Conversations.subtitle(
            Conversation(id: c.id, title: c.title, updated: c.updated, modelID: nil, resumable: c.resumable,
                         problems: c.problems, sessionIDs: c.sessionIDs),
            now: now, locale: locale)
        return when.isEmpty ? title : "\(title) · \(when)"
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
