import Foundation

/// One phase's telemetry, derived from the captured wire by `AgentTestAnalyzer`.
public struct AgentTestPhaseReport: Equatable, Sendable {
    public let worker: WorkerId
    public let toolCalls: Int            // total tool_requests
    public let rounds: Int               // tool_request groups (a round = a run of consecutive requests)
    public let toolDistribution: [String: Int]
    public let repeatedIdenticalCalls: Int  // consecutive requests with identical name+params
    public let reReads: Int              // distinct files read more than once
    public let generatedTokens: Int
    public let ctxAtEnd: Int
}

/// The whole-run report (D5): the phase reports plus the aggregates.
public struct AgentTestReport: Equatable, Sendable {
    public let phases: [AgentTestPhaseReport]
    public var totalToolCalls: Int { phases.reduce(0) { $0 + $1.toolCalls } }
    public var totalRepeatedIdenticalCalls: Int { phases.reduce(0) { $0 + $1.repeatedIdenticalCalls } }
    public var totalReReads: Int { phases.reduce(0) { $0 + $1.reReads } }

    public func summary() -> String {
        var lines = ["agenttest report: \(phases.count) phase(s), \(totalToolCalls) tool calls, \(totalRepeatedIdenticalCalls) repeated-identical, \(totalReReads) re-reads"]
        for (i, p) in phases.enumerated() {
            let dist = p.toolDistribution.sorted { $0.value > $1.value }
                .map { "\($0.key):\($0.value)" }.joined(separator: ",")
            lines.append("  phase \(i + 1) (worker \(p.worker.rawValue)): \(p.toolCalls) calls / \(p.rounds) rounds, \(p.repeatedIdenticalCalls) repeated, \(p.reReads) re-reads, ctx=\(p.ctxAtEnd) gen=\(p.generatedTokens) [\(dist)]")
        }
        return lines.joined(separator: "\n")
    }
}

/// The deterministic telemetry analyzer (P11 addendum D5): re-derives the
/// metrics from the captured wire, so the analysis is repeatable and testable
/// rather than ad-hoc. Pure — no Process, no IO beyond its input.
public enum AgentTestAnalyzer {
    public static func analyze(events: [PoolWireEvent]) -> AgentTestReport {
        var phases: [AgentTestPhaseReport] = []
        var cur = Accumulator()
        var curWorker: WorkerId = .orchestrator
        var inPhase = false

        func flush() {
            guard inPhase else { return }
            phases.append(cur.finish(worker: curWorker))
            cur = Accumulator()
            inPhase = false
        }

        for ev in events {
            guard ev.worker != .orchestrator else { continue }
            inPhase = true
            curWorker = ev.worker
            cur.apply(ev.event)
            if case .ready(_, let stop, _, _) = ev.event, stop != nil {
                flush()  // the worker's turn-end ready closes the phase
            }
        }
        return AgentTestReport(phases: phases)
    }

    private struct Accumulator {
        var toolCalls = 0
        var rounds = 0
        var inRound = false
        var distribution: [String: Int] = [:]
        var repeated = 0
        var lastCall: (name: String, params: String)?
        var readCounts: [String: Int] = [:]
        var generatedTokens = 0
        var ctxAtEnd = 0

        mutating func apply(_ event: AgentEvent) {
            switch event {
            case .toolRequest(_, let name, let params):
                toolCalls += 1
                if !inRound { rounds += 1; inRound = true }
                distribution[name, default: 0] += 1
                let key = params.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
                if let last = lastCall, last.name == name, last.params == key {
                    repeated += 1
                }
                lastCall = (name, key)
                if name == "read", let path = params.first(where: { $0.name == "path" })?.value {
                    readCounts[path, default: 0] += 1
                }
            case .text, .think:
                inRound = false       // prose ends the current round
                lastCall = nil        // …and a call after prose is not "consecutive"
            case .ready(_, _, let generated, let ctx):
                if let generated { generatedTokens = generated }
                if let ctx { ctxAtEnd = ctx }
            default:
                break
            }
        }

        func finish(worker: WorkerId) -> AgentTestPhaseReport {
            let reReads = readCounts.values.filter { $0 > 1 }.count
            return AgentTestPhaseReport(
                worker: worker,
                toolCalls: toolCalls, rounds: rounds, toolDistribution: distribution,
                repeatedIdenticalCalls: repeated, reReads: reReads,
                generatedTokens: generatedTokens, ctxAtEnd: ctxAtEnd)
        }
    }
}
