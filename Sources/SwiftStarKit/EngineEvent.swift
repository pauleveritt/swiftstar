import Foundation

public struct EngineTool: Equatable, Sendable {
    public let op: String
    public let path: String?

    public init(op: String, path: String?) {
        self.op = op
        self.path = path
    }
}

public struct EngineToolResult: Equatable, Sendable {
    public let tool: EngineTool
    public let preview: String
    public let truncated: Bool

    public init(tool: EngineTool, preview: String, truncated: Bool) {
        self.tool = tool
        self.preview = preview
        self.truncated = truncated
    }
}

public struct EngineAnswer: Equatable, Sendable {
    public let text: String
    public let contextUsed: Int?
    public let contextSize: Int?
    public let durationMs: Double?
    /// Why the engine gave no text (only `laguna-xs-chat` reports one).
    public let reason: String?

    public init(text: String, contextUsed: Int?, contextSize: Int?, durationMs: Double?, reason: String? = nil) {
        self.reason = reason
        self.text = text
        self.contextUsed = contextUsed
        self.contextSize = contextSize
        self.durationMs = durationMs
    }
}

/// Per-pause measurements from a `checkpoint` snapshot; every field but
/// `evalCount` may be absent (the engine's snapshots are partial).
public struct PauseMetrics: Equatable, Sendable {
    public let prefillTokens: Int?
    public let prefillMs: Double?
    public let evalCount: Int
    public let evalMs: Double?

    public init(prefillTokens: Int?, prefillMs: Double?, evalCount: Int, evalMs: Double?) {
        self.prefillTokens = prefillTokens
        self.prefillMs = prefillMs
        self.evalCount = evalCount
        self.evalMs = evalMs
    }
}

public struct EngineMemory: Equatable, Sendable {
    public let allocatedBytes: Int64?
    public let budgetBytes: Int64?
    public let planGiB: Double?

    public init(allocatedBytes: Int64?, budgetBytes: Int64?, planGiB: Double?) {
        self.allocatedBytes = allocatedBytes
        self.budgetBytes = budgetBytes
        self.planGiB = planGiB
    }
}

public struct EngineSessionInfo: Equatable, Sendable {
    public let id: String
    public let modelID: String?
    public let contextSize: Int?

    public init(id: String, modelID: String?, contextSize: Int?) {
        self.id = id
        self.modelID = modelID
        self.contextSize = contextSize
    }
}

public enum EngineEvent: Equatable, Sendable {
    case ready
    case loading(String)
    case session(EngineSessionInfo)
    case generating(Bool)
    case prompt(String)
    case narration(String)
    case thinking(String)
    case toolStart(EngineTool)
    case toolEnd(EngineTool, ok: Bool, durationMs: Double?)
    case toolResult(EngineToolResult)
    case answer(EngineAnswer)
    case pause(PauseMetrics)
    case memory(EngineMemory)
    /// Stop took effect; carries the context after the interrupt.
    case interrupted(contextUsed: Int?, contextSize: Int?)
    /// The engine ended the session's turn (`terminal`): followed by `close`.
    case turnEnded(outcome: String)
    /// A prompt was queued behind the running turn (`count` now pending).
    case queued(count: Int)
    /// A queued message was (not) confirmed delivered after a tool resume.
    case steering(applied: Bool, text: String?)
    case notice(String)
    case refused(String)
    case awaitingInput
    case error(String)
    case closed(capturePath: String?)
    case protocolError(String)
    case ignored
}
