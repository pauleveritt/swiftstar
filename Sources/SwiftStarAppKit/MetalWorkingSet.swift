import Foundation
import Metal

/// GPU-wired working-set facts for the admission denominator (P25 Cycle 4b).
/// Mirrors ds4-control's `Feasibility.swift` (`effectiveWiredLimitMB`,
/// `wiredLimitAdvisoryMB`), adapted for SwiftStar's simpler admission shape:
/// `VariantGate.admit` takes plain `Int64` byte values, not this module's
/// types, so everything here reduces to two numbers `VariantAdmissionSource`
/// feeds in.
///
/// Why this replaces `MemorySnapshot.availableBytes()` as the denominator: a
/// large mmap'd, GPU-resident model's binding constraint is Metal's wired
/// working set, not free-page count — free+inactive pages measures the wrong
/// thing and made the same launch admit or refuse with the machine's memory
/// weather (P25 design doc, "the actual blocker").
public enum MetalWorkingSet {
    /// Physical unified memory in bytes.
    public static func systemMemoryBytes() -> Int64 {
        var bytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &bytes, &size, nil, 0)
        return Int64(bytes)
    }

    /// The live `iogpu.wired_limit_mb` sysctl (MB). 0 = OS default (the user
    /// hasn't raised it). Read live (not cached) so raising the sysctl in
    /// Terminal takes effect on the next admission check.
    public static func currentWiredLimitMB() -> Int {
        var value = 0  // zero-initialized: a 4-byte sysctl lands in the low bytes on arm64
        var size = MemoryLayout<Int>.size
        guard sysctlbyname("iogpu.wired_limit_mb", &value, &size, nil, 0) == 0 else { return 0 }
        return value
    }

    /// Metal's advertised ceiling (`recommendedMaxWorkingSetSize`), cached —
    /// it only changes once `iogpu.wired_limit_mb` is set, and the live
    /// sysctl read wins in that case anyway (`effectiveLimitBytes`).
    private static let metalDefaultLimitBytes: Int64 = {
        guard let device = MTLCreateSystemDefaultDevice() else { return 0 }
        return Int64(device.recommendedMaxWorkingSetSize)
    }()

    /// Conservative fallback when Metal reports no device at all: 75% of
    /// RAM, matching ds4-control's fallback (`defaultWiredLimitMB`).
    private static func fallbackLimitBytes() -> Int64 {
        Int64(Double(systemMemoryBytes()) * 0.75)
    }

    /// Test/debug override: when `SWIFTSTAR_EMULATE_WIRED_LIMIT_MB` is a
    /// positive integer, `effectiveLimitBytes()` reports that instead of the
    /// real sysctl — so the sysctl-override-wins precedence can be exercised
    /// without touching the real `iogpu.wired_limit_mb` (no sudo needed).
    /// Mirrors ds4-control's `DS4_EMULATE_WIRED_LIMIT_MB`.
    public static func emulatedWiredLimitMB() -> Int? {
        #if DEBUG
            guard let raw = ProcessInfo.processInfo.environment["SWIFTSTAR_EMULATE_WIRED_LIMIT_MB"],
                let mb = Int(raw), mb > 0
            else { return nil }
            return mb
        #else
            return nil
        #endif
    }

    /// The effective GPU wired ceiling right now: the emulated override when
    /// set (debug builds only), else the user's raised sysctl, else Metal's
    /// advertised default, else the RAM-based fallback if Metal reports no
    /// device.
    public static func effectiveLimitBytes() -> Int64 {
        if let emulated = emulatedWiredLimitMB() { return Int64(emulated) * 1_048_576 }
        let setMB = currentWiredLimitMB()
        if setMB > 0 { return Int64(setMB) * 1_048_576 }
        return metalDefaultLimitBytes > 0 ? metalDefaultLimitBytes : fallbackLimitBytes()
    }

    /// The OS reserve `wiredLimitAdvisoryMB` leaves below total RAM
    /// (ds4-control's `osReserveGiB` — 4 GiB).
    public static let osReserveBytes: Int64 = 4 * 1_073_741_824

    /// RAM minus the OS reserve — the ceiling raising `iogpu.wired_limit_mb`
    /// could reach on this machine, i.e. the largest advisory worth naming.
    public static func ramAdvisoryCeilingBytes() -> Int64 {
        max(0, systemMemoryBytes() - osReserveBytes)
    }
}
