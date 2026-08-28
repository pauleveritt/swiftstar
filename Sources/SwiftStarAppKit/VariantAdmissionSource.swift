import Foundation

/// The single seam every `VariantGate.admit` call site uses for "how much
/// memory is available for this launch" (P25 Cycle 4a). `VariantGate.admit`
/// already takes a plain `Int64` — this exists so a future denominator change
/// (P25 Cycle 4b: a Metal working-set-aware limit, replacing free+inactive
/// pages) has one place to change instead of every call site independently.
/// Unchanged behavior today: delegates straight to
/// `MemorySnapshot.availableBytes()`.
public enum VariantAdmissionSource {
    public static func availableBytes() -> Int64 {
        MemorySnapshot.availableBytes()
    }
}
