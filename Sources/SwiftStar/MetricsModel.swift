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
        if collectTask == nil {
            collectTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { break }
                    await self.tick()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
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

    func stop() {
        controller?.onTelemetry = nil
        collectTask?.cancel()
        collectTask = nil
        replayTask?.cancel()
        replayTask = nil
    }

    /// The live memory budget (from the session's `ready`), when known.
    var memoryBudgetPlannedBytes: Int64? {
        state.memoryBudgetPlannedBytes
    }

    private func consume(_ event: AgentEvent) {
        switch event {
        case .status(let snapshot):
            provenance = .live
            reducer.reduce(&state, .status(snapshot))
        case .ready(let plannedBytes, _, _, _):
            provenance = .live
            reducer.reduce(&state, .ready(plannedBytes: plannedBytes))
        default:
            break
        }
    }

    private func tick() async {
        // Idle-aware: no agent pid → no IOKit reads, and the machine dials
        // blank honestly instead of holding a stale figure.
        guard let pid = controller?.runningPid else {
            machine = MachineSnapshot(residentBytes: nil, watts: 0, gpuUtilization: 0, cpuUtilization: 0)
            return
        }
        machine = await collector.collect(pid: pid)
    }
}
