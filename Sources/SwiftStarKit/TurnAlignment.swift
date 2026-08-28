import Foundation

/// One turn of the session: its statuses plus the `TurnOutcome` that closed it
/// (nil when the turn produced none — the phantom startup prefill, a turn that
/// never reached a `ready`, or a still-open in-progress turn).
public struct AlignedTurn: Equatable, Sendable {
    public let statuses: [StatusSnapshot]
    public let outcome: TurnOutcome?
}

/// Segments the wire's statuses into turns and pairs each with the outcome
/// that actually produced it (P21 `swiftstar-analyze summary`).
///
/// The app writes a `TurnOutcome` only when a `ready` event that carries turn
/// data (`stop_reason`/`generated`/`ctx_used`) closes a turn the user started;
/// the engine's startup system-prompt prefill ends in a field-less `ready` and
/// writes none (AgentController: the outcome builder is nil at startup, so the
/// startup ready is a no-op). Indexing outcomes by plain turn number therefore
/// misattributes outcome[0] to the phantom startup turn — observed on
/// `captures/live/20260827-200648`, where `summary` reported the prefill turn
/// as "ctx 13728 tools 62" and "tools 0" for the turn that actually made 62
/// calls. The rule here: **outcome k pairs with the k-th turn whose terminal
/// `ready` carries data**, which also survives a turn that ends without any
/// `ready` (the app itself records no outcome for it either).
public enum TurnAlignment {
    public static func align(events: [WireEvent], outcomes: [TurnOutcome]) -> [AlignedTurn] {
        // Pass 1: segment statuses into turns (idle ends a turn and is
        // appended as its LAST status — the settled ctx) and mark each turn
        // whose terminal ready carries turn data. A ready arriving while a
        // turn is open belongs to it; a ready arriving right after a closing
        // idle belongs to the just-closed turn (the observed startup shape) —
        // but never unsets a real turn's mark (a real turn's ready precedes its
        // idle).
        struct Turn {
            var statuses: [StatusSnapshot] = []
            var readyCarriesData = false
        }
        var turns: [Turn] = []
        var current = Turn()
        var lastClosedIndex: Int?

        for event in events {
            switch event {
            case .status(let s):
                if s.state == "idle" {
                    if !current.statuses.isEmpty {
                        // The closing idle settles the turn's context (compaction
                        // lands at idle), so it must be the turn's LAST status —
                        // otherwise `cmdSummary`'s outcome-less fallback reads the
                        // pre-settle ctx (observed: idle differs from the preceding
                        // status in 4 places on captures/live/20260827-200648).
                        current.statuses.append(s)
                        turns.append(current)
                        lastClosedIndex = turns.count - 1
                        current = Turn()
                    }
                } else {
                    current.statuses.append(s)
                }
            case .ready(_, let stopReason, let generated, let ctxUsed):
                let carriesData = stopReason != nil || generated != nil || ctxUsed != nil
                if !current.statuses.isEmpty {
                    current.readyCarriesData = carriesData
                } else if let idx = lastClosedIndex, !turns[idx].readyCarriesData {
                    turns[idx].readyCarriesData = carriesData
                }
            case .hello, .ignored, .refused:
                break
            }
        }
        if !current.statuses.isEmpty { turns.append(current) }

        // Pass 2: hand each outcome to the next data-carrying turn, in order.
        var result: [AlignedTurn] = []
        var outcomeIndex = 0
        for turn in turns {
            let outcome: TurnOutcome?
            if turn.readyCarriesData, outcomeIndex < outcomes.count {
                outcome = outcomes[outcomeIndex]
                outcomeIndex += 1
            } else {
                outcome = nil
            }
            result.append(AlignedTurn(statuses: turn.statuses, outcome: outcome))
        }
        return result
    }
}
