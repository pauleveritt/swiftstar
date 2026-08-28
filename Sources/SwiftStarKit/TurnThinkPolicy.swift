import Foundation

/// The per-turn think effort on the agent wire (P23, D1/D4/D6). `none` is
/// `/quick`'s no-think turn; `high` and `max` map 1:1 to the engine's
/// `DS4_THINK_HIGH`/`DS4_THINK_MAX`. Absent from the wire = the engine
/// default, which is `DS4_THINK_HIGH` on the shipped line.
public enum ThinkEffort: String, Sendable {
    /// The no-think turn (`/quick`). **Deliberately named `off`, not `none`**:
    /// this type is always passed as `ThinkEffort?`, and inside an Optional
    /// `.none` resolves to `Optional.none` — i.e. nil — silently. A case named
    /// `none` therefore makes `decide(requested: .none, …)` mean "send no
    /// override" instead of "send think=none", which would make `/quick` a
    /// no-op that still passes its own tests. The wire value stays `"none"`,
    /// which is what the engine parses.
    case off = "none"
    case high
    case max
}

/// What a think request resolves to, once the family and the advertised caps
/// are known (D3/D4). `.useDefault` sends nothing — the engine default runs
/// the turn. `.refused` is the loud app-side refusal for a prefix-busting
/// family; the engine refuses the same cases loudly if one slips through.
public enum TurnThinkDecision: Equatable, Sendable {
    case useDefault
    case override(ThinkEffort)
    case refused(reason: String)
}

/// The single decision authority for per-turn think (P23, spec component 1).
/// Pure: no I/O, no engine, no parser. `decide` is the only place that maps
/// (requested, family, cap) → decision; the `/quick` path, the dispatch path,
/// and the sampler record all consult it.
public struct TurnThinkPolicy {
    /// D3: the engine advertises the per-turn override with the new
    /// `"think_override"` cap (the base cap `"think"` is the think EVENT kind,
    /// present since P5, and cannot negotiate a feature). The app sends an
    /// override only when the cap is present; otherwise `.useDefault` — the
    /// wire never degrades silently.
    public static let overrideCap = "think_override"

    public static func decide(requested: ThinkEffort?, family: ModelFamily, capAdvertised: Bool) -> TurnThinkDecision {
        guard let requested else { return .useDefault }
        guard capAdvertised else { return .useDefault }
        switch family {
        case .glm:
            // D4: the reasoning-effort text is a system message at the front
            // of the transcript; a flip fails the sysprompt.kv memcmp and
            // forces a full system re-prefill AND a cache overwrite every flip.
            return .refused(reason: "glm cannot flip think mode per turn without a prefix bust")
        case .deepSeekV4Flash where requested == .max:
            // D4: MAX↔anything busts the prefix; HIGH↔NONE does not.
            return .refused(reason: "deepseek-v4-flash cannot flip think mode to max per turn without a prefix bust")
        default:
            return .override(requested)
        }
    }

    /// The wire effort for a handoff packet's declared `ThinkMode` (the
    /// capture-integrity fix: `SamplingPolicy.think` was written, validated,
    /// asserted — and read by nothing at dispatch time). `.bounded` maps to
    /// `.high`: the per-round ceiling is the process-level `--think-budget`
    /// standing guardrail (D6), not a distinct wire mode.
    public static func effort(for mode: ThinkMode) -> ThinkEffort {
        switch mode {
        case .off: return .off
        case .on, .bounded: return .high
        }
    }

    /// The effort actually used, rendered for `TurnOutcome.sampler` (P23
    /// retires the `"engine-defaults"` literal — it is false the moment the
    /// app sends any override; the outcome must record the truth).
    public static func samplerRecord(_ decision: TurnThinkDecision) -> String {
        switch decision {
        case .useDefault: return "think=default"
        case .override(let effort): return "think=\(effort.rawValue)"
        case .refused: return "think=refused"
        }
    }
}
