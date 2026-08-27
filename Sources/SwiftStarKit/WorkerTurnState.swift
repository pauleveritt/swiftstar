import Foundation

/// P11 (D4) worker-turn bookkeeping, pulled out of `AgentController` (item 1
/// of the P22 cleanup): the id/packet/consult-membership shape that used to
/// be three hand-synced properties (`activeWorkerId`, `activeWorkerPacket`,
/// `consultWorkers`), each cleared by hand in three separate places. Pure
/// value type, so the bookkeeping is unit-testable without the app target's
/// live `Process`/`Worktree` handles.
///
/// `PoolScheduler` serializes the engine to at most one *running* worker, so
/// `active` is a single optional slot — but consult membership is broader
/// than "the active worker": with a larger subagent pool, more than one
/// consult task can be enqueued (queued, not yet running) while only one
/// worker is active, so `consultWorkers` tracks membership independently and
/// survives `clearActive()`. Callers remove a worker's membership explicitly
/// when its turn is folded into a receipt (`finishWorkerTurn`/
/// `failActiveWorker`), not implicitly when the active slot clears.
public struct WorkerTurnState: Equatable, Sendable {
    /// The currently in-flight worker's identity and the packet its turn was
    /// started from (its `writableFiles` confine the worker's mutations).
    public struct Active: Equatable, Sendable {
        public let id: WorkerId
        public let packet: HandoffPacket
    }

    public private(set) var active: Active?
    /// Workers (queued or running) whose turn is a `/chat` consult rather than
    /// a dispatch — its answer is delivered directly, never as a receipt.
    public private(set) var consultWorkers: Set<WorkerId> = []

    public init() {}

    /// Begin a worker's turn: sets `active` to its id + packet. Does not touch
    /// `consultWorkers` — callers `markConsult` separately, at enqueue time.
    public mutating func start(id: WorkerId, packet: HandoffPacket) {
        active = Active(id: id, packet: packet)
    }

    /// End the active turn (finished, failed, or a session restart). Only the
    /// active slot clears — consult membership for this or any other worker
    /// is untouched; the caller removes it explicitly via `removeConsult`.
    public mutating func clearActive() {
        active = nil
    }

    public mutating func markConsult(_ id: WorkerId) {
        consultWorkers.insert(id)
    }

    public mutating func removeConsult(_ id: WorkerId) {
        consultWorkers.remove(id)
    }

    public func isConsult(_ id: WorkerId) -> Bool {
        consultWorkers.contains(id)
    }
}
