import Foundation

public struct EngineMetricsState: Equatable, Sendable {
    public var prefillTPS: Double?
    public var generationTPS: Double?
    public var contextUsed: Int?
    public var contextSize: Int?
    public var gpuAllocatedBytes: Int64?
    public var gpuBudgetBytes: Int64?
    public var planGiB: Double?

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
            state.prefillTPS = rate(p.prefillTokens, p.prefillMs)
            state.generationTPS = rate(p.evalCount, p.evalMs)
        case .answer(let a):
            state.contextUsed = a.contextUsed ?? state.contextUsed
            state.contextSize = a.contextSize ?? state.contextSize
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
