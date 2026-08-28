import Testing
import Foundation
@testable import SwiftStarKit

struct VariantGateTests {
    private func variant(modelFile: URL) -> Variant {
        let base = VariantRegistry.mellum
        return Variant(
            id: base.id,
            displayName: base.displayName,
            modelFile: modelFile,
            family: base.family,
            sampler: base.sampler,
            contract: base.contract
        )
    }

    private func writeMellumGGUF(downType: UInt32 = 8) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-test-\(UUID().uuidString).gguf")
        try GGUFBuilder.make(tensors: GGUFBuilder.mellumTensors(downType: downType)).write(to: url)
        return url
    }

    private let plentyOfBytes: Int64 = 256 * 1024 * 1024 * 1024  // 256 GiB

    @Test func admitsACleanMellumVariant() throws {
        let url = try writeMellumGGUF()
        let result = VariantGate.admit(variant(modelFile: url), contextSize: 32_768, availableBytes: plentyOfBytes)
        #expect(result == .admitted)
    }

    @Test func unreadableFileIsContractMismatch() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).gguf")
        let result = VariantGate.admit(variant(modelFile: url), contextSize: 32_768, availableBytes: plentyOfBytes)
        guard case .contractMismatch(let mismatches) = result else {
            Issue.record("expected contractMismatch, got \(result)")
            return
        }
        #expect(mismatches.count == 1)
        guard case .unreadableFile = mismatches[0] else {
            Issue.record("expected .unreadableFile, got \(mismatches)")
            return
        }
    }

    @Test func contractMismatchPrecedesMemoryCheck() throws {
        let url = try writeMellumGGUF(downType: 6)  // Q5_0 down: contract violation
        let result = VariantGate.admit(variant(modelFile: url), contextSize: 32_768, availableBytes: 1)  // also infeasible
        guard case .contractMismatch = result else {
            Issue.record("expected contractMismatch (precedence), got \(result)")
            return
        }
    }

    @Test func infeasibleBudgetRefuses() throws {
        let url = try writeMellumGGUF()
        let result = VariantGate.admit(variant(modelFile: url), contextSize: 40_960, availableBytes: 8 * 1024 * 1024 * 1024)
        guard case .infeasible(let reason) = result else {
            Issue.record("expected infeasible, got \(result)")
            return
        }
        #expect(reason.deficitBytes > 0)
        #expect(reason.message.contains("Mellum"))
    }

    @Test func unsupportedContextRefuses() throws {
        let url = try writeMellumGGUF()
        let result = VariantGate.admit(variant(modelFile: url), contextSize: 131_072, availableBytes: plentyOfBytes)
        guard case .contractMismatch(let mismatches) = result else {
            Issue.record("expected contractMismatch (unsupported ctx), got \(result)")
            return
        }
        #expect(mismatches.count == 1)
        guard case .unsupportedContext(let requested, _, _) = mismatches[0] else {
            Issue.record("expected .unsupportedContext, got \(mismatches)")
            return
        }
        #expect(requested == 131_072)
    }

    @Test func admittedHasNilRefusalMessage() throws {
        let url = try writeMellumGGUF()
        let result = VariantGate.admit(variant(modelFile: url), contextSize: 32_768, availableBytes: plentyOfBytes)
        #expect(result.refusalMessage == nil)
    }
}

struct LagunaSGateTests {
    private func variant(modelFile: URL) -> Variant {
        let base = VariantRegistry.lagunaS
        return Variant(
            id: base.id,
            displayName: base.displayName,
            modelFile: modelFile,
            family: base.family,
            sampler: base.sampler,
            contract: base.contract
        )
    }

    private func writeLagunaSGGUF(q2Type: UInt32 = 10, q3Type: UInt32 = 11) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-test-\(UUID().uuidString).gguf")
        let tensors = GGUFBuilder.lagunaSTensors(q2Type: q2Type, q3Type: q3Type)
        try GGUFBuilder.makeLaguna(tensors: tensors).write(to: url)
        return url
    }

    private let plentyOfBytes: Int64 = 256 * 1024 * 1024 * 1024  // 256 GiB

    @Test func admitsACleanLagunaSVariantAtTheAppDefaultContext() throws {
        let url = try writeLagunaSGGUF()
        // The app's shipped default context (51,200) — Laguna S's declared
        // range (16,384–51,200) must actually cover it (unlike Mellum/XS).
        let result = VariantGate.admit(variant(modelFile: url), contextSize: 51_200, availableBytes: plentyOfBytes)
        #expect(result == .admitted)
    }

    @Test func mixedQuantMismatchIsNamedPerSegment() throws {
        // Q3_K where Q2_K is expected on the first segment: a contract
        // violation the single-segment shape couldn't even express.
        let url = try writeLagunaSGGUF(q2Type: 11)
        let result = VariantGate.admit(variant(modelFile: url), contextSize: 51_200, availableBytes: plentyOfBytes)
        guard case .contractMismatch(let mismatches) = result else {
            Issue.record("expected contractMismatch, got \(result)")
            return
        }
        #expect(mismatches.count == 20)
    }

    @Test func unsupportedContextAboveLagunaSRangeRefuses() throws {
        let url = try writeLagunaSGGUF()
        let result = VariantGate.admit(variant(modelFile: url), contextSize: 200_000, availableBytes: plentyOfBytes)
        guard case .contractMismatch(let mismatches) = result else {
            Issue.record("expected contractMismatch (unsupported ctx), got \(result)")
            return
        }
        #expect(mismatches.count == 1)
        guard case .unsupportedContext = mismatches[0] else {
            Issue.record("expected .unsupportedContext, got \(mismatches)")
            return
        }
    }

    @Test func infeasibleBudgetRefusesWithLagunaSName() throws {
        let url = try writeLagunaSGGUF()
        let result = VariantGate.admit(variant(modelFile: url), contextSize: 32_768, availableBytes: 8 * 1024 * 1024 * 1024)
        guard case .infeasible(let reason) = result else {
            Issue.record("expected infeasible, got \(result)")
            return
        }
        #expect(reason.deficitBytes > 0)
        #expect(reason.message.contains("Laguna S"))
    }
}

/// P25 Cycle 4b: `wiredLimitAdvisoryBytes` is `VariantAdmissionSource`'s
/// second injected value — the RAM-based ceiling raising `iogpu.wired_limit_mb`
/// could reach. Table-driven over both regimes: the default (nil, every
/// pre-Cycle-4b call site including every test above) must keep the exact
/// legacy message; a caller that supplies it gets one of two GPU-appropriate
/// messages depending on whether raising the limit would actually help.
struct WiredLimitAdvisoryTests {
    private func mellum(modelFile: URL) -> Variant {
        let base = VariantRegistry.mellum
        return Variant(
            id: base.id, displayName: base.displayName, modelFile: modelFile,
            family: base.family, sampler: base.sampler, contract: base.contract)
    }

    private func writeMellumGGUF() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("advisory-test-\(UUID().uuidString).gguf")
        try GGUFBuilder.make(tensors: GGUFBuilder.mellumTensors()).write(to: url)
        return url
    }

    @Test func noAdvisoryKeepsTheLegacyCloseAppsMessage() throws {
        let url = try writeMellumGGUF()
        let result = VariantGate.admit(mellum(modelFile: url), contextSize: 40_960, availableBytes: 1)
        guard case .infeasible(let reason) = result else {
            Issue.record("expected infeasible, got \(result)")
            return
        }
        #expect(reason.message.contains("Close memory-heavy apps"))
        #expect(!reason.message.contains("sysctl"))
        #expect(reason.wiredLimitAdvisoryBytes == nil)
        #expect(reason.wiredLimitFixBytes == nil)
    }

    @Test func advisoryProvidedAndRaisingTheLimitWouldHelpNamesTheSysctl() throws {
        let url = try writeMellumGGUF()
        let variant = mellum(modelFile: url)
        let totalBytes = try #require(variant.contract.memoryBudget.totalBytes(at: 40_960))
        // availableBytes is short; the advisory ceiling comfortably covers it,
        // deliberately +1 GiB above totalBytes so the two candidate MB values
        // a buggy implementation might print never collide.
        let advisory = totalBytes + 1_073_741_824
        let result = VariantGate.admit(
            variant, contextSize: 40_960, availableBytes: 1,
            wiredLimitAdvisoryBytes: advisory)
        guard case .infeasible(let reason) = result else {
            Issue.record("expected infeasible, got \(result)")
            return
        }
        #expect(!reason.message.contains("Close memory-heavy apps"))
        // The suggested sysctl value must be the advisory ceiling (RAM minus
        // the OS reserve) — NOT the launch's bare requirement. Setting the
        // system-wide GPU limit to exactly one launch's footprint leaves zero
        // room for anything else sharing it, which is the hang this cycle
        // exists to avoid. Regression: this bug shipped once already and no
        // test caught it because only the command's presence was checked.
        let advisoryMB = Int(Double(advisory) / 1_048_576)
        let totalBytesMB = Int((Double(totalBytes) / 1_048_576).rounded(.up))
        #expect(reason.message.contains("sudo sysctl -w iogpu.wired_limit_mb=\(advisoryMB)"))
        #expect(!reason.message.contains("sudo sysctl -w iogpu.wired_limit_mb=\(totalBytesMB)"))
        // The machine-readable form must agree with the prose: a UI reading
        // wiredLimitFixBytes instead of parsing message gets the same value.
        #expect(reason.wiredLimitAdvisoryBytes == advisory)
        #expect(reason.wiredLimitFixBytes == advisory)
    }

    @Test func advisoryProvidedButEvenRaisingIsNotEnoughSaysSoInstead() throws {
        let url = try writeMellumGGUF()
        let variant = mellum(modelFile: url)
        let totalBytes = try #require(variant.contract.memoryBudget.totalBytes(at: 40_960))
        // The advisory ceiling is itself below what's needed — raising the
        // sysctl wouldn't fix this; a smaller context is the only lever.
        let result = VariantGate.admit(
            variant, contextSize: 40_960, availableBytes: 1,
            wiredLimitAdvisoryBytes: totalBytes - 1)
        guard case .infeasible(let reason) = result else {
            Issue.record("expected infeasible, got \(result)")
            return
        }
        #expect(reason.message.contains("pick a smaller context size"))
        #expect(!reason.message.contains("sudo sysctl"))
        // An advisory was supplied but is insufficient — this is the case a
        // naive "wiredLimitAdvisoryBytes != nil means show a Raise button"
        // check would get wrong. wiredLimitFixBytes reads nil, correctly.
        #expect(reason.wiredLimitAdvisoryBytes == totalBytes - 1)
        #expect(reason.wiredLimitFixBytes == nil)
    }

    @Test func admissionStillSucceedsRegardlessOfAdvisoryWhenThereIsEnoughRoom() {
        let url = try? writeMellumGGUF()
        guard let url else { Issue.record("failed to write fixture"); return }
        let variant = mellum(modelFile: url)
        let plentyOfBytes: Int64 = 256 * 1024 * 1024 * 1024
        let result = VariantGate.admit(
            variant, contextSize: 40_960, availableBytes: plentyOfBytes,
            wiredLimitAdvisoryBytes: plentyOfBytes)
        #expect(result == .admitted)
    }
}

/// `FeasibilityReason.wiredLimitFixBytes` as a pure formula, independent of
/// `VariantGate`/GGUF fixtures — the fact a UI would actually read, so it
/// gets its own direct coverage rather than only exercising it incidentally
/// through admission tests (Fable review, 2026-08-28).
struct FeasibilityReasonWiredLimitFixTests {
    private func reason(plannedBytes: Int64, advisory: Int64?) -> FeasibilityReason {
        FeasibilityReason(
            message: "irrelevant for this test", deficitBytes: 0, availableBytes: 0,
            plannedBytes: plannedBytes, wiredLimitAdvisoryBytes: advisory)
    }

    @Test func nilAdvisoryIsNilFix() {
        #expect(reason(plannedBytes: 100, advisory: nil).wiredLimitFixBytes == nil)
    }

    @Test func advisoryAtExactlyPlannedBytesIsAFix() {
        // <= , not < — the boundary itself counts as "would help".
        #expect(reason(plannedBytes: 100, advisory: 100).wiredLimitFixBytes == 100)
    }

    @Test func advisoryOneByteBelowPlannedBytesIsNotAFix() {
        #expect(reason(plannedBytes: 100, advisory: 99).wiredLimitFixBytes == nil)
    }

    @Test func fixValueIsTheAdvisoryNotThePlannedBytes() {
        // The whole point of this cycle's fix: the suggested value must be
        // the RAM-based ceiling, never the launch's bare requirement.
        let fix = reason(plannedBytes: 100, advisory: 500).wiredLimitFixBytes
        #expect(fix == 500)
        #expect(fix != 100)
    }

    @Test func equatableIncludesTheNewFieldSoADifferingAdvisoryIsADifferentReason() {
        let a = reason(plannedBytes: 100, advisory: 500)
        let b = reason(plannedBytes: 100, advisory: 600)
        #expect(a != b)
    }
}
