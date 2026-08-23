import Testing
import Foundation
@testable import SwiftStarKit

struct FeasibilityTests {
    @Test func knownGoodFits() {
        let verdict = Feasibility.check(
            plannedBytes: 49_943_965_040,   // 46.51 GiB — the P1 config's plan
            availableBytes: 100 * 1024 * 1024 * 1024,
            modelName: "laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf"
        )
        #expect(verdict == .feasible)
    }

    @Test func knownBrokenRefuses() {
        let verdict = Feasibility.check(
            plannedBytes: 49_943_965_040,
            availableBytes: 24 * 1024 * 1024 * 1024,
            modelName: "laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf"
        )
        guard case .infeasible(let reason) = verdict else {
            Issue.record("expected infeasible")
            return
        }
        // The ~6.1 GiB Laguna scratch under-report is folded into the effective
        // plan (F4), so the reason carries the CORRECTED bytes, not the raw
        // planned_bytes.
        #expect(reason.deficitBytes > 0)
        #expect(reason.availableBytes == 24 * 1024 * 1024 * 1024)
        #expect(reason.plannedBytes == 49_943_965_040 + 6_549_825_126)
        // The message must carry the numbers and an actionable lever.
        #expect(reason.message.contains("52.6"))
        #expect(reason.message.contains("24.0"))
        #expect(reason.message.lowercased().contains("close"))
        #expect(reason.message.contains("smaller"))
    }

    @Test func lagunaCorrectionAppliesOnlyToLaguna() {
        let raw: Int64 = 49_943_965_040
        let correction: Int64 = 6_549_825_126
        let avail: Int64 = 30 * 1024 * 1024 * 1024
        // Laguna: the corrected plan includes the ~6.1 GiB scratch under-report.
        let laguna = Feasibility.check(plannedBytes: raw, availableBytes: avail,
                                       modelName: "laguna-s-2.1.gguf")
        if case .infeasible(let reason) = laguna {
            #expect(reason.plannedBytes == raw + correction)
        } else {
            Issue.record("expected infeasible for a Laguna model")
        }
        // Non-Laguna: no correction — the raw plan is used as-is.
        let other = Feasibility.check(plannedBytes: raw, availableBytes: avail,
                                      modelName: "mellum-2.1.gguf")
        if case .infeasible(let reason) = other {
            #expect(reason.plannedBytes == raw)
        } else {
            Issue.record("expected infeasible for a non-Laguna model")
        }
    }

    @Test func modelLargerThanTotalRAMAlwaysRefused() {
        // No prior run needed: planned >= total is refused outright.
        let verdict = Feasibility.check(
            plannedBytes: 200 * 1024 * 1024 * 1024,
            availableBytes: 128 * 1024 * 1024 * 1024,
            modelName: "big"
        )
        if case .feasible = verdict {
            Issue.record("expected infeasible for planned > total RAM")
        }
    }

    @Test func exactFitIsFeasible() {
        let verdict = Feasibility.check(
            plannedBytes: 1_000_000_000,
            availableBytes: 1_000_000_000,
            modelName: "exact"
        )
        #expect(verdict == .feasible)
    }
}
