import Testing
@testable import SwiftStarKit

/// P11 (D4) worker-turn bookkeeping (item 1 of the AgentController cleanup):
/// the id/packet/consult-membership shape that used to be three hand-synced
/// `AgentController` properties (`activeWorkerId`, `activeWorkerPacket`,
/// `consultWorkers`), now one pure, testable type.
struct WorkerTurnStateTests {
    private func packet(_ task: String) -> HandoffPacket {
        HandoffPacket(taskText: task, writableFiles: ["a.swift"], validationCommand: nil,
                      baselines: [:], turnBudget: 1000, toolCallBudget: 8)
    }

    @Test func freshStateHasNoActiveWorkerAndNoConsults() {
        let s = WorkerTurnState()
        #expect(s.active == nil)
        #expect(s.consultWorkers.isEmpty)
        #expect(s.isConsult(WorkerId(1)) == false)
    }

    @Test func startSetsActiveIdAndPacket() {
        var s = WorkerTurnState()
        s.start(id: WorkerId(1), packet: packet("one"))
        #expect(s.active?.id == WorkerId(1))
        #expect(s.active?.packet.taskText == "one")
    }

    @Test func clearActiveDropsTheActiveSlotOnly() {
        var s = WorkerTurnState()
        s.start(id: WorkerId(1), packet: packet("one"))
        s.markConsult(WorkerId(1))
        s.clearActive()
        #expect(s.active == nil)
        // Consult membership survives clearing the active slot — it is
        // explicitly removed per-worker (finishWorkerTurn/failActiveWorker),
        // not implicitly by ending a turn.
        #expect(s.isConsult(WorkerId(1)))
    }

    @Test func markAndRemoveConsultTracksMembershipIndependently() {
        var s = WorkerTurnState()
        s.markConsult(WorkerId(1))
        s.markConsult(WorkerId(2))
        #expect(s.isConsult(WorkerId(1)))
        #expect(s.isConsult(WorkerId(2)))
        s.removeConsult(WorkerId(1))
        #expect(s.isConsult(WorkerId(1)) == false)
        #expect(s.isConsult(WorkerId(2)))
    }

    @Test func multipleConsultsCanBeMarkedWhileOnlyOneIsActive() {
        // A larger subagent pool can queue more than one consult worker while
        // only one runs at a time (PoolScheduler serializes `active`); consult
        // membership must not be limited to whichever worker is active.
        var s = WorkerTurnState()
        s.markConsult(WorkerId(1))
        s.markConsult(WorkerId(2))
        s.start(id: WorkerId(1), packet: packet("one"))
        #expect(s.active?.id == WorkerId(1))
        #expect(s.isConsult(WorkerId(1)))
        #expect(s.isConsult(WorkerId(2)))
    }

    @Test func resetClearsEverything() {
        var s = WorkerTurnState()
        s.start(id: WorkerId(1), packet: packet("one"))
        s.markConsult(WorkerId(1))
        s.markConsult(WorkerId(2))
        s = WorkerTurnState()
        #expect(s.active == nil)
        #expect(s.consultWorkers.isEmpty)
    }
}
