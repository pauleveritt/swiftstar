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
