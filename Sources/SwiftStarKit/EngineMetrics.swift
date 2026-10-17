import Foundation

public struct EngineMetricsState: Equatable, Sendable {
    public var prefillTPS: Double?
    public var generationTPS: Double?
    public var contextUsed: Int?
    public var contextSize: Int?
    public var gpuAllocatedBytes: Int64?
    public var gpuBudgetBytes: Int64?
    public var planGiB: Double?
    /// This process's prefix-cache outcome; a hit is left out of the prefill
    /// rate, since the engine counts its tokens as prefilled (SU.6b, D3).
    public var prefixCache: EnginePrefixCache?
    /// This process's start-up reports (EN.2).
    public var startup = EngineStartupInfo()
    /// A resumed conversation's saved-state load (EN.2).
    public var conversationState: EngineConversationState?

    public init(prefillTPS: Double? = nil, generationTPS: Double? = nil,
                contextUsed: Int? = nil, contextSize: Int? = nil,
                gpuAllocatedBytes: Int64? = nil, gpuBudgetBytes: Int64? = nil,
                planGiB: Double? = nil) {
        self.prefillTPS = prefillTPS
        self.generationTPS = generationTPS
        self.contextUsed = contextUsed
        self.contextSize = contextSize
        self.gpuAllocatedBytes = gpuAllocatedBytes
        self.gpuBudgetBytes = gpuBudgetBytes
        self.planGiB = planGiB
    }
}

public enum EngineMetricsReducer {
    public static func reduce(_ state: inout EngineMetricsState, _ event: EngineEvent) {
        switch event {
        case .pause(let p):
            // `prefill_tokens` is the conversation's transcript length minus
            // its evals (ds4-engine operator_telemetry.py:101-113), and
            // `sync_ms` includes a hit's load, so both carry the hit until the
            // next `.session` or `.prefixCache`. After `/clear` or a
            // compaction the count stops meaning prefill; a corrected count of
            // 0 or less keeps the prior rate rather than showing ~0.
            var tokens = p.prefillTokens, ms = p.prefillMs
            if let hit = state.prefixCache, hit.outcome == "hit" {
                tokens = tokens.map { $0 - (hit.tokens ?? 0) }.flatMap { $0 > 0 ? $0 : nil }
                ms = ms.map { $0 - (hit.loadMs ?? 0) }
            }
            state.prefillTPS = rate(tokens, ms) ?? state.prefillTPS
            state.generationTPS = rate(p.evalCount, p.evalMs) ?? state.generationTPS
        case .answer(let a):
            state.contextUsed = a.contextUsed ?? state.contextUsed
            state.contextSize = a.contextSize ?? state.contextSize
        case .session(let info):
            state.contextSize = info.contextSize ?? state.contextSize
            state.prefixCache = nil  // a new process: new counters
            state.startup = EngineStartupInfo()
            state.conversationState = nil
        case .startup(let part, _):
            state.startup.fold(part)
        case .conversationState(let c):
            state.conversationState = c
        case .prefixCache(let p):
            state.prefixCache = p
        case .resumed(let r):
            // A relaunched session's context, before its first answer.
            state.contextUsed = r.contextUsed ?? state.contextUsed
        case .interrupted(let used, let size):
            state.contextUsed = used ?? state.contextUsed
            state.contextSize = size ?? state.contextSize
        case .memory(let m):
            state.gpuAllocatedBytes = m.allocatedBytes ?? state.gpuAllocatedBytes
            state.gpuBudgetBytes = m.budgetBytes ?? state.gpuBudgetBytes
            state.planGiB = m.planGiB ?? state.planGiB
        default:
            break
        }
    }

    private static func rate(_ tokens: Int?, _ ms: Double?) -> Double? {
        guard let tokens, let ms, ms > 0 else { return nil }
        return Double(tokens) / (ms / 1000)
    }
}
