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
        // range (16,384–150,000) must actually cover it (unlike Mellum/XS).
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
