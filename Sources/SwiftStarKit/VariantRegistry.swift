import Foundation

/// The catalog of known variants. Hardcoded Swift (matches the existing
/// hardcoded model preset); holds Mellum now, Laguna XS next week. The
/// registry is the single source of variant *identity*; `VariantResolver` is
/// the single source of *modelPath resolution*.
public enum VariantRegistry {
    public static let all: [Variant] = [mellum, lagunaXS]

    public static func resolve(_ id: String) -> Variant? {
        all.first { $0.id == id }
    }

    /// Locate a variant's gguf. Model files legitimately live in more than one
    /// place on a development machine — the Mellum drop in `~/models`, the
    /// Laguna line in the ds4 checkout's `gguf/` — and a variant that names the
    /// wrong directory is unusable with no signal beyond `.unreadableFile`.
    /// (That is precisely how the XS default shipped: it named `~/models`, which
    /// holds only the Mellum file, and the acceptance run set the env override,
    /// so the green run masked it.)
    ///
    /// Order: the variant's own env override, then `SWIFTSTAR_MODEL_DIR`, then
    /// each known directory that actually has the file. When nothing matches,
    /// return the first candidate so the refusal names a plausible path rather
    /// than an empty string.
    static func locateModel(_ fileName: String, envKey: String) -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env[envKey], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directories: [URL] = []
        if let dir = env["SWIFTSTAR_MODEL_DIR"], !dir.isEmpty {
            directories.append(URL(fileURLWithPath: dir))
        }
        directories.append(home.appending(path: "models"))
        directories.append(home.appending(path: "projects/ds4/gguf"))

        let candidates = directories.map { $0.appending(path: fileName) }
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
            ?? candidates[0]
    }

    public static let mellum: Variant = {
        let path = locateModel("mellum-thinking-TARGET.gguf", envKey: "SWIFTSTAR_MELLUM_MODEL")
        return Variant(
            id: "mellum-2.1",
            displayName: "Mellum 2.1",
            modelFile: path,
            family: .mellum,
            // JetBrains' published sampling (ds4_engine_sampling_defaults,
            // ds4.c:63358): temp 0.6, top-k 20, top-p 0.95, min-p 0.0. Declared
            // for the record (D6); not wired to argv this phase.
            sampler: SamplerDefaults(temperature: 0.6, topK: 20, topP: 0.95, minP: 0.0),
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

    public static let lagunaXS: Variant = {
        let path = locateModel("laguna-xs-2.1-RoutedQ3_K-biased.gguf", envKey: "SWIFTSTAR_LAGUNA_XS_MODEL")
        return Variant(
            id: "laguna-xs-2.1",
            displayName: "Laguna XS 2.1",
            modelFile: path,
            family: .lagunaXS,
            // Laguna family sampling defaults (engine-lines.md): temp 0.7,
            // top-k 20, top-p 0.95, min-p 0.05. Declared, not wired (D6).
            sampler: SamplerDefaults(temperature: 0.7, topK: 20, topP: 0.95, minP: 0.05),
            // The 16 GB shipping config (LAGUNA-XS21.md §6): SSD-stream the
            // routed experts with a 3,200-expert cache and a 4096 prefill chunk.
            runtime: EngineRuntimeConfig(
                ssdStreaming: true, ssdStreamingCacheExperts: 3200, prefillChunk: 4096),
            contract: RuntimeContract(
                architecture: "laguna",
                rope: RopeContract(scalingType: "yarn", freqBase: 500_000.0),
                quantLayout: QuantContract(
                    downType: .q3_k,
                    // Layer 0 is the dense leading layer (no routed experts);
                    // the 39 sparse layers 1..39 carry the Q3_K routed experts.
                    startLayer: 1,
                    layerCount: 40,
                    downTensorPattern: "blk.%d.ffn_down_exps.weight"
                ),
                // Resident non-KV footprint (expert cache 4.03 + buffers 0.99 +
                // resident 0.20 = 5.22 GiB) + linear KV (0.69 @16k, 1.31 @32k).
                // Measured on 32 GB M1 Pro (mini-notes §8); 6.53 GiB @32k.
                memoryBudget: MemoryBudget(
                    weightsGiB: 5.22,
                    scratchGiB: 0.0,
                    kvGiBAt16k: 0.69,
                    kvGiBAt32k: 1.31,
                    kvGiBAt40k: 1.31,
                    minContext: 16_384,
                    maxContext: 32_768
                )
            )
        )
    }()
}
