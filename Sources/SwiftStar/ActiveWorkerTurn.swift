import Foundation
import SwiftStarKit
import SwiftStarAppKit

/// P11 (D4) worker-turn state, consolidated (item 1 of the P22 cleanup): all
/// state that exists only while one pool worker's turn is in flight, wrapped
/// in a single value so `AgentController` has exactly one place that creates
/// and clears it. Previously six hand-synced properties
/// (`activeWorkerId`, `activeWorkerPacket`, `activeWorkerWorktree`,
/// `workerOutcomeBuilder`, `consultWorkers`, `workerWatchdogTask`) cleared by
/// hand in three places: the restart reset in `startAgent()`,
/// `failActiveWorker()`, and `finishWorkerTurn()`.
///
/// Wraps `SwiftStarKit.WorkerTurnState` (the pure id/packet/consult-membership
/// bookkeeping, unit-tested in `WorkerTurnStateTests`) together with the live
/// handles that cannot leave the app target: the disposable worktree
/// (`WorktreeDispatcher.Worktree` — its file mutations land here, never in
/// the caller's tree, the P10 isolation guarantee), the turn's
/// `TurnOutcomeBuilder`, and the watchdog `Task` that frees the pool if a
/// worker turn never reaches its `ready`.
struct ActiveWorkerTurn {
    private(set) var state = WorkerTurnState()
    var worktree: WorktreeDispatcher.Worktree?
    var outcomeBuilder: TurnOutcomeBuilder?
    var watchdog: Task<Void, Never>?

    var activeId: WorkerId? { state.active?.id }
    var activePacket: HandoffPacket? { state.active?.packet }

    /// Begin a worker's turn: the id/packet (delegated to `WorkerTurnState`),
    /// its disposable worktree, and a fresh outcome builder.
    mutating func start(id: WorkerId, packet: HandoffPacket,
                        worktree: WorktreeDispatcher.Worktree,
                        outcomeBuilder: TurnOutcomeBuilder) {
        state.start(id: id, packet: packet)
        self.worktree = worktree
        self.outcomeBuilder = outcomeBuilder
    }

    /// End the active turn (finished, failed, or a session restart): cancels
    /// the watchdog and drops the active slot + live handles. Consult
    /// membership is untouched — it is removed explicitly, per worker, by the
    /// caller (`finishWorkerTurn`/`failActiveWorker`), since a larger pool can
    /// have other consult workers still queued.
    mutating func clearActive() {
        watchdog?.cancel()
        state.clearActive()
        worktree = nil
        outcomeBuilder = nil
        watchdog = nil
    }

    mutating func markConsult(_ id: WorkerId) {
        state.markConsult(id)
    }

    mutating func removeConsult(_ id: WorkerId) {
        state.removeConsult(id)
    }

    func isConsult(_ id: WorkerId) -> Bool {
        state.isConsult(id)
    }
}
