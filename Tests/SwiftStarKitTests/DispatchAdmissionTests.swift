import Testing
@testable import SwiftStarKit

struct DispatchAdmissionTests {
    // The 2026-08-30 font session's dead letter: the model dispatched a
    // read-only "build and test" verification with empty writableFiles, the
    // builder refused it (returns nil), and the controller recorded no host
    // verdict — so the outcome showed the dispatch as "emitted" only. The
    // decision must refuse that shape with a reason that names writableFiles
    // so the model can self-correct (supply files, or do the read-only work
    // itself).
    @Test func refusesReadOnlyDispatchWithoutWritableFiles() {
        let params = [ToolParam(name: "taskText", value: "Build and test"),
                      ToolParam(name: "writableFiles", value: ""),
                      ToolParam(name: "validationCommand", value: "swift build")]
        let decision = DispatchAdmission.decide(
            params: params, digest: RollingDigest(), loaded: [:], implementer: "laguna",
            poolState: PoolState(workerCapacity: 2), dumb: false)
        guard case .refused(let reason) = decision else {
            Issue.record("expected refusal, got \(decision)")
            return
        }
        #expect(reason.contains("writableFiles"))
    }

    @Test func refusesWithoutTaskText() {
        let params = [ToolParam(name: "writableFiles", value: "a.swift")]
        let decision = DispatchAdmission.decide(
            params: params, digest: RollingDigest(), loaded: [:], implementer: "laguna",
            poolState: PoolState(workerCapacity: 2), dumb: false)
        guard case .refused(let reason) = decision else {
            Issue.record("expected refusal, got \(decision)")
            return
        }
        #expect(reason.contains("taskText"))
    }

    @Test func refusesInDumbMode() {
        let params = [ToolParam(name: "taskText", value: "fix a.swift"),
                      ToolParam(name: "writableFiles", value: "a.swift")]
        let decision = DispatchAdmission.decide(
            params: params, digest: RollingDigest(), loaded: [:], implementer: "laguna",
            poolState: PoolState(workerCapacity: 2), dumb: true)
        guard case .refused(let reason) = decision else {
            Issue.record("expected refusal, got \(decision)")
            return
        }
        #expect(reason.contains("dumb mode"))
    }

    @Test func refusesWhenPoolIsFull() {
        var pool = PoolState(workerCapacity: 1)
        if let packet = DispatchPacketBuilder.build(
            params: [ToolParam(name: "taskText", value: "x"),
                     ToolParam(name: "writableFiles", value: "a.swift")],
            digest: RollingDigest(), loaded: [:], implementer: "laguna") {
            pool = PoolScheduler.apply(pool, .enqueue(packet: packet))
        }
        let params = [ToolParam(name: "taskText", value: "fix b.swift"),
                      ToolParam(name: "writableFiles", value: "b.swift")]
        let decision = DispatchAdmission.decide(
            params: params, digest: RollingDigest(), loaded: [:], implementer: "laguna",
            poolState: pool, dumb: false)
        guard case .refused(let reason) = decision else {
            Issue.record("expected refusal, got \(decision)")
            return
        }
        #expect(reason.contains("pool is full"))
    }

    @Test func enqueuesWhenWellFormed() {
        let params = [ToolParam(name: "taskText", value: "fix a.swift"),
                      ToolParam(name: "writableFiles", value: "a.swift, b.swift")]
        let decision = DispatchAdmission.decide(
            params: params, digest: RollingDigest(), loaded: [:], implementer: "laguna",
            poolState: PoolState(workerCapacity: 2), dumb: false)
        guard case .enqueue(let packet, let worker) = decision else {
            Issue.record("expected enqueue, got \(decision)")
            return
        }
        #expect(packet.writableFiles == ["a.swift", "b.swift"])
        #expect(worker == WorkerId(1))
    }
}

/// The dead letter itself: not "did the gate refuse?" but "did the refusal
/// become visible?". The 2026-08-30 bug was a correct refusal whose outcome
/// stayed at `.emitted`, so the model saw a tool call that neither ran nor was
/// rejected. These pin the verdict, which is the part that was missing —
/// `DispatchAdmissionTests`' reason assertions all passed while the bug was live.
struct DispatchVerdictTests {
    private static func builderWithPendingDispatch() -> TurnOutcomeBuilder? {
        var b: TurnOutcomeBuilder? = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b?.apply(.toolRequest(idx: 7, name: "dispatch", params: []))
        return b
    }

    @Test func refusedDispatchIsRecordedAsRejected() {
        var builder = Self.builderWithPendingDispatch()
        let response = DispatchAdmission.apply(
            .refused("dispatch is malformed"), idx: 7, into: &builder)
        #expect(response.ok == false)
        #expect(response.s.contains("refused"))
        #expect(builder?.finish().toolCalls == [
            ToolCallOutcome(name: "dispatch", transitions: [.emitted, .rejected]),
        ])
    }

    @Test func enqueuedDispatchIsRecordedAsExecuted() {
        var builder = Self.builderWithPendingDispatch()
        guard case .enqueue(let packet, let worker) = DispatchAdmission.decide(
            params: [ToolParam(name: "taskText", value: "fix a.swift"),
                     ToolParam(name: "writableFiles", value: "a.swift")],
            digest: RollingDigest(), loaded: [:], implementer: "laguna",
            poolState: PoolState(workerCapacity: 2), dumb: false) else {
            Issue.record("expected enqueue"); return
        }
        let response = DispatchAdmission.apply(
            .enqueue(packet: packet, worker: worker), idx: 7, into: &builder)
        #expect(response.ok == true)
        #expect(response.s == "dispatched as worker 1")
        #expect(builder?.finish().toolCalls == [
            ToolCallOutcome(name: "dispatch", transitions: [.emitted, .executed]),
        ])
    }

    @Test func aNilBuilderIsToleratedTheWayTheControllersOptionalWas() {
        // The controller's `outcomeBuilder` is nil outside a turn; composing a
        // response must still work rather than trap.
        var builder: TurnOutcomeBuilder?
        let response = DispatchAdmission.apply(
            .refused("subagent pool is full"), idx: 3, into: &builder)
        #expect(response.ok == false)
        #expect(builder == nil)
    }
}
