import Foundation

/// One capture directory's identity for the retention decision: a name
/// (the directory's last path component — the caller resolves it back to a
/// full URL to delete), its filesystem modification date, and its size
/// (carried through so a caller can log bytes freed without a second stat
/// pass; the decision itself never uses it).
public struct CaptureEntry: Equatable, Sendable {
    public let name: String
    public let modified: Date
    public let sizeBytes: Int64

    public init(name: String, modified: Date, sizeBytes: Int64) {
        self.name = name
        self.modified = modified
        self.sizeBytes = sizeBytes
    }
}

/// A retention policy for one producer tree's capture directories. Two knobs,
/// combined by union (keep wins): keep the `keepCount` most-recently-modified
/// directories, AND keep anything modified within `keepDays` of "now" —
/// whichever rule would keep a given directory, it is kept. This is the
/// conservative combination: a directory is deleted only when BOTH rules agree
/// it is expendable (old by count AND old by age), so neither knob alone can
/// cause a surprise mass deletion — e.g. a burst of 50 captures in one day
/// (agenttest CI-style churn) does not blow past `keepCount` and delete
/// same-day evidence, and a lone stale directory from months ago does not
/// survive just because the tree has fewer than `keepCount` entries overall.
public struct CaptureRetentionPolicy: Equatable, Sendable {
    public let keepCount: Int
    public let keepDays: Int

    /// Defaults: keep the 20 most recent capture directories, or anything from
    /// the last 14 days — whichever is more. Chosen because `captures/agenttest/`
    /// (the largest producer) can produce several directories per day during
    /// active iteration, so a pure day cutoff alone could still discard a whole
    /// afternoon's worth of same-day debugging evidence; a pure count cutoff
    /// alone could discard last week's captures during a quiet stretch. The
    /// union keeps a look-back window useful for "what changed since
    /// yesterday" debugging without needing either knob to be generous enough
    /// to cover both cases by itself. Both knobs are overridable via
    /// `UserDefaults` (see `AgentController.captureRetentionPolicy`).
    public init(keepCount: Int = 20, keepDays: Int = 14) {
        self.keepCount = keepCount
        self.keepDays = keepDays
    }
}

/// Pure decision logic for pruning stale session captures (`captures/live/`,
/// `captures/agenttest/`, and the root-level `swiftstar-drive` directories).
/// No filesystem access here — a caller stats the real directories, builds
/// `CaptureEntry` values, and this decides which to delete; the caller does
/// the actual `FileManager.removeItem` (and the logging).
///
/// `captures/evidence/` is never a producer tree this function is called
/// against — the wiring layer must never enumerate it in the first place, so
/// it is permanently exempt structurally, not by policy. As a second,
/// belt-and-suspenders line of defense, this function also refuses to ever
/// select an entry literally named `evidence` for deletion, even if one is
/// fed in by mistake.
public enum CaptureRetention {
    /// Directory names (from `entries`) to delete under `policy`, given `now`
    /// as the reference time (pass a fixed date in tests for determinism —
    /// production callers use the default `Date()`).
    public static func directoriesToDelete(
        entries: [CaptureEntry], policy: CaptureRetentionPolicy, now: Date = Date()
    ) -> [CaptureEntry] {
        // Belt-and-suspenders: `captures/evidence/` must never be deleted by
        // this policy, even if a caller's entry list accidentally includes it.
        let candidates = entries.filter { $0.name != "evidence" }
        guard !candidates.isEmpty else { return [] }

        let cutoff = now.addingTimeInterval(-Double(policy.keepDays) * 86_400)
        let mostRecentFirst = candidates.sorted { $0.modified > $1.modified }
        let keptByRecency = Set(mostRecentFirst.prefix(max(policy.keepCount, 0)).map(\.name))

        // Delete only what neither rule wants to keep: not in the top
        // `keepCount` by modification date, AND older than the day cutoff.
        // `modified < cutoff` (strict) so a directory exactly `keepDays` old
        // is still kept — the cutoff is the oldest day still "recent."
        return candidates.filter { entry in
            !keptByRecency.contains(entry.name) && entry.modified < cutoff
        }
    }
}
