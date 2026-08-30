import Foundation

/// How long a turn actually took, separated from how long the capture was open.
///
/// A capture's wire span is not a turn duration. The wire opens when the engine
/// starts; in an app session the turn does not begin until the human has
/// finished typing, and `swiftstar-drive` submits its prompt immediately. So the
/// two harnesses' wire spans are not comparable, and neither is a turn time.
///
/// Measured on `captures/live/20260830-180004`: the wire spans 573.6s, of which
/// the first 52.8s is engine start plus typing. Reading the wire span as the
/// turn duration overstates it by 22% and, compared against a drive capture,
/// manufactures a difference that is entirely harness shape.
///
/// `leadIn` is reported rather than silently dropped — a reader who is handed
/// only the corrected number cannot tell whether a correction happened.
public struct TurnSpan: Equatable, Sendable {
    /// Seconds from the turn's first status to its first non-idle one.
    public let leadInSeconds: Double
    /// Seconds from the turn's first non-idle status to its last status.
    public let workSeconds: Double

    public init(leadInSeconds: Double, workSeconds: Double) {
        self.leadInSeconds = leadInSeconds
        self.workSeconds = workSeconds
    }

    /// Measure one turn's statuses, in wire order. Returns nil when the turn
    /// never left `idle` (nothing to time) or when `ts` is not monotonic (the
    /// wire's clock is CLOCK_MONOTONIC microseconds — going backwards means a
    /// corrupt capture, and a negative duration is worse than no duration).
    public static func measure(_ statuses: [StatusSnapshot]) -> TurnSpan? {
        guard let first = statuses.first,
              let startIndex = statuses.firstIndex(where: { $0.state != "idle" }),
              let last = statuses.last
        else { return nil }
        let start = statuses[startIndex]
        guard start.ts >= first.ts, last.ts >= start.ts else { return nil }
        return TurnSpan(
            leadInSeconds: Double(start.ts - first.ts) / 1_000_000,
            workSeconds: Double(last.ts - start.ts) / 1_000_000)
    }
}
