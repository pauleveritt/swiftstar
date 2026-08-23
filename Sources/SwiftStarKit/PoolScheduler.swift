import Foundation

/// The pool's state (D1): the queue of pending workers, the currently running
/// worker (at most one — the serialized family), the completed receipts, and
/// receipts awaiting delivery back into the orchestrator. Pure value type.
public struct PoolState: Equatable, Sendable {
    public var pending: [WorkerId: HandoffPacket] = [:]
    public var running: WorkerId?
    public var completed: [WorkerId: DispatchReceipt] = [:]
    public var pendingDelivery: [WorkerId: DispatchReceipt] = [:]
    /// The free worker-session ids (`1...workerCapacity`), in ascending order.
    /// The engine hosts a FIXED number of worker sessions (N-1); ids must be
    /// reused, never grown past that bound — an unbounded id would overflow the
    /// engine's pool and be silently clamped to the orchestrator.
    public var freeIds: [WorkerId] = []
    public init(workerCapacity: Int = 64) {
        self.freeIds = (1...max(workerCapacity, 1)).map { WorkerId($0) }
    }
}

/// A command that transitions `PoolState` (D1). Pure; `PoolScheduler.apply` is
/// a function of state + command.
public enum PoolCommand: Equatable, Sendable {
    case enqueue(packet: HandoffPacket)
    case workerStarted(WorkerId)
    case workerFinished(WorkerId, DispatchReceipt)
    /// An infrastructure failure (engine crash, timeout, thrown attempt) folded
    /// into a receipt — the caller maps the failure to a `DispatchReceipt` with
    /// a reason. Frees the engine exactly like `workerFinished`.
    case workerFailed(WorkerId, DispatchReceipt)
    case receiptInjected(WorkerId)
}

/// The pure scheduler (D1): a queue over one serialized engine. One worker
/// generates at a time; `nextWorker` returns the next pending worker only when
/// the engine is free.
public enum PoolScheduler {
    /// The next free worker id (or nil when the pool is full). The caller
    /// peeks here before `.enqueue`, so it can answer "pool full" instead of
    /// overflowing the engine's fixed worker set.
    public static func availableWorker(_ state: PoolState) -> WorkerId? {
        state.freeIds.first
    }

    public static func apply(_ state: PoolState, _ command: PoolCommand) -> PoolState {
        var s = state
        switch command {
        case .enqueue(let packet):
            if let id = s.freeIds.first {
                s.freeIds.removeFirst()
                s.pending[id] = packet
            }
            // else: pool full — the caller must have checked availableWorker
        case .workerStarted(let id):
            s.pending[id] = nil
            s.running = id
        case .workerFinished(let id, let receipt), .workerFailed(let id, let receipt):
            s.running = nil
            s.completed[id] = receipt
            s.pendingDelivery[id] = receipt
            if !s.freeIds.contains(id) {
                s.freeIds.append(id)
                s.freeIds.sort()
            }
        case .receiptInjected(let id):
            s.pendingDelivery[id] = nil
        }
        return s
    }

    public static func canStart(_ state: PoolState) -> Bool {
        state.running == nil && !state.pending.isEmpty
    }

    /// The next worker to run, in enqueue order (smallest id), when the engine
    /// is free. Returns nil when nothing is pending or the engine is busy.
    public static func nextWorker(_ state: PoolState) -> (WorkerId, HandoffPacket)? {
        guard state.running == nil,
              let entry = state.pending.min(by: { $0.key < $1.key }) else { return nil }
        return (entry.key, entry.value)
    }
}
