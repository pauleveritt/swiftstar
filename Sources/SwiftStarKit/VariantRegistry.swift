import Foundation

/// The catalog of known variants. Hardcoded Swift (matches the existing
/// hardcoded model preset); holds Mellum now, Laguna XS next week. The
/// registry is the single source of variant *identity*; `VariantResolver` is
/// the single source of *modelPath resolution*.
public enum VariantRegistry {
    public static let all: [Variant] = [mellum, lagunaXS, lagunaS, deepSeekV4Flash]

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
                    // Derived from this variant's own 16k→32k slope
                    // (+0.62 GiB per 16,384 tokens → +0.31 per 8,192), not
                    // copied from the 32k anchor. `MemoryBudget.kvGiB(at:)`
                    // extrapolates above 32,768 from the 32k→40k slope, so a
                    // copied anchor plans KV flat at any larger context —
                    // dormant only while `maxContext` was 32,768 (P23).
                    kvGiBAt40k: 1.62,
                    minContext: 16_384,
                    // Raised from 32,768 (P23). The old cap was the 16/32 GB
                    // shipping budget — the comment above reads "Measured on
                    // 32 GB M1 Pro" — not a model limit: the GGUF declares
                    // laguna.context_length = 262144. Running the main agent
                    // at 32,768 forced five compactions in 24 minutes in the
                    // 2026-08-27 capture, manufacturing 37.5% of its
                    // Σsuffix. Capped at the app's own default (51,200)
                    // rather than the model ceiling, so the raise stays
                    // inside a measured envelope; VariantGate still admits
                    // against real memory.
                    maxContext: 51_200
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
        // The expert cache size feeds both argv (`--ssd-streaming-cache-
        // experts`) and the memory budget below — a single source so tuning
        // the cache can't silently leave the admission gate's weightsGiB
        // stale (code-review finding 2026-08-28: they used to be two
        // disconnected literals that happened to agree).
        let ssdStreamingCacheExperts = 3200
        // GiB per cached expert, measured live at cacheExperts=3200 (12.09
        // GiB / 3200) — a property of the model's expert tensor shape, not
        // of the cache size, so it holds if the cache is retuned. The 0.31
        // GiB resident slice (buffers outside the cache) is likewise
        // measured, not cache-size-dependent.
        let perExpertGiB = 12.09 / 3200.0
        let residentSliceGiB = 0.31
        return Variant(
            id: "laguna-s-2.1",
            displayName: "Laguna S 2.1",
            modelFile: path,
            family: .lagunaS,
            // Laguna family sampling defaults (engine-lines.md): temp 0.7,
            // top-k 20, top-p 0.95, min-p 0.05 — same family default as XS.
            sampler: SamplerDefaults(temperature: 0.7, topK: 20, topP: 0.95, minP: 0.05),
            // P22 SSD-across-the-line (engine divergence #13): S now rides the
            // same routed-expert streaming path as XS — --ssd-streaming with a
            // 3,200-expert resident cache (XS's tuned value; the S-ssd footprint
            // validation re-measures it). No prefill chunk: XS's 4096 is
            // XS-tuned, and the engine's --prefill-chunk gate stays XS21-only
            // (the laguna-s21-ssd branch's deliberate scope).
            runtime: EngineRuntimeConfig(
                ssdStreaming: true, ssdStreamingCacheExperts: ssdStreamingCacheExperts, prefillChunk: nil),
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
                // Resident footprint under SSD streaming (P22 divergence #13;
                // GLM review fix 2026-08-28 — the budget previously modeled the
                // resident path S no longer uses, over-estimating the gate's
                // need ~2.6×). Measured live at ctx 51200 on the pinned engine:
                //   weights  = cacheExperts x perExpertGiB + residentSliceGiB
                //              ~= 3200 x 0.0037781 + 0.31 = 12.40 GiB (the
                //              ~46 GiB file streams from SSD; see above)
                //   scratch  = 6,146,969,608 B = 5.72 GiB (same as resident)
                //   KV(ctx)  = 49,152 x ctx + 75,497,472 B — unchanged from the
                //              resident path (the wire's kv_bytes at 51200
                //              reproduces the formula byte-exact)
                // planned at 51200 = 20.53 GiB vs 53.08 GiB resident.
                //
                // maxContext is capped at the measured point (51200), not the
                // model's own 150,000 ceiling (validated for the *resident*
                // path only — the old comment's byte-exact KV cross-check at
                // ctx 150,000 predates this streaming budget). The streaming
                // path's non-KV terms (expert cache, scratch) have not been
                // observed above 51200, and S passes no `--prefill-chunk` cap
                // the way XS does, so nothing bounds a long-prefill streaming
                // buffer from growing with context (code-review finding
                // 2026-08-28: the prior 150,000 ceiling was pure extrapolation
                // from one datapoint — the "sparse sampling undersold a
                // worst-case claim" trap this project has hit before). Raise
                // it again once a live measurement at a higher context
                // confirms the streaming path stays flat.
                memoryBudget: MemoryBudget(
                    weightsGiB: Double(ssdStreamingCacheExperts) * perExpertGiB + residentSliceGiB,
                    scratchGiB: 5.72,
                    kvGiBAt16k: 0.8203125,
                    kvGiBAt32k: 1.5703125,
                    kvGiBAt40k: 1.9453125,
                    minContext: 16_384,
                    maxContext: 51_200
                )
            )
        )
    }()

    /// DeepSeek V4 Flash — the 128 GB flagship rung (P25), the reference the
    /// other three are measured against (`docs/laptop-ai.md`). Resident only
    /// (no SSD streaming; that is the 32 GB Laguna XS story). Weights are
    /// local — no download; the only artifact copy under the expected `-0731`
    /// filename lives in DS4 Control's own download directory.
    public static let deepSeekV4Flash: Variant = {
        let path = locateModel(
            "DeepSeek-V4-Flash-Layers37-42Q4KExperts-OtherExpertLayersIQ2XXSGateUp-Q2KDown-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-fixed-0731.gguf",
            envKey: "SWIFTSTAR_DEEPSEEK_V4_FLASH_MODEL")
        return Variant(
            id: "deepseek-v4-flash",
            displayName: "DeepSeek V4 Flash",
            modelFile: path,
            family: .deepSeekV4Flash,
            // No published sampler defaults for this family (unlike Mellum's
            // JetBrains numbers or the Laguna family default) — nil means
            // "engine defaults apply", same convention as an undeclared field.
            contract: RuntimeContract(
                architecture: "deepseek4",
                rope: RopeContract(scalingType: "yarn", freqBase: 10_000.0),
                // q2-q4-imatrix expert layout, read tensor-by-tensor from the
                // real 0731 file: Q2_K down-projection on layers 0..<37, Q4_K
                // on 37..<43 ("Layers37-42Q4KExperts" in the filename) — no
                // dense leading layer, unlike Laguna (layer 0 is already MoE).
                quantLayout: QuantContract(
                    segments: [
                        QuantContract.Segment(downType: .q2_k, startLayer: 0, layerCount: 37),
                        QuantContract.Segment(downType: .q4_k, startLayer: 37, layerCount: 43),
                    ],
                    downTensorPattern: "blk.%d.ffn_down_exps.weight"
                ),
                // Derived offline from ds4-control's Metal-allocator formulas
                // (P25 Cycle 3 pins this against a test-side port of those
                // formulas): weights = exact GGUF bytes (97,591,747,456);
                // scratch = shared + session graph workspace, constant above
                // the 4,096-token prefill cap; KV anchors include the
                // context-dependent indexer scratch. maxContext 450,000
                // leaves ~1.76 GiB of real headroom below the OS-default
                // Metal working-set ceiling (107.52 GiB on a 128 GiB M5 Max)
                // — deliberately not "just inside" it (526,267 was the exact
                // crossover; a Fable review flagged that margin as
                // indistinguishable from the oracle's own error tolerance,
                // with zero allowance for other GPU-wired usage, and Cycle 5's
                // live validation is skipped by decision so it was never
                // proven in practice). The full 1,000,000 ceiling still needs
                // the wired limit raised (Cycle 4b's advisory).
                memoryBudget: MemoryBudget(
                    weightsGiB: 90.8894,
                    scratchGiB: 4.2179,
                    kvGiBAt16k: 0.742351,
                    kvGiBAt32k: 1.117839,
                    kvGiBAt40k: 1.305583,
                    minContext: 16_384,
                    maxContext: 450_000
                )
            )
        )
    }()
}
