import Foundation

/// A named, actionable contract violation. `.unreadableFile` and
/// `.unsupportedContext` are synthesized by `VariantGate`, never by the
/// verifier (which is pure and does no IO).
public enum VariantMismatch: Equatable, Sendable {
    case architecture(expected: String, actual: String?)
    case rope(expected: String, actual: String)
    case downQuant(layer: Int, expected: GGUFType, actual: GGUFType?)
    case unreadableFile(path: String, reason: String)
    case unsupportedContext(requested: Int, min: Int, max: Int)

    /// One human-actionable line.
    public var message: String {
        switch self {
        case .architecture(let expected, let actual):
            return "architecture mismatch: expected '\(expected)', got '\(actual ?? "missing")'"
        case .rope(let expected, let actual):
            return "rope mismatch: expected [\(expected)], got [\(actual)]"
        case .downQuant(let layer, let expected, let actual):
            return "down-quant mismatch on layer \(layer): expected \(expected.name), got \(actual?.name ?? "missing")"
        case .unreadableFile(let path, let reason):
            return "cannot read \(path): \(reason)"
        case .unsupportedContext(let requested, let min, let max):
            return "context size \(requested) is unsupported for this variant (supported \(min)–\(max))"
        }
    }
}

/// Pure contract check: `(Variant, GGUFMetadata) -> [VariantMismatch]`. No IO,
/// no throws, total. Enforces exactly three facts — architecture, rope, and
/// down-quant on every layer. A missing tensor is a mismatch, never a skip.
public enum VariantVerifier {
    public static func verify(_ variant: Variant, metadata: GGUFMetadata) -> [VariantMismatch] {
        var mismatches: [VariantMismatch] = []

        // 1. Architecture — the root of the rope-flipped-token lesson.
        if metadata.architecture != variant.contract.architecture {
            mismatches.append(.architecture(
                expected: variant.contract.architecture,
                actual: metadata.architecture))
        }

        // 2. Rope scaling type + frequency base.
        let expectedRope = "scalingType=\(variant.contract.rope.scalingType) freqBase=\(variant.contract.rope.freqBase)"
        let actualRope = "scalingType=\(metadata.ropeScalingType ?? "missing") freqBase=\(metadata.ropeFreqBase.map { String($0) } ?? "missing")"
        if metadata.ropeScalingType != variant.contract.rope.scalingType
            || metadata.ropeFreqBase != variant.contract.rope.freqBase {
            mismatches.append(.rope(expected: expectedRope, actual: actualRope))
        }

        // 3. Down-quant on every layer. Iterate the layer range explicitly: a
        // missing key is `.downQuant(actual: nil)`, never a silent skip (I4).
        let layout = variant.contract.quantLayout
        for layer in 0..<layout.layerCount {
            let name = layout.downTensorName(layer: layer)
            let actual = metadata.tensorTypes[name]
            if actual != layout.downType {
                mismatches.append(.downQuant(layer: layer, expected: layout.downType, actual: actual))
            }
        }

        return mismatches
    }
}
