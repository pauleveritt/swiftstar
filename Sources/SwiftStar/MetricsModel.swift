import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit

/// Where the lead dials' values come from. `.recorded` is the pre-spawn
/// placeholder (the bundled capture); `.live` once the wire's status/ready
/// events flow (P21: Metrics is fed from the live wire, not the fixture).
enum Provenance {
    case recorded
    case live
}

@MainActor
@Observable
final class MetricsModel {
    private(set) var state = MetricsState()
    private(set) var machine = MachineSnapshot(residentBytes: nil, watts: 0, gpuUtilization: 0, cpuUtilization: 0)
    private(set) var provenance: Provenance = .recorded
    /// True only while the machine dials hold a real sample (an agent pid was
    /// alive at the last tick). False = no measurement, not a measured zero.
    private(set) var sampling = false

    private let collector = ProcessStatsCollector()
    private var reducer = MetricsReducer()
    private var collectTask: Task<Void, Never>?
    private var replayTask: Task<Void, Never>?
    private weak var controller: AgentController?

    /// Wire the live telemetry source and start the collectors. Idempotent:
    /// the machine-collector and placeholder-replay tasks start at most once;
    /// re-calling (e.g. on a pid change) just re-points the live observer.
    func start(controller: AgentController) {
        self.controller = controller
        controller.onTelemetry = { [weak self] event in
            self?.consume(event)
        }
        if replayTask == nil {
            // Pre-spawn placeholder only: the bundled capture, until a live
            // status/ready event flips provenance (then the replay stops).
            replayTask = Task { [weak self] in
                guard let self else { return }
                var parser = WireEventParser()
                for await line in FixtureReplay.lines() {
                    guard self.provenance != .live else { break }
                    if let event = parser.feed(line) {
                        self.reducer.reduce(&self.state, event)
                    }
                }
            }
        }
    }

    /// Machine sampling (memory/GPU/CPU/power) runs only while the Metrics
    /// surface is on screen. The 1 Hz IOKit + IOReport sampling is not free — a
    /// registry walk and a 100 ms power window per tick — and nothing else reads
    /// it: the bottom bar's memory ring has the controller's own poller. Before
    /// this it ran for the app's lifetime regardless of the visible section.
    func setCollecting(_ enabled: Bool) {
        guard enabled else {
            collectTask?.cancel()
            collectTask = nil
            sampling = false
            return
        }
        guard collectTask == nil else { return }
        collectTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.tick()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        controller?.onTelemetry = nil
        setCollecting(false)
        replayTask?.cancel()
        replayTask = nil
    }

    /// The live memory budget (from the session's `ready`), when it is safe to
    /// divide the live resident footprint by it: the plan must be this session's
    /// AND measured for the model now running. Without the model check a restart
    /// into a different model divides the new model's resident bytes by the old
    /// model's plan; without the `.live` check the placeholder capture's 46.5 GiB
    /// plan is the denominator for the whole model-load window. This is the
    /// guard the status bar already had (`AgentView`) and Metrics did not.
    var memoryBudgetPlannedBytes: Int64? {
        guard provenance == .live,
              let plannedModel,
              plannedModel == controller?.settings.modelPath.lastPathComponent else { return nil }
        return state.memoryBudgetPlannedBytes
    }

    /// The model `state.memoryBudgetPlannedBytes` was measured for.
    private var plannedModel: String?

    private func consume(_ event: AgentEvent) {
        switch event {
        case .status(let snapshot):
            goLive()
            reducer.reduce(&state, .status(snapshot))
        case .ready(let plannedBytes, _, _, _):
            goLive()
            // Only a plan-bearing ready re-anchors the denominator; a bare ready
            // (the engine omits the field when the memory plan fails) must not
            // blank a good budget, matching the controller's own guard.
            guard plannedBytes != nil else { break }
            plannedModel = controller?.settings.modelPath.lastPathComponent
            reducer.reduce(&state, .ready(plannedBytes: plannedBytes, stopReason: nil, generated: nil, ctxUsed: nil))
        default:
            break
        }
    }

    /// Cross from the placeholder to the session's own numbers. The reduced
    /// state MUST be cleared on that edge: the reducer deliberately ignores
    /// zero-valued fields (an incomplete status must not blank a dial), so
    /// without this the fixture's ctx/TPS survive the first all-zero idle status
    /// and keep rendering — now with the "capture replay" banner gone. Recorded
    /// values shown as live is the one thing this surface must never do.
    private func goLive() {
        guard provenance != .live else { return }
        state = MetricsState()
        provenance = .live
    }

    private func tick() async {
        // Idle-aware: no agent pid → no IOKit reads. `sampling` is what makes
        // that honest — the zeroed snapshot is an absence of measurement, and
        // the dials must render it as "—", not as a measured 0% / 0.0 W.
        guard let pid = controller?.runningPid else {
            machine = MachineSnapshot(residentBytes: nil, watts: 0, gpuUtilization: 0, cpuUtilization: 0)
            sampling = false
            return
        }
        machine = await collector.collect(pid: pid)
        sampling = true
    }
}
