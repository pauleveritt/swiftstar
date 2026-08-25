import Foundation

/// The catalog of known variants. Hardcoded Swift (matches the existing
/// hardcoded model preset); holds Mellum now, Laguna XS next week. The
/// registry is the single source of variant *identity*; `VariantResolver` is
/// the single source of *modelPath resolution*.
public enum VariantRegistry {
    public static let all: [Variant] = [mellum]

    public static func resolve(_ id: String) -> Variant? {
        all.first { $0.id == id }
    }

    public static let mellum: Variant = {
        let defaultPath = NSHomeDirectory() + "/models/mellum-thinking-TARGET.gguf"
        let path = ProcessInfo.processInfo.environment["SWIFTSTAR_MELLUM_MODEL"] ?? defaultPath
        return Variant(
            id: "mellum-2.1",
            displayName: "Mellum 2.1",
            modelFile: URL(fileURLWithPath: path),
            family: .mellum,
            sampler: nil,  // engine family default (undocumented for Mellum) — D6
            contract: RuntimeContract(
                architecture: "mellum",
                rope: RopeContract(scalingType: "yarn", freqBase: 500_000.0),
                quantLayout: QuantContract(
                    downType: .q8_0,
                    layerCount: 28,
                    downTensorPattern: "blk.%d.ffn_down_exps.weight"
                ),
                memoryBudget: MemoryBudget(
                    weightsGiB: 9.33,
                    scratchGiB: 0.4,
                    kvGiBAt16k: 0.26,
                    kvGiBAt32k: 0.48,
                    kvGiBAt40k: 0.59
                )
            )
        )
    }()
}
