import Foundation
@testable import SwiftStarKit

/// Test-support: build minimal GGUF v3 byte streams (header + kv + tensor
/// directory only, no weights) and in-memory `GGUFMetadata` values for the
/// verifier/gate tests. Matches the format the P12.2 generator documents.
enum GGUFBuilder {
    static func u32(_ v: UInt32) -> Data {
        var d = Data()
        d.append(UInt8(v & 0xff))
        d.append(UInt8((v >> 8) & 0xff))
        d.append(UInt8((v >> 16) & 0xff))
        d.append(UInt8((v >> 24) & 0xff))
        return d
    }

    static func u64(_ v: UInt64) -> Data {
        var d = Data()
        for k in 0..<8 { d.append(UInt8((v >> (8 * k)) & 0xff)) }
        return d
    }

    static func f32(_ v: Float) -> Data { u32(v.bitPattern) }

    static func str(_ s: String) -> Data { u64(UInt64(s.utf8.count)) + Data(s.utf8) }

    static let stringType: UInt32 = 8
    static let float32Type: UInt32 = 6

    static func make(
        architecture: String = "mellum",
        scalingType: String = "yarn",
        freqBase: Float = 500_000.0,
        tensors: [(name: String, type: UInt32, dims: [UInt64])],
        version: UInt32 = 3
    ) -> Data {
        let kv: [Data] = [
            str("general.architecture") + u32(stringType) + str(architecture),
            str("mellum.rope.scaling.type") + u32(stringType) + str(scalingType),
            str("mellum.rope.freq_base") + u32(float32Type) + f32(freqBase),
        ]
        var body = Data()
        body.append(u32(0x4655_4747))       // "GGUF"
        body.append(u32(version))
        body.append(u64(UInt64(tensors.count)))
        body.append(u64(UInt64(kv.count)))
        for k in kv { body.append(k) }
        for t in tensors {
            body.append(str(t.name))
            body.append(u32(UInt32(t.dims.count)))
            for dim in t.dims { body.append(u64(dim)) }
            body.append(u32(t.type))
            body.append(u64(0))             // relative offset (payload not read)
        }
        return body
    }

    /// A Laguna-shaped byte stream: same as `make` but with `laguna.rope.*`
    /// metadata keys (Laguna XS 2.1).
    static func makeLaguna(
        architecture: String = "laguna",
        scalingType: String = "yarn",
        freqBase: Float = 500_000.0,
        tensors: [(name: String, type: UInt32, dims: [UInt64])],
        version: UInt32 = 3
    ) -> Data {
        let kv: [Data] = [
            str("general.architecture") + u32(stringType) + str(architecture),
            str("laguna.rope.scaling.type") + u32(stringType) + str(scalingType),
            str("laguna.rope.freq_base") + u32(float32Type) + f32(freqBase),
        ]
        var body = Data()
        body.append(u32(0x4655_4747))       // "GGUF"
        body.append(u32(version))
        body.append(u64(UInt64(tensors.count)))
        body.append(u64(UInt64(kv.count)))
        for k in kv { body.append(k) }
        for t in tensors {
            body.append(str(t.name))
            body.append(u32(UInt32(t.dims.count)))
            for dim in t.dims { body.append(u64(dim)) }
            body.append(u32(t.type))
            body.append(u64(0))
        }
        return body
    }

    /// A Mellum-shaped tensor directory: `blk.N.ffn_down_exps.weight` for N in
    /// 0..<layerCount, all `downType` (Q8_0 = 8). `dropLayer` omits one layer.
    static func mellumTensors(
        downType: UInt32 = 8,
        layerCount: Int = 28,
        dropLayer: Int? = nil
    ) -> [(name: String, type: UInt32, dims: [UInt64])] {
        var tensors: [(String, UInt32, [UInt64])] = []
        for layer in 0..<layerCount {
            if layer == dropLayer { continue }
            tensors.append(("blk.\(layer).ffn_down_exps.weight", downType, [896, 2304, 64]))
        }
        return tensors
    }

    /// A Laguna-XS-shaped tensor directory: `blk.N.ffn_down_exps.weight` for N
    /// in startLayer..<layerCount (1..<40), all `downType` (Q3_K = 11).
    static func lagunaTensors(
        downType: UInt32 = 11,
        startLayer: Int = 1,
        layerCount: Int = 40,
        dropLayer: Int? = nil
    ) -> [(name: String, type: UInt32, dims: [UInt64])] {
        var tensors: [(String, UInt32, [UInt64])] = []
        for layer in startLayer..<layerCount {
            if layer == dropLayer { continue }
            tensors.append(("blk.\(layer).ffn_down_exps.weight", downType, [896, 2304, 64]))
        }
        return tensors
    }

    /// A Laguna-S-shaped tensor directory: `blk.N.ffn_down_exps.weight` for N
    /// in startLayer..<layerCount (1..<48 by default), Q2_K (10) on
    /// `1..<q3StartLayer` and Q3_K (11) from `q3StartLayer` on — the mixed
    /// "RoutedQ2_K-Last27Q3_K" layout read from the real file.
    static func lagunaSTensors(
        q2Type: UInt32 = 10,
        q3Type: UInt32 = 11,
        startLayer: Int = 1,
        q3StartLayer: Int = 21,
        layerCount: Int = 48,
        dropLayer: Int? = nil
    ) -> [(name: String, type: UInt32, dims: [UInt64])] {
        var tensors: [(String, UInt32, [UInt64])] = []
        for layer in startLayer..<layerCount {
            if layer == dropLayer { continue }
            let type = layer < q3StartLayer ? q2Type : q3Type
            tensors.append(("blk.\(layer).ffn_down_exps.weight", type, [896, 2304, 64]))
        }
        return tensors
    }

    /// A DeepSeek-V4-Flash-shaped byte stream: same as `make` but with
    /// `deepseek4.rope.*` metadata keys (arch `deepseek4`).
    static func makeDeepSeek(
        architecture: String = "deepseek4",
        scalingType: String = "yarn",
        freqBase: Float = 10_000.0,
        tensors: [(name: String, type: UInt32, dims: [UInt64])],
        version: UInt32 = 3
    ) -> Data {
        let kv: [Data] = [
            str("general.architecture") + u32(stringType) + str(architecture),
            str("deepseek4.rope.scaling.type") + u32(stringType) + str(scalingType),
            str("deepseek4.rope.freq_base") + u32(float32Type) + f32(freqBase),
        ]
        var body = Data()
        body.append(u32(0x4655_4747))       // "GGUF"
        body.append(u32(version))
        body.append(u64(UInt64(tensors.count)))
        body.append(u64(UInt64(kv.count)))
        for k in kv { body.append(k) }
        for t in tensors {
            body.append(str(t.name))
            body.append(u32(UInt32(t.dims.count)))
            for dim in t.dims { body.append(u64(dim)) }
            body.append(u32(t.type))
            body.append(u64(0))
        }
        return body
    }

    /// A DeepSeek-V4-Flash-shaped tensor directory (q2-q4-imatrix layout, read
    /// from the real 0731 file): `blk.N.ffn_down_exps.weight` for N in
    /// 0..<layerCount (43), Q2_K (10) on 0..<q4StartLayer, Q4_K (12) from
    /// `q4StartLayer` on — no dense leading layer, unlike Laguna.
    static func deepSeekTensors(
        q2Type: UInt32 = 10,
        q4Type: UInt32 = 12,
        q4StartLayer: Int = 37,
        layerCount: Int = 43,
        dropLayer: Int? = nil
    ) -> [(name: String, type: UInt32, dims: [UInt64])] {
        var tensors: [(String, UInt32, [UInt64])] = []
        for layer in 0..<layerCount {
            if layer == dropLayer { continue }
            let type = layer < q4StartLayer ? q2Type : q4Type
            tensors.append(("blk.\(layer).ffn_down_exps.weight", type, [2048, 4096, 256]))
        }
        return tensors
    }

    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }
}

/// A clean Mellum `GGUFMetadata` (correct architecture/rope, all 28 down
/// tensors Q8_0), for verifier tests that don't need a file on disk.
func makeMellumMetadata(
    downType: GGUFType = .q8_0,
    layerCount: Int = 28,
    dropLayer: Int? = nil,
    architecture: String? = "mellum",
    scalingType: String? = "yarn",
    freqBase: Double? = 500_000.0
) -> GGUFMetadata {
    var tensorTypes: [String: GGUFType] = [:]
    for layer in 0..<layerCount {
        if layer == dropLayer { continue }
        tensorTypes["blk.\(layer).ffn_down_exps.weight"] = downType
    }
    return GGUFMetadata(
        architecture: architecture,
        ropeScalingType: scalingType,
        ropeFreqBase: freqBase,
        tensorTypes: tensorTypes
    )
}

/// A clean Laguna XS 2.1 `GGUFMetadata` (architecture "laguna", rope yarn /
/// 500000, routed down tensors Q3_K on layers 1..<40 — dense layer 0 skipped).
func makeLagunaMetadata(
    downType: GGUFType = .q3_k,
    startLayer: Int = 1,
    layerCount: Int = 40,
    dropLayer: Int? = nil,
    architecture: String? = "laguna",
    scalingType: String? = "yarn",
    freqBase: Double? = 500_000.0
) -> GGUFMetadata {
    var tensorTypes: [String: GGUFType] = [:]
    for layer in startLayer..<layerCount {
        if layer == dropLayer { continue }
        tensorTypes["blk.\(layer).ffn_down_exps.weight"] = downType
    }
    return GGUFMetadata(
        architecture: architecture,
        ropeScalingType: scalingType,
        ropeFreqBase: freqBase,
        tensorTypes: tensorTypes
    )
}

/// A clean DeepSeek V4 Flash `GGUFMetadata` (architecture "deepseek4", rope
/// yarn / 10000, routed down tensors Q2_K on layers 0..<37 then Q4_K on
/// 37..<43 — no dense leading layer, mirroring the real q2-q4-imatrix file's
/// "Layers37-42Q4KExperts" layout).
func makeDeepSeekMetadata(
    q2Type: GGUFType = .q2_k,
    q4Type: GGUFType = .q4_k,
    q4StartLayer: Int = 37,
    layerCount: Int = 43,
    dropLayer: Int? = nil,
    architecture: String? = "deepseek4",
    scalingType: String? = "yarn",
    freqBase: Double? = 10_000.0
) -> GGUFMetadata {
    var tensorTypes: [String: GGUFType] = [:]
    for layer in 0..<layerCount {
        if layer == dropLayer { continue }
        let type = layer < q4StartLayer ? q2Type : q4Type
        tensorTypes["blk.\(layer).ffn_down_exps.weight"] = type
    }
    return GGUFMetadata(
        architecture: architecture,
        ropeScalingType: scalingType,
        ropeFreqBase: freqBase,
        tensorTypes: tensorTypes
    )
}

/// A clean Laguna S 2.1 `GGUFMetadata` (architecture "laguna", rope yarn /
/// 500000, routed down tensors Q2_K on layers 1..<21 then Q3_K on 21..<48 —
/// dense layer 0 skipped, mirroring the real file's mixed
/// "RoutedQ2_K-Last27Q3_K" layout).
func makeLagunaSMetadata(
    q2Type: GGUFType = .q2_k,
    q3Type: GGUFType = .q3_k,
    startLayer: Int = 1,
    q3StartLayer: Int = 21,
    layerCount: Int = 48,
    dropLayer: Int? = nil,
    architecture: String? = "laguna",
    scalingType: String? = "yarn",
    freqBase: Double? = 500_000.0
) -> GGUFMetadata {
    var tensorTypes: [String: GGUFType] = [:]
    for layer in startLayer..<layerCount {
        if layer == dropLayer { continue }
        let type = layer < q3StartLayer ? q2Type : q3Type
        tensorTypes["blk.\(layer).ffn_down_exps.weight"] = type
    }
    return GGUFMetadata(
        architecture: architecture,
        ropeScalingType: scalingType,
        ropeFreqBase: freqBase,
        tensorTypes: tensorTypes
    )
}
