import Foundation

/// The result of admitting (or refusing) a variant before spawn.
public enum VariantAdmission: Equatable, Sendable {
    case admitted
    case contractMismatch([VariantMismatch])
    case infeasible(FeasibilityReason)

    /// A single human-actionable refusal summary (empty when admitted).
    public var refusalMessage: String? {
        switch self {
        case .admitted:
            return nil
        case .contractMismatch(let mismatches):
            return mismatches.map(\.message).joined(separator: "\n")
        case .infeasible(let reason):
            return reason.message
        }
    }
}

/// The single admission entry point for both the app and the harness (D5):
/// read metadata -> verify -> memory check. `.unreadableFile` is synthesized
/// here (never by the verifier), and a contract mismatch takes precedence over
/// the memory check. Pure static function; no mutable state.
public enum VariantGate {
    public static func admit(
        _ variant: Variant,
        contextSize: Int,
        availableBytes: Int64,
        wiredLimitAdvisoryBytes: Int64? = nil
    ) -> VariantAdmission {
        // 1. Read the file's own metadata (header + kv + tensor directory only).
        let metadata: GGUFMetadata
        do {
            metadata = try GGUFMetadataReader.parse(at: variant.modelFile)
        } catch let e as GGUFMetadataReader.ReadError {
            return .contractMismatch([.unreadableFile(path: e.path, reason: e.reason)])
        } catch {
            return .contractMismatch([.unreadableFile(path: variant.modelFile.path, reason: "\(error)")])
        }

        // 2. Verify the declared contract.
        let mismatches = VariantVerifier.verify(variant, metadata: metadata)
        if !mismatches.isEmpty {
            return .contractMismatch(mismatches)
        }

        // 3. Memory check against the declared, context-dependent budget.
        let budget = variant.contract.memoryBudget
        guard let totalBytes = budget.totalBytes(at: contextSize) else {
            return .contractMismatch([.unsupportedContext(
                requested: contextSize,
                min: budget.minContext,
                max: budget.maxContext)])
        }
        guard totalBytes <= availableBytes else {
            let deficit = totalBytes - availableBytes
            return .infeasible(FeasibilityReason(
                message: infeasibleMessage(
                    variant: variant, totalBytes: totalBytes, availableBytes: availableBytes,
                    deficit: deficit, wiredLimitAdvisoryBytes: wiredLimitAdvisoryBytes),
                deficitBytes: deficit,
                availableBytes: availableBytes,
                plannedBytes: totalBytes,
                wiredLimitAdvisoryBytes: wiredLimitAdvisoryBytes
            ))
        }

        return .admitted
    }

    /// Two distinct messages depending on the denominator's semantics: with
    /// no advisory ceiling (legacy free+inactive-pages callers, and every
    /// pre-Cycle-4b test), "close apps" is correct advice. With an advisory
    /// ceiling (P25 Cycle 4b's Metal-working-set denominator), closing apps
    /// doesn't raise a GPU wired ceiling — the actual fix is either raising
    /// `iogpu.wired_limit_mb` (when the RAM headroom would allow it) or
    /// picking a smaller context (when it wouldn't).
    private static func infeasibleMessage(
        variant: Variant, totalBytes: Int64, availableBytes: Int64, deficit: Int64,
        wiredLimitAdvisoryBytes: Int64?
    ) -> String {
        guard let advisory = wiredLimitAdvisoryBytes else {
            return """
            "\(variant.displayName)" needs \(gib(totalBytes)) GiB of RAM but only \
            \(gib(availableBytes)) GiB is available (short \(gib(deficit)) GiB). \
            Close memory-heavy apps, or pick a smaller context size and check again.
            """
        }
        var message = """
        "\(variant.displayName)" needs \(gib(totalBytes)) GiB, but the GPU's current wired-memory \
        ceiling is \(gib(availableBytes)) GiB (short \(gib(deficit)) GiB).
        """
        // The same formula FeasibilityReason.wiredLimitFixBytes uses — one
        // decision, not two independently maintained ones (Fable review,
        // 2026-08-28: the prose and the machine-readable fact must agree).
        if let fix = FeasibilityReason.wiredLimitFix(plannedBytes: totalBytes, advisory: advisory) {
            // Suggest the advisory ceiling itself (RAM minus the OS reserve),
            // not the launch's bare requirement — setting the system-wide GPU
            // wired limit to exactly one launch's footprint leaves zero room
            // for WindowServer or anything else sharing it, which is the hang
            // this cycle exists to avoid.
            let advisoryMB = Int(Double(fix) / 1_048_576)
            message += " Raise the ceiling with: sudo sysctl -w iogpu.wired_limit_mb=\(advisoryMB)"
        } else {
            message += " Even raising the limit isn't enough on this machine's \(gib(advisory)) GiB " +
                "of usable RAM — pick a smaller context size."
        }
        return message
    }

    private static func gib(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }
}

/// The single source of `modelPath` resolution for both controllers and the
/// harness (C1/M4). Collapses the duplicated hardcoded-Laguna-default and the
/// duplicated resolution logic to one place. Returns the resolved file and the
/// matching variant (nil = custom/raw path, i.e. unverified).
public enum VariantResolver {
    /// Resolve a selected variant id to a `Variant`, treating nil/"custom" as
    /// "no preset variant selected" (the legacy raw-path case).
    public static func resolveVariant(selectedVariantID: String?) -> Variant? {
        guard let id = selectedVariantID, id != "custom" else { return nil }
        return VariantRegistry.resolve(id)
    }

    public static func resolveModelFile(
        selectedVariantID: String?,
        modelPath: String?,
        envModel: String?,
        fallback: URL
    ) -> (url: URL, variant: Variant?) {
        if let id = selectedVariantID, id != "custom", let variant = VariantRegistry.resolve(id) {
            return (variant.modelFile, variant)
        }
        if let p = modelPath, !p.isEmpty {
            return (URL(fileURLWithPath: p), nil)
        }
        if let e = envModel, !e.isEmpty {
            return (URL(fileURLWithPath: e), nil)
        }
        return (fallback, nil)
    }
}
