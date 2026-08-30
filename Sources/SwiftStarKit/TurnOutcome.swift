import Foundation

/// The outcome-telemetry vocabulary for one tool call (D12, roadmap 0ee5f6c):
/// emitted (announced on the wire), parsed (its block closed cleanly),
/// rejected (the block closed with a status — invalid, interrupted, or
/// failed; the vocabulary has no finer case), executed (dispatch ran; bash
/// additionally shows it via `output`).
public enum ToolLifecycle: String, Equatable, Sendable, CaseIterable, Codable {
    case emitted, parsed, rejected, executed
}

public struct ToolCallOutcome: Equatable, Sendable, Codable {
    public let name: String
    public let transitions: [ToolLifecycle]
}

/// Why a turn ended. `timeout` is app-side by definition — the app's own turn
/// budget — and exists so the record's vocabulary is complete; P7's controller
/// imposes no timeout policy (D12).
public enum TurnStopReason: String, Equatable, Sendable, CaseIterable, Codable {
    case eos
    case limit
    case interrupt
    case timeout
    case contextFull = "context_full"
}

/// One turn's capture-grade outcome record (D12): the spawn-time
/// identification the wire cannot carry (model/build/sampler), the task text,
/// final token/context figures, the stop reason, and every tool call's
/// lifecycle. P10's handoff packets consume these facts rather than inferring
/// success from the transcript.
public struct TurnOutcome: Equatable, Sendable, Codable {
    public let model: String
    public let build: String
    /// The per-turn think decision actually used (P23):
    /// `think=default|none|high|max|refused`. Was a hardcoded
    /// `"engine-defaults"` until the app could send per-turn overrides.
    public let sampler: String
    public let task: String
    public let generatedTokens: Int
    public let ctxUsed: Int
    public let stopReason: TurnStopReason
    public let toolCalls: [ToolCallOutcome]
    /// P9 host-authoritative facts (D5): the actual mutation paths, the command
    /// exit status, an output digest, and whether validation ran. The wire
    /// cannot carry these (the host learns them by executing), so they default
    /// empty/nil/nil/false and the app sets them on the finished record. They
    /// are `var` for that reason; the wire-derived fields above stay `let`.
    public var mutations: [String] = []
    public var text: String = ""
    public var exitStatus: Int? = nil
    public var outputDigest: String? = nil
    public var validationRan: Bool = false
    /// The turn-closing `ready`'s own token count — the FINAL generation
    /// segment only, which is what the engine reports (it resets the counter at
    /// every prefill). `generatedTokens` above is the turn's total across all
    /// segments. Optional because records written before this field existed
    /// carry only the wire value, in `generatedTokens`, where it means this.
    public var finalSegmentTokens: Int? = nil

    public init(model: String, build: String, sampler: String, task: String,
                generatedTokens: Int, ctxUsed: Int, stopReason: TurnStopReason,
                toolCalls: [ToolCallOutcome]) {
        self.model = model
        self.build = build
        self.sampler = sampler
        self.task = task
        self.generatedTokens = generatedTokens
        self.ctxUsed = ctxUsed
        self.stopReason = stopReason
        self.toolCalls = toolCalls
    }
}

extension TurnOutcome: CustomStringConvertible {
    /// One compact line for the SWIFTSTAR_LOG trail.
    public var description: String {
        let tools = toolCalls.map { "\($0.name)[\($0.transitions.map(\.rawValue).joined(separator: "+"))]" }
            .joined(separator: " ")
        var s = "turn model=\(model) build=\(build) sampler=\(sampler) tokens=\(generatedTokens) ctx=\(ctxUsed) stop=\(stopReason.rawValue) tools=[\(tools)]"
        if !mutations.isEmpty { s += " mutations=\(mutations.joined(separator: ","))" }
        if let exitStatus { s += " exit=\(exitStatus)" }
        if let outputDigest { s += " digest=\(outputDigest)" }
        if validationRan { s += " validated=true" }
        s += " task=\(task.prefix(80))"
        return s
    }
}

/// Builds one `TurnOutcome` from a turn's wire events plus the app-known facts
/// the wire cannot carry (D12). Pure; the controller opens one builder per
/// turn and finishes it at the turn end. Tool state is keyed by `idx` within
/// the current block (the same idx contract as `AgentTranscript`); a block's
/// `finish` closes every call in it, and completed blocks accumulate within
/// the turn.
public struct TurnOutcomeBuilder {
    private let model: String
    private let build: String
    private let sampler: String
    private let task: String
    private var calls: [Int: (name: String, transitions: [ToolLifecycle])] = [:]
    private var order: [Int] = []
    private var completed: [ToolCallOutcome] = []
    /// P9 host mode (D5): the wire carries `.toolRequest` (not `.tool` phases);
    /// the builder records each request as `emitted` and the host's verdict as
    /// `executed` (ok) or `rejected` (refused), in arrival order. `idx` is
    /// scoped to the current block and repeats across blocks, so host calls are
    /// keyed by arrival order (this array), not by idx.
    private var hostCalls: [(name: String, transitions: [ToolLifecycle])] = []
    /// P9 host-authoritative facts (D5), accumulated from `recordHostVerdict`.
    private var mutations: [String] = []
    private var text = ""
    private var exitStatus: Int?
    private var outputDigest: String?
    private var validationRan = false
    /// The turn's decode work per generation segment. The engine resets its
    /// `generated` counter at every prefill, so the turn-closing `ready`
    /// reports only the final segment — `DecodeAccumulator` is the arithmetic
    /// that turns the status stream back into a turn total. A builder that is
    /// never fed statuses falls back to the wire value (see `finish`).
    private var decode = DecodeAccumulator()
    private var sawStatus = false
    private var wireStopReason: TurnStopReason?
    private var generated = 0
    private var ctxUsed = 0

    /// P23: the builder derives the sampler record from the effort actually
    /// used. nil = engine default (`"think=default"`); the hardcoded
    /// `"engine-defaults"` literal is retired — it was false the moment the
    /// app started sending per-turn overrides.
    public init(model: String, build: String, task: String, think: ThinkEffort? = nil) {
        self.model = model
        self.build = build
        self.task = task
        self.sampler = TurnThinkPolicy.samplerRecord(
            think.map { TurnThinkDecision.override($0) } ?? .useDefault)
    }

    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case .tool(let te):
            applyTool(te)
        case .ready(_, let stopReason, let generated, let ctxUsed):
            if let stopReason { wireStopReason = TurnStopReason(rawValue: stopReason) }
            if let generated { self.generated = generated }
            if let ctxUsed { self.ctxUsed = ctxUsed }
        case .toolRequest(let idx, let name, _):
            // P9 host mode (D5): the request is the emission. `idx` is scoped to
            // the current block and repeats across blocks, so the builder keys
            // host calls by arrival order (the `hostCalls` array), not by idx.
            _ = idx  // traced on the wire; not the key here
            hostCalls.append((name: name, transitions: [.emitted]))
        case .text(let s):
            text += s
        case .status(let snapshot):
            decode.apply(snapshot)
            sawStatus = true
        case .hello, .queued, .think, .ignored, .refused, .toolRequestRefused:
            break
        }
    }

    /// P9 host mode (D5): record the host's verdict on the most recent
    /// `.toolRequest`. The protocol is strictly request→result (the engine
    /// blocks per request), so the last un-verdicted host call is the current
    /// one. `ok` → `executed` (the host ran it); `!ok` → `rejected` (the host
    /// refused or the executor failed). The host-authoritative facts
    /// (mutations/exitStatus/outputDigest/validationRan) accumulate onto the
    /// finished record. `idx` is the request's wire idx (kept for symmetry);
    /// it is NOT the key — it repeats across blocks.
    public mutating func recordHostVerdict(idx: Int, ok: Bool,
                                           mutations: [String], exitStatus: Int?,
                                           outputDigest: String?, validationRan: Bool) {
        _ = idx
        if let last = hostCalls.indices.last,
           !hostCalls[last].transitions.contains(.executed),
           !hostCalls[last].transitions.contains(.rejected) {
            var c = hostCalls[last]
            c.transitions.append(ok ? .executed : .rejected)
            hostCalls[last] = c
        }
        self.mutations.append(contentsOf: mutations)
        if let exitStatus { self.exitStatus = exitStatus }
        if let outputDigest { self.outputDigest = outputDigest }
        if validationRan { self.validationRan = validationRan }
    }

    /// The app override (interrupt/timeout — the app knows what it did) beats
    /// the wire's reason; a wire predating the D12 fields ends turns with no
    /// reason, so a turn that simply ended defaults to `.eos`.
    public func finish(appStopReason: TurnStopReason? = nil) -> TurnOutcome {
        // In host-tools mode the wire carries BOTH the `.tool` transcript phases
        // and the `.toolRequest` execution events for the SAME calls. Count them
        // once: the host-tools requests are the authoritative view (they carry
        // the host's verdict), so prefer them and ignore the transcript view.
        let all: [ToolCallOutcome]
        if !hostCalls.isEmpty {
            all = hostCalls.map { ToolCallOutcome(name: $0.name, transitions: $0.transitions) }
        } else {
            var fromTranscript = completed
            for idx in order {
                if let c = calls[idx] {
                    fromTranscript.append(ToolCallOutcome(name: c.name, transitions: c.transitions))
                }
            }
            all = fromTranscript
        }
        // The turn's total, not the wire's last segment. `ready` supersedes the
        // final segment's last status sample (samples are periodic and miss
        // whatever followed), which is exactly what `finish` is for.
        //
        // Fall back to the wire value when no status carried usable decode work:
        // a builder fed no status stream at all, or one whose samples all
        // reported a zero/garbage rate. Reporting the accumulator's 0 over the
        // wire's own count would trade an undercount for a total loss.
        var acc = decode
        acc.finish(finalGenerated: generated)
        let turnTokens = (sawStatus && acc.generatedTokens > 0) ? acc.generatedTokens : generated
        var outcome = TurnOutcome(
            model: model, build: build, sampler: sampler, task: task,
            generatedTokens: turnTokens, ctxUsed: ctxUsed,
            stopReason: appStopReason ?? wireStopReason ?? .eos,
            toolCalls: all
        )
        outcome.mutations = self.mutations
        outcome.exitStatus = self.exitStatus
        outcome.outputDigest = self.outputDigest
        outcome.validationRan = self.validationRan
        outcome.text = self.text
        outcome.finalSegmentTokens = generated
        return outcome
    }

    private mutating func applyTool(_ te: AgentToolEvent) {
        switch te.phase {
        case .start:
            flushBlock()
        case .tool:
            calls[te.idx] = (name: te.name ?? "", transitions: [.emitted])
            order.append(te.idx)
        case .paramBegin, .paramValue, .paramEnd:
            break  // the lifecycle vocabulary has no finer granularity
        case .output:
            if var c = calls[te.idx], !c.transitions.contains(.executed) {
                c.transitions.append(.executed)
                calls[te.idx] = c
            }
        case .finish:
            // One finish per block: it closes every call in it. A clean
            // finish (no status) means the calls parsed and — dispatch being
            // synchronous — executed; a status means the block closed badly,
            // which the vocabulary records as rejected.
            for idx in order {
                guard var c = calls[idx] else { continue }
                if te.status == nil {
                    if !c.transitions.contains(.parsed) { c.transitions.append(.parsed) }
                    if !c.transitions.contains(.executed) { c.transitions.append(.executed) }
                } else if !c.transitions.contains(.rejected) {
                    c.transitions.append(.rejected)
                }
                calls[idx] = c
            }
        }
    }

    private mutating func flushBlock() {
        for idx in order {
            if let c = calls[idx] {
                completed.append(ToolCallOutcome(name: c.name, transitions: c.transitions))
            }
        }
        calls = [:]
        order = []
    }
}
