import Testing
import Foundation
import SwiftStarAppKit

/// `MetalWorkingSet` lives in `SwiftStarAppKit`, which `SwiftStarKitTests`
/// (the fast tier) does not depend on — so these tests are structurally
/// integration-tier regardless of speed. Serialized: several tests mutate
/// the process-global `SWIFTSTAR_EMULATE_WIRED_LIMIT_MB` environment
/// variable, and Swift Testing runs tests within a suite concurrently by
/// default.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct MetalWorkingSetTests {
    @Test func systemMemoryBytesIsPlausible() {
        // Every Mac this app targets has well over 1 GiB of unified memory;
        // this mainly catches a broken sysctl read returning 0 or garbage.
        #expect(MetalWorkingSet.systemMemoryBytes() > 1_073_741_824)
    }

    @Test func ramAdvisoryCeilingIsRAMMinusTheOSReserve() {
        let expected = MetalWorkingSet.systemMemoryBytes() - MetalWorkingSet.osReserveBytes
        #expect(MetalWorkingSet.ramAdvisoryCeilingBytes() == expected)
    }

    @Test func ramAdvisoryCeilingNeverGoesNegative() {
        // max(0, ...) — a machine with less than the 4 GiB reserve would
        // otherwise report a negative ceiling, which is nonsensical.
        #expect(MetalWorkingSet.ramAdvisoryCeilingBytes() >= 0)
    }

    /// Live sanity, mirroring ds4-control's `testEffectiveWiredLimitLive`:
    /// the effective limit is always positive, and when the user has
    /// genuinely raised the sysctl, the live read wins over Metal's default.
    @Test func effectiveLimitBytesLive() {
        let inheritedOverride = ProcessInfo.processInfo.environment["SWIFTSTAR_EMULATE_WIRED_LIMIT_MB"]
        unsetenv("SWIFTSTAR_EMULATE_WIRED_LIMIT_MB")
        defer {
            if let inheritedOverride {
                setenv("SWIFTSTAR_EMULATE_WIRED_LIMIT_MB", inheritedOverride, 1)
            } else {
                unsetenv("SWIFTSTAR_EMULATE_WIRED_LIMIT_MB")
            }
        }
        let effective = MetalWorkingSet.effectiveLimitBytes()
        #expect(effective > 0)
        if MetalWorkingSet.currentWiredLimitMB() > 0 {
            #expect(effective == Int64(MetalWorkingSet.currentWiredLimitMB()) * 1_048_576)
        }
    }

    /// The precedence this cycle's whole admission-safety argument rests on
    /// — and the one branch that has never executed on any machine this app
    /// has run on (this machine's `iogpu.wired_limit_mb` is unset). Without
    /// the emulation hook, that precedence was asserted in prose only.
    @Test func emulatedOverrideWinsOverTheLiveSysctlAndMetalDefault() {
        let inheritedOverride = ProcessInfo.processInfo.environment["SWIFTSTAR_EMULATE_WIRED_LIMIT_MB"]
        defer {
            if let inheritedOverride {
                setenv("SWIFTSTAR_EMULATE_WIRED_LIMIT_MB", inheritedOverride, 1)
            } else {
                unsetenv("SWIFTSTAR_EMULATE_WIRED_LIMIT_MB")
            }
        }
        setenv("SWIFTSTAR_EMULATE_WIRED_LIMIT_MB", "20000", 1)
        #if DEBUG
            #expect(MetalWorkingSet.emulatedWiredLimitMB() == 20_000)
            #expect(MetalWorkingSet.effectiveLimitBytes() == 20_000 * 1_048_576)
        #else
            // Release builds never honor the override — a debug-only escape
            // hatch must not leak into what ships.
            #expect(MetalWorkingSet.emulatedWiredLimitMB() == nil)
        #endif
    }

    @Test func nonPositiveOrGarbageOverrideIsIgnored() {
        let inheritedOverride = ProcessInfo.processInfo.environment["SWIFTSTAR_EMULATE_WIRED_LIMIT_MB"]
        defer {
            if let inheritedOverride {
                setenv("SWIFTSTAR_EMULATE_WIRED_LIMIT_MB", inheritedOverride, 1)
            } else {
                unsetenv("SWIFTSTAR_EMULATE_WIRED_LIMIT_MB")
            }
        }
        for bad in ["0", "-5", "not-a-number", ""] {
            setenv("SWIFTSTAR_EMULATE_WIRED_LIMIT_MB", bad, 1)
            #expect(MetalWorkingSet.emulatedWiredLimitMB() == nil, "expected '\(bad)' to be ignored")
        }
    }
}
