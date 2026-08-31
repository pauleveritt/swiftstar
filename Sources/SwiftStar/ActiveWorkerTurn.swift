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
    private(set) var interrupted = false
    private(set) var toolTask: Task<ToolCallbackResponse, Never>? = nil
    private var toolBudget = ToolCallBudgetTracker(budget: 0)

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
        self.interrupted = false
        self.toolTask = nil
        self.toolBudget = ToolCallBudgetTracker(budget: packet.toolCallBudget)
    }

    /// Record that the user stopped this pooled turn. The engine should emit
    /// its normal interrupted `ready`, but the controller uses this local fact
    /// to avoid surfacing partial consult prose as a completed answer.
    mutating func markInterrupted() {
        interrupted = true
        toolTask?.cancel()
    }

    mutating func setToolTask(_ task: Task<ToolCallbackResponse, Never>) {
        toolTask = task
    }

    mutating func clearToolTask() {
        toolTask = nil
    }

    mutating func cancelToolTask() {
        toolTask?.cancel()
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
        interrupted = false
        toolTask?.cancel()
        toolTask = nil
        toolBudget = ToolCallBudgetTracker(budget: 0)
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

    /// Admit one emitted worker request against the packet's per-turn budget.
    /// The tracker is reset with the active turn and cleared with it, so a
    /// worker cannot inherit calls from a prior packet.
    mutating func admitToolCall() -> Bool {
        toolBudget.admit()
    }
}
