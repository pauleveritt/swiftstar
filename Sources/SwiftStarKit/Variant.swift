import Foundation

/// The model family the engine keys its default sampling and admission on.
public enum ModelFamily: String, Equatable, Sendable {
    case mellum
}

/// Declared sampling defaults for a variant. Optional per-field and as a whole:
/// nil means "the engine's family default applies." Not wired to argv this
/// phase (D6); carried so the (b) runtime-contract shape exists.
public struct SamplerDefaults: Equatable, Sendable {
    public var temperature: Double?
    public var topK: Int?
    public var topP: Double?
    public var minP: Double?

    public init(temperature: Double? = nil, topK: Int? = nil, topP: Double? = nil, minP: Double? = nil) {
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.minP = minP
    }

    /// A compact, self-describing rendering for capture metadata, e.g.
    /// `temp 0.6 top-k 20 top-p 0.95 min-p 0.0`. Empty when nothing is set.
    public var description: String {
        var parts: [String] = []
        if let t = temperature { parts.append("temp \(t)") }
        if let k = topK { parts.append("top-k \(k)") }
        if let p = topP { parts.append("top-p \(p)") }
        if let m = minP { parts.append("min-p \(m)") }
        return parts.joined(separator: " ")
    }
}

/// The rope configuration a variant's runtime must honor. The two load-bearing
/// facts are the scaling type (which export the engine implements) and the
/// frequency base — a wrong export flipped a greedy token at 26 tokens on
/// identical weights (engine-lines harvest).
public struct RopeContract: Equatable, Sendable {
    public var scalingType: String
    public var freqBase: Double

    public init(scalingType: String, freqBase: Double) {
        self.scalingType = scalingType
        self.freqBase = freqBase
    }
}

/// The quant layout a variant's file must honor. The enforced fact is the down
/// projection's type (Q8_0 everywhere on Mellum); the engine's own admission
/// owns the deeper gate/up agreement checks.
public struct QuantContract: Equatable, Sendable {
    public var downType: GGUFType
    public var layerCount: Int
    /// printf-style tensor-name pattern, e.g. `blk.%d.ffn_down_exps.weight`.
    public var downTensorPattern: String

    public init(downType: GGUFType, layerCount: Int, downTensorPattern: String) {
        self.downType = downType
        self.layerCount = layerCount
        self.downTensorPattern = downTensorPattern
    }

    public func downTensorName(layer: Int) -> String {
        String(format: downTensorPattern, layer)
    }
}

/// The per-variant memory budget, a function of context size — not a constant.
/// Weights and scratch are constant; KV scales linearly with context, anchored
/// at the documented (16k, 32k, 40k) -> (0.26, 0.48, 0.59) GiB points (B1).
/// Context sizes outside [minContext, maxContext] are unsupported for the
/// declared budget and refused (D4).
public struct MemoryBudget: Equatable, Sendable {
    public var weightsGiB: Double
    public var scratchGiB: Double
    public var kvGiBAt16k: Double
    public var kvGiBAt32k: Double
    public var kvGiBAt40k: Double
    public var minContext: Int
    public var maxContext: Int

    public init(
        weightsGiB: Double,
        scratchGiB: Double,
        kvGiBAt16k: Double,
        kvGiBAt32k: Double,
        kvGiBAt40k: Double,
        minContext: Int = 16_384,
        maxContext: Int = 40_960
    ) {
        self.weightsGiB = weightsGiB
        self.scratchGiB = scratchGiB
        self.kvGiBAt16k = kvGiBAt16k
        self.kvGiBAt32k = kvGiBAt32k
        self.kvGiBAt40k = kvGiBAt40k
        self.minContext = minContext
        self.maxContext = maxContext
    }

    private static let gib = 1_073_741_824.0

    /// KV footprint in GiB at a context size, linearly interpolated over the
    /// documented anchors. nil outside [minContext, maxContext].
    public func kvGiB(at ctx: Int) -> Double? {
        guard ctx >= minContext, ctx <= maxContext else { return nil }
        if ctx <= 32_768 {
            let t = Double(ctx - 16_384) / Double(32_768 - 16_384)
            return kvGiBAt16k + (kvGiBAt32k - kvGiBAt16k) * t
        } else {
            let t = Double(ctx - 32_768) / Double(40_960 - 32_768)
            return kvGiBAt32k + (kvGiBAt40k - kvGiBAt32k) * t
        }
    }

    /// Total resident bytes at a context size; nil when the size is unsupported.
    public func totalBytes(at ctx: Int) -> Int64? {
        guard let kv = kvGiB(at: ctx) else { return nil }
        return Int64(((weightsGiB + scratchGiB + kv) * Self.gib).rounded())
    }
}

/// The enforced per-variant runtime contract (b): architecture, rope, quant
/// layout, and memory budget. Verified at selection/launch, before anything
/// expensive happens.
public struct RuntimeContract: Equatable, Sendable {
    public var architecture: String
    public var rope: RopeContract
    public var quantLayout: QuantContract
    public var memoryBudget: MemoryBudget

    public init(architecture: String, rope: RopeContract, quantLayout: QuantContract, memoryBudget: MemoryBudget) {
        self.architecture = architecture
        self.rope = rope
        self.quantLayout = quantLayout
        self.memoryBudget = memoryBudget
    }
}

/// A first-class model the app can run: identity, the file to load, the family,
/// optional declared sampler defaults, and the runtime contract that must be
/// honored. A `Variant` is not just a file path and a sampler (engine-lines).
public struct Variant: Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var modelFile: URL
    public var family: ModelFamily
    public var sampler: SamplerDefaults?
    public var contract: RuntimeContract

    public init(
        id: String,
        displayName: String,
        modelFile: URL,
        family: ModelFamily,
        sampler: SamplerDefaults? = nil,
        contract: RuntimeContract
    ) {
        self.id = id
        self.displayName = displayName
        self.modelFile = modelFile
        self.family = family
        self.sampler = sampler
        self.contract = contract
    }
}
