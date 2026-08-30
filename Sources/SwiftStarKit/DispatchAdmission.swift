import Foundation

/// P11 (D5) / P20: the host's decision on one `dispatch` tool call. The
/// orchestrator model supplies the objective and the writable files; the host
/// either admits the call (enqueue a pool worker) or refuses it with a reason.
///
/// Pure and unit-testable so the refusal reasons and the admission are pinned
/// by `DispatchAdmissionTests`. Extracted from `AgentController`'s inline
/// dispatch handler, which had three refusal branches but recorded a host
/// verdict (`TurnOutcomeBuilder.recordHostVerdict`) on only one of them (dumb
/// mode). The "malformed dispatch" and "subagent pool is full" branches wrote
/// the `tool_result` line and skipped the verdict, so a refused dispatch left
/// its outcome transition as `.emitted` only — a dead letter with no visible
/// refusal. This is the 2026-08-30 font-session finding: a read-only "build
/// and test" dispatch (empty `writableFiles`) was correctly refused but
/// recorded nothing. Every refusal is now a single `.refused` case, so the
/// controller records `rejected` on all of them.
public enum DispatchAdmission: Sendable {
    /// The decision: refuse (with the plain reason — the controller composes
    /// the wire's `"refused: …"` prefix) or admit (the packet plus the free
    /// worker id to enqueue).
    public enum Decision: Equatable, Sendable {
        case refused(String)
        case enqueue(packet: HandoffPacket, worker: WorkerId)
    }

    /// The pure admission gate. `dumb` keeps the eval baseline clean (a dumb
    /// run must not secretly dispatch workers and still win); a malformed call
    /// (missing `taskText`, or an empty `writableFiles` list) refuses with a
    /// reason that names the missing requirement; a full pool refuses so the
    /// caller never overflows the engine's fixed worker set.
    public static func decide(
        params: [ToolParam],
        digest: RollingDigest,
        loaded: [String: String],
        implementer: String,
        poolState: PoolState,
        dumb: Bool
    ) -> Decision {
        if dumb {
            return .refused("dispatch is disabled in dumb mode")
        }
        guard let packet = DispatchPacketBuilder.build(
            params: params, digest: digest, loaded: loaded, implementer: implementer) else {
            // A read-only "verify" dispatch (empty writableFiles) lands here.
            // Name both requirements so the model can self-correct: supply the
            // files the worker may write, or do the read-only work itself.
            return .refused(
                "dispatch is malformed (a non-empty taskText and a non-empty writableFiles list are required)")
        }
        guard let worker = PoolScheduler.availableWorker(poolState) else {
            return .refused("subagent pool is full")
        }
        return .enqueue(packet: packet, worker: worker)
    }

    /// Compose the tool result for a decision AND record the host's verdict on
    /// it, together, in one place. These two must not be separable: the
    /// 2026-08-30 dead letter was precisely a refusal that wrote its result
    /// line and skipped the verdict, leaving the outcome at `.emitted` with no
    /// visible refusal. Keeping the pair here — in Kit, under test — means the
    /// controller cannot write one without the other, and
    /// `DispatchAdmissionTests` fails if the verdict is ever dropped again.
    ///
    /// The caller still owns the side effects a decision implies (mutating
    /// `PoolState` on `.enqueue`, logging); only the wire-and-outcome pair
    /// lives here.
    public static func apply(_ decision: Decision, idx: Int,
                             into builder: inout TurnOutcomeBuilder?) -> ToolCallbackResponse {
        switch decision {
        case .refused(let reason):
            builder?.recordHostVerdict(idx: idx, ok: false, mutations: [], exitStatus: nil,
                                       outputDigest: nil, validationRan: false)
            return ToolCallbackResponse(
                idx: idx, ok: false, s: ToolResultCondenser.condense("refused: \(reason)"))
        case .enqueue(_, let worker):
            builder?.recordHostVerdict(idx: idx, ok: true, mutations: [], exitStatus: nil,
                                       outputDigest: nil, validationRan: false)
            return ToolCallbackResponse(
                idx: idx, ok: true, s: "dispatched as worker \(worker.rawValue)")
        }
    }

}
