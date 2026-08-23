import Foundation

/// The outcome-telemetry vocabulary for one tool call (D12, roadmap 0ee5f6c):
/// emitted (announced on the wire), parsed (its block closed cleanly),
/// rejected (the block closed with a status — invalid, interrupted, or
/// failed; the vocabulary has no finer case), executed (dispatch ran; bash
/// additionally shows it via `output`).
public enum ToolLifecycle: String, Equatable, Sendable, CaseIterable {
    case emitted, parsed, rejected, executed
}

public struct ToolCallOutcome: Equatable, Sendable {
    public let name: String
    public let transitions: [ToolLifecycle]
}

/// Why a turn ended. `timeout` is app-side by definition — the app's own turn
/// budget — and exists so the record's vocabulary is complete; P7's controller
/// imposes no timeout policy (D12).
public enum TurnStopReason: String, Equatable, Sendable, CaseIterable {
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
public struct TurnOutcome: Equatable, Sendable {
    public let model: String
    public let build: String
    public let sampler: String
    public let task: String
    public let generatedTokens: Int
    public let ctxUsed: Int
    public let stopReason: TurnStopReason
    public let toolCalls: [ToolCallOutcome]

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
        return "turn model=\(model) build=\(build) sampler=\(sampler) tokens=\(generatedTokens) ctx=\(ctxUsed) stop=\(stopReason.rawValue) tools=[\(tools)] task=\(task.prefix(80))"
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
    private var wireStopReason: TurnStopReason?
    private var generated = 0
    private var ctxUsed = 0

    public init(model: String, build: String, sampler: String, task: String) {
        self.model = model
        self.build = build
        self.sampler = sampler
        self.task = task
    }

    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case .tool(let te):
            applyTool(te)
        case .ready(_, let stopReason, let generated, let ctxUsed):
            if let stopReason { wireStopReason = TurnStopReason(rawValue: stopReason) }
            if let generated { self.generated = generated }
            if let ctxUsed { self.ctxUsed = ctxUsed }
        case .hello, .status, .queued, .text, .think, .ignored, .refused:
            break
        }
    }

    /// The app override (interrupt/timeout — the app knows what it did) beats
    /// the wire's reason; a wire predating the D12 fields ends turns with no
    /// reason, so a turn that simply ended defaults to `.eos`.
    public func finish(appStopReason: TurnStopReason? = nil) -> TurnOutcome {
        var all = completed
        for idx in order {
            if let c = calls[idx] {
                all.append(ToolCallOutcome(name: c.name, transitions: c.transitions))
            }
        }
        return TurnOutcome(
            model: model, build: build, sampler: sampler, task: task,
            generatedTokens: generated, ctxUsed: ctxUsed,
            stopReason: appStopReason ?? wireStopReason ?? .eos,
            toolCalls: all
        )
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
