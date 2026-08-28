import Testing
import Foundation
import SwiftStarKit
import SwiftStarAppKit

/// P25 Cycle 4b's live regression gate: every variant admitted under the old
/// free+inactive-pages denominator must still admit under the new Metal
/// working-set one — the switch is meant to be strictly more permissive (and
/// more accurate), never a new refusal. Reads real system state
/// (`MTLCreateSystemDefaultDevice`, `iogpu.wired_limit_mb`), so gated like
/// every other live-system test (`SWIFTSTAR_INTEGRATION=1 swift test`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct WiredLimitAdmissionIntegrationTests {
    /// Every shipped variant, admitted at a context it actually declares as
    /// supported, must not be refused by the live denominator — a contract
    /// mismatch here would mean either the fixture (unrelated to this cycle)
    /// or a genuinely undersized machine, not this cycle's change; skip
    /// rather than fail so this test means what it says.
    @Test func everyVariantAdmitsUnderTheLiveMetalDenominator() {
        let available = VariantAdmissionSource.availableBytes()
        let advisory = VariantAdmissionSource.wiredLimitAdvisoryBytes()

        for variant in VariantRegistry.all {
            guard FileManager.default.isReadableFile(atPath: variant.modelFile.path) else {
                continue  // not staged on this machine — nothing to check
            }
            let ctx = variant.contract.memoryBudget.clampContext(51_200)
            let result = VariantGate.admit(
                variant, contextSize: ctx, availableBytes: available,
                wiredLimitAdvisoryBytes: advisory)
            switch result {
            case .admitted:
                break
            case .contractMismatch:
                continue  // unrelated to the denominator — a stale/wrong artifact, not this cycle's concern
            case .infeasible(let reason):
                Issue.record("\(variant.id) refused under the live Metal denominator: \(reason.message)")
            }
        }
    }

    /// On a 128 GiB machine, the flagship should admit at its declared
    /// maxContext (450,000 — chosen with ~1.76 GiB of real headroom below the
    /// OS-default Metal limit, not just barely inside it) with no sysctl
    /// raised. This only means something when the wired limit hasn't been
    /// raised — otherwise the machine isn't in the state the number
    /// describes, so skip rather than assert something else.
    @Test func deepSeekAdmitsAtItsDeclaredMaxContextOnA128GiBMachineWithNoRaisedLimit() {
        guard MetalWorkingSet.currentWiredLimitMB() == 0 else { return }
        let variant = VariantRegistry.deepSeekV4Flash
        guard FileManager.default.isReadableFile(atPath: variant.modelFile.path) else { return }
        guard MetalWorkingSet.systemMemoryBytes() >= 128 * 1_073_741_824 else { return }

        let result = VariantGate.admit(
            variant, contextSize: variant.contract.memoryBudget.maxContext,
            availableBytes: VariantAdmissionSource.availableBytes(),
            wiredLimitAdvisoryBytes: VariantAdmissionSource.wiredLimitAdvisoryBytes())
        #expect(result == .admitted, "expected admission at maxContext on a 128 GiB machine with the OS-default Metal limit, got \(result)")
    }
}
