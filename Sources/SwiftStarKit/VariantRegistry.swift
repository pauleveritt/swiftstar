import Foundation

/// The catalog of known variants. Hardcoded Swift (matches the existing
/// hardcoded model preset); holds Mellum now, Laguna XS next week. The
/// registry is the single source of variant *identity*; `VariantResolver` is
/// the single source of *modelPath resolution*.
public enum VariantRegistry {
    public static let all: [Variant] = [mellum, lagunaXS, lagunaS]

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
        // DeepSeek V4 Flash's artifact (P25): lives only under DS4 Control's
        // download dir under its current `-0731` filename — the legacy copy in
        // the ds4 submodule's gguf/ carries a different (pre-`-0731`) filename,
        // so it would never match here regardless.
        directories.append(home.appending(path: "Library/Application Support/DS4 Control/gguf"))

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

    /// Laguna S 2.1 — the app's default model (~46 GiB on disk), given a real
    /// `Variant` (P22) so it participates in `VariantGate`/`VariantVerifier`
    /// like Mellum and Laguna XS instead of bypassing both via
    /// `AgentController.defaultModelFallback`.
    public static let lagunaS: Variant = {
        let path = locateModel("laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf", envKey: "SWIFTSTAR_LAGUNA_S_MODEL")
        return Variant(
            id: "laguna-s-2.1",
            displayName: "Laguna S 2.1",
            modelFile: path,
            family: .lagunaS,
            // Laguna family sampling defaults (engine-lines.md): temp 0.7,
            // top-k 20, top-p 0.95, min-p 0.05 — same family default as XS.
            sampler: SamplerDefaults(temperature: 0.7, topK: 20, topP: 0.95, minP: 0.05),
            // S was deliberately excluded from SSD streaming (engine-lines.md,
            // ROADMAP P22 forward item) — nil runtime, same as Mellum.
            contract: RuntimeContract(
                architecture: "laguna",
                rope: RopeContract(scalingType: "yarn", freqBase: 500_000.0),
                // Read from the real file (GGUFMetadataReader): a dense leading
                // layer 0 (not routed, like Laguna XS), then MIXED routed-expert
                // quant across layers 1..<48 — Q2_K on 1..<21 (20 layers), Q3_K
                // on 21..<48 (the last 27; "RoutedQ2_K-Last27Q3_K" in the
                // filename, confirmed tensor-by-tensor against the file).
                quantLayout: QuantContract(
                    segments: [
                        QuantContract.Segment(downType: .q2_k, startLayer: 1, layerCount: 21),
                        QuantContract.Segment(downType: .q3_k, startLayer: 21, layerCount: 48),
                    ],
                    downTensorPattern: "blk.%d.ffn_down_exps.weight"
                ),
                // Resident footprint at three context anchors, all derived from
                // formulas this project measured and documented against the
                // real engine (docs/superpowers/research/
                // 2026-08-22-p11-engine-constraints-and-corrections.md,
                // "Correction 2"), cross-checked against the file's on-disk
                // size (48,260,803,968 bytes = 44.9464 GiB) for sanity:
                //   weights  ~= on-disk size (S is resident, not SSD-streamed)
                //   scratch  = min(ctx,16384) x 375,156 B/row, constant for any
                //              ctx >= 16,384 (the allocator's prefill_cap caps
                //              at 16,384) = 6,146,555,904 B = 5.7244 GiB
                //   KV(ctx)  = 49,152 x ctx + 75,497,472 B (reproduces the
                //              doc's cited measured `ready` events byte-exact
                //              at ctx 32,768 and ctx 150,000)
                // maxContext 150,000 is the doc's own verified operating point
                // (docs/harvest/telemetry-findings.md: "the everyday ctx
                // 150,000 setting") and comfortably covers the app's shipped
                // default context (51,200), unlike Mellum/XS's narrower ranges.
                memoryBudget: MemoryBudget(
                    weightsGiB: 44.9464,
                    scratchGiB: 5.7244,
                    kvGiBAt16k: 0.8203125,
                    kvGiBAt32k: 1.5703125,
                    kvGiBAt40k: 1.9453125,
                    minContext: 16_384,
                    maxContext: 150_000
                )
            )
        )
    }()
}
