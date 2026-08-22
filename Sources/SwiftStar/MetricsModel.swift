import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit

@MainActor
@Observable
final class MetricsModel {
    private(set) var state = MetricsState()
    private(set) var machine = MachineSnapshot(residentBytes: nil, watts: 0, gpuUtilization: 0, cpuUtilization: 0)
    private(set) var isReplayingWire = false

    private let collector = ProcessStatsCollector()
    private var collectTask: Task<Void, Never>?
    private var replayTask: Task<Void, Never>?
    private var enginePid: pid_t?

    func start(enginePid: pid_t?) {
        // Idempotent: the collector reads the latest pid each tick, and each
        // task is started at most once — calling start again (e.g. on pid
        // change) must not duplicate the timer or restart the replay.
        self.enginePid = enginePid
        if collectTask == nil {
            collectTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { break }
                    await self.tick()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        if replayTask == nil {
            replayTask = Task { [weak self] in
                guard let self else { return }
                self.isReplayingWire = true
                var parser = WireEventParser()
                let reducer = MetricsReducer()
                for await line in FixtureReplay.lines() {
                    if let event = parser.feed(line) {
                        reducer.reduce(&self.state, event)
                    }
                }
                self.isReplayingWire = false
            }
        }
    }

    func stop() {
        collectTask?.cancel()
        collectTask = nil
        replayTask?.cancel()
        replayTask = nil
        isReplayingWire = false
    }

    /// Live boot-line budget wins over the replayed ready-event budget: a
    /// recorded budget must never be paired with a live footprint on a
    /// different machine.
    var memoryBudgetPlannedBytes: Int64? {
        EngineController.lastKnownPlannedBytes ?? state.memoryBudgetPlannedBytes
    }

    private func tick() async {
        machine = await collector.collect(pid: enginePid)
    }
}
