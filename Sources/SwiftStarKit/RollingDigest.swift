import Foundation

/// The objective-independent "always-want" reduced form of the conversation
/// (D6): strip tool noise, keep the host-authoritative ledger. Maintained
/// incrementally, host-side, with no model and no inference — the packet-maker's
/// Layer 1, pre-chewed out-of-band. The raw conversation is never prefilled
/// again; only this digest is.
public struct RollingDigest: Equatable, Sendable {
    public var toolCalls: [String] = []
    public var filesTouched: [String] = []
    public var exitStatuses: [Int] = []
    public var validationRan = false
    public var refs: [WorkerId: String] = [:]
    public var receipts: [WorkerId: String] = [:]

    public init() {}

    /// The bounded, deterministic one-line-per-fact form the adaptation step
    /// reads (and the compaction ledger reconstructs from — D9).
    public func summary() -> String {
        var lines: [String] = []
        if !filesTouched.isEmpty { lines.append("files: \(filesTouched.joined(separator: ","))") }
        if !exitStatuses.isEmpty { lines.append("exit: \(exitStatuses.map(String.init).joined(separator: ","))") }
        if validationRan { lines.append("validated: true") }
        for (w, ref) in refs.sorted(by: { $0.key < $1.key }) { lines.append("Worker \(w.rawValue) ref: \(ref)") }
        for (w, reason) in receipts.sorted(by: { $0.key < $1.key }) { lines.append("Worker \(w.rawValue) refused: \(reason)") }
        return lines.joined(separator: "\n")
    }
}

/// The pure reducer that folds wire events and host facts into the digest.
public enum RollingDigestReducer {
    /// Fold one pooled wire event: tool calls are kept (the name only — the
    /// params, which carry the noise, are dropped); text/think/status are not
    /// digested (they are the noise being stripped).
    public static func apply(_ digest: RollingDigest, event: PoolWireEvent) -> RollingDigest {
        var d = digest
        switch event.event {
        case .toolRequest(_, let name, _):
            d.toolCalls.append(name)
        default:
            break
        }
        return d
    }

    /// The host's verdict on a tool call (P9/P10 facts): the actual mutations
    /// and the validation/exit facts — these, not the wire, are authoritative.
    public static func recordHostVerdict(_ digest: RollingDigest, mutations: [String],
                                         exitStatus: Int?, validationRan: Bool) -> RollingDigest {
        var d = digest
        d.filesTouched.append(contentsOf: mutations)
        if let exitStatus { d.exitStatuses.append(exitStatus) }
        if validationRan { d.validationRan = true }
        return d
    }

    /// Fold a worker's receipt into the ledger (D9): the ref or the refusal
    /// reason. This is the pool state that survives the orchestrator's
    /// compaction.
    public static func record(_ digest: RollingDigest, receipt: DispatchReceipt) -> RollingDigest {
        var d = digest
        if let ref = receipt.ref {
            d.refs[receipt.worker] = ref
        } else if let reason = receipt.reason {
            d.receipts[receipt.worker] = reason
        }
        return d
    }
}
