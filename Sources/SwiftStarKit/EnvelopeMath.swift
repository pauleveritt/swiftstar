import Foundation

/// One arm of the sensitivity envelope (D11): the deterministic perturbations
/// of the canonical packet set — no model judgment anywhere in the sweep.
public enum PacketPerturbation: String, CaseIterable, Equatable, Sendable {
    case canonical
    case taskTextBloat15x
    case taskTextBloat2x
    case failureInjection
    case packetCountSweep
}

/// The gate's report (D11): an envelope, not a point. `overheadRatio` is the
/// realized win over the analytic ceiling; `winByPerturbation` is the
/// sensitivity envelope; the counters are the instrumentation.
public struct EnvelopeReport: Equatable, Sendable {
    public let overheadRatio: Double
    public let winByPerturbation: [PacketPerturbation: Double]
    public let tokensEvaluated: Int
    public let tokensNominal: Int
    public let peakResidentMB: Int
    public let snapshotSaveCount: Int
    public let snapshotRestoreCount: Int
}

/// The pure arithmetic of the measurement gate (D11).
public enum EnvelopeMath {
    /// The analytic upper bound (research note): 8 × 16k sequential prefills
    /// vs one 131k prefill, integrated from the measured curve.
    public static let ceiling = 4.2

    /// realized win / ceiling. A realized win of 0 is a ratio of 0 (not NaN);
    /// the win is `deepSeconds / poolSeconds`.
    public static func overheadRatio(realizedWin: Double) -> Double {
        realizedWin / ceiling
    }

    public static func report(winByPerturbation: [PacketPerturbation: Double],
                              tokensEvaluated: Int, tokensNominal: Int,
                              peakResidentMB: Int,
                              snapshotSaveCount: Int, snapshotRestoreCount: Int) -> EnvelopeReport {
        EnvelopeReport(
            overheadRatio: overheadRatio(realizedWin: winByPerturbation[.canonical] ?? 0),
            winByPerturbation: winByPerturbation,
            tokensEvaluated: tokensEvaluated,
            tokensNominal: tokensNominal,
            peakResidentMB: peakResidentMB,
            snapshotSaveCount: snapshotSaveCount,
            snapshotRestoreCount: snapshotRestoreCount)
    }
}

/// The deterministic perturbation constructors (D11): each arm is built by a
/// pure function over the canonical packet, never by ad-hoc shell logic.
extension PacketPerturbation {
    /// The counts the packet-count sweep runs (D11).
    public static let packetCountSweepCounts = [1, 2, 4, 8]

    /// Apply this perturbation to a canonical `taskText` (deterministic filler;
    /// bloat simulates a wordier brief to sample the prefill curve's response to
    /// input size). `.canonical`/`.failureInjection`/`.packetCountSweep` leave
    /// the text unchanged.
    public func apply(to taskText: String) -> String {
        switch self {
        case .taskTextBloat15x: return taskText + String(repeating: " detail", count: taskText.count / 2)
        case .taskTextBloat2x:  return taskText + String(repeating: " detail", count: taskText.count)
        case .canonical, .failureInjection, .packetCountSweep: return taskText
        }
    }
}
