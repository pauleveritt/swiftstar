import Testing
@testable import SwiftStarKit

struct PoolSchedulerTests {
    private func packet(_ task: String) -> HandoffPacket {
        HandoffPacket(taskText: task, writableFiles: ["a.swift"], validationCommand: nil,
                      baselines: [:], turnBudget: 1000, toolCallBudget: 8)
    }
    @Test func enqueueThenStartRunsOneAtATime() {
        var s = PoolState()
        s = PoolScheduler.apply(s, .enqueue(packet: packet("one")))
        s = PoolScheduler.apply(s, .enqueue(packet: packet("two")))
        let first = PoolScheduler.nextWorker(s)
        #expect(first?.1.taskText == "one")
        s = PoolScheduler.apply(s, .workerStarted(first!.0))
        #expect(s.running != nil)
        #expect(PoolScheduler.canStart(s) == false)   // serialized: one at a time
        #expect(s.pending.count == 1)
    }
    @Test func finishRecordsReceiptAndFreesTheEngine() {
        var s = PoolState()
        s = PoolScheduler.apply(s, .enqueue(packet: packet("one")))
        s = PoolScheduler.apply(s, .enqueue(packet: packet("two")))
        let first = PoolScheduler.nextWorker(s)!
        s = PoolScheduler.apply(s, .workerStarted(first.0))
        let receipt = DispatchReceipt(worker: first.0, ref: "ref", reason: nil, summary: "done")
        s = PoolScheduler.apply(s, .workerFinished(first.0, receipt))
        #expect(s.completed[first.0] == receipt)
        #expect(s.running == nil)
        #expect(PoolScheduler.canStart(s) == true)     // engine freed for the next worker
        #expect(PoolScheduler.nextWorker(s)?.1.taskText == "two")
    }
    @Test func refusalReceiptStillCompletes() {
        var s = PoolState()
        s = PoolScheduler.apply(s, .enqueue(packet: packet("one")))
        let w = PoolScheduler.nextWorker(s)!
        s = PoolScheduler.apply(s, .workerStarted(w.0))
        let receipt = DispatchReceipt(worker: w.0, ref: nil, reason: "noChanges", summary: "nothing")
        s = PoolScheduler.apply(s, .workerFinished(w.0, receipt))
        #expect(s.completed[w.0]?.reason == "noChanges")
    }
    @Test func workerFailureFreesTheEngineAsAReceipt() {
        var s = PoolState()
        s = PoolScheduler.apply(s, .enqueue(packet: packet("one")))
        s = PoolScheduler.apply(s, .enqueue(packet: packet("two")))
        let w = PoolScheduler.nextWorker(s)!
        s = PoolScheduler.apply(s, .workerStarted(w.0))
        let failure = DispatchReceipt(worker: w.0, ref: nil, reason: "engine crash", summary: "crashed")
        s = PoolScheduler.apply(s, .workerFailed(w.0, failure))
        #expect(s.completed[w.0]?.reason == "engine crash")
        #expect(s.running == nil)             // engine freed
        #expect(PoolScheduler.canStart(s))    // next worker can run
        #expect(PoolScheduler.nextWorker(s)?.1.taskText == "two")
    }
    @Test func receiptInjectedClearsPendingDelivery() {
        var s = PoolState()
        s = PoolScheduler.apply(s, .enqueue(packet: packet("one")))
        let w = PoolScheduler.nextWorker(s)!
        s = PoolScheduler.apply(s, .workerStarted(w.0))
        s = PoolScheduler.apply(s, .workerFinished(w.0, DispatchReceipt(worker: w.0, ref: "r", reason: nil, summary: "d")))
        s = PoolScheduler.apply(s, .receiptInjected(w.0))
        #expect(s.pendingDelivery.isEmpty)
    }
    @Test func workerIdsAreBoundedAndReused() {
        var s = PoolState(workerCapacity: 3)
        #expect(PoolScheduler.availableWorker(s) == WorkerId(1))
        s = PoolScheduler.apply(s, .enqueue(packet: packet("a")))
        #expect(PoolScheduler.availableWorker(s) == WorkerId(2))
        s = PoolScheduler.apply(s, .enqueue(packet: packet("b")))
        s = PoolScheduler.apply(s, .enqueue(packet: packet("c")))
        #expect(PoolScheduler.availableWorker(s) == nil)   // pool full
        // Finish worker 1; its id returns to the free list.
        let w1 = PoolScheduler.nextWorker(s)!
        #expect(w1.0 == WorkerId(1))
        s = PoolScheduler.apply(s, .workerStarted(w1.0))
        s = PoolScheduler.apply(s, .workerFinished(w1.0, DispatchReceipt(worker: w1.0, ref: "r", reason: nil, summary: "d")))
        #expect(PoolScheduler.availableWorker(s) == WorkerId(1))  // reused, never grows past 3
    }
}
