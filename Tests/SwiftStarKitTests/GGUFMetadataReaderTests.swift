import Testing
import Foundation
@testable import SwiftStarKit

struct GGUFMetadataReaderTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gguf-test-\(UUID().uuidString).gguf")
    }

    private func write(_ data: Data) throws -> URL {
        let url = tempURL()
        try data.write(to: url)
        return url
    }

    @Test func parsesMellumMetadata() throws {
        let data = GGUFBuilder.make(tensors: GGUFBuilder.mellumTensors())
        let url = try write(data)
        let meta = try GGUFMetadataReader.parse(at: url)
        #expect(meta.architecture == "mellum")
        #expect(meta.ropeScalingType == "yarn")
        #expect(meta.ropeFreqBase == 500_000.0)
        #expect(meta.tensorTypes.count == 28)
        #expect(meta.tensorTypes["blk.0.ffn_down_exps.weight"] == .q8_0)
        #expect(meta.tensorTypes["blk.27.ffn_down_exps.weight"] == .q8_0)
    }

    @Test func recordsNonQ8DownType() throws {
        let data = GGUFBuilder.make(tensors: GGUFBuilder.mellumTensors(downType: 6)) // Q5_0
        let url = try write(data)
        let meta = try GGUFMetadataReader.parse(at: url)
        #expect(meta.tensorTypes["blk.0.ffn_down_exps.weight"] == .q5_0)
    }

    @Test func parsesLagunaRopeKeysAndQ3K() throws {
        let data = GGUFBuilder.makeLaguna(tensors: GGUFBuilder.lagunaTensors())
        let url = try write(data)
        let meta = try GGUFMetadataReader.parse(at: url)
        #expect(meta.architecture == "laguna")
        #expect(meta.ropeScalingType == "yarn")
        #expect(meta.ropeFreqBase == 500_000.0)
        #expect(meta.tensorTypes.count == 39)
        #expect(meta.tensorTypes["blk.1.ffn_down_exps.weight"] == .q3_k)
        #expect(meta.tensorTypes["blk.39.ffn_down_exps.weight"] == .q3_k)
        #expect(meta.tensorTypes["blk.0.ffn_down_exps.weight"] == nil)
    }

    @Test func parsesLagunaSMixedQuantLayout() throws {
        // Laguna S 2.1's "RoutedQ2_K-Last27Q3_K": Q2_K on layers 1..<21, Q3_K
        // on 21..<48 — the reader itself is quant-shape-agnostic (it just
        // records whatever type id each tensor carries), but this pins that
        // both type ids (10 and 11) round-trip correctly in the same file.
        let data = GGUFBuilder.makeLaguna(tensors: GGUFBuilder.lagunaSTensors())
        let url = try write(data)
        let meta = try GGUFMetadataReader.parse(at: url)
        #expect(meta.architecture == "laguna")
        #expect(meta.tensorTypes.count == 47)
        #expect(meta.tensorTypes["blk.1.ffn_down_exps.weight"] == .q2_k)
        #expect(meta.tensorTypes["blk.20.ffn_down_exps.weight"] == .q2_k)
        #expect(meta.tensorTypes["blk.21.ffn_down_exps.weight"] == .q3_k)
        #expect(meta.tensorTypes["blk.47.ffn_down_exps.weight"] == .q3_k)
        #expect(meta.tensorTypes["blk.0.ffn_down_exps.weight"] == nil)
    }

    @Test func wrongVersionIsNamedRefusal() throws {
        let data = GGUFBuilder.make(tensors: GGUFBuilder.mellumTensors(), version: 2)
        let url = try write(data)
        do {
            _ = try GGUFMetadataReader.parse(at: url)
            Issue.record("expected a version refusal")
        } catch let e as GGUFMetadataReader.ReadError {
            #expect(e.reason.contains("version"))
        }
    }

    @Test func badMagicIsNamedRefusal() throws {
        let url = try write(Data("not a gguf at all".utf8))
        do {
            _ = try GGUFMetadataReader.parse(at: url)
            Issue.record("expected a magic refusal")
        } catch let e as GGUFMetadataReader.ReadError {
            #expect(e.reason.contains("magic"))
        }
    }

    @Test func truncatedDirectoryIsNamedRefusalNotSilentSkip() throws {
        let data = GGUFBuilder.make(tensors: GGUFBuilder.mellumTensors())
        let url = try write(Data(data.prefix(data.count / 2)))  // cut mid-directory
        do {
            _ = try GGUFMetadataReader.parse(at: url)
            Issue.record("expected a truncation refusal")
        } catch let e as GGUFMetadataReader.ReadError {
            #expect(e.reason.contains("truncated"))
        }
    }

    @Test func missingFileIsNamedRefusal() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).gguf")
        #expect(throws: GGUFMetadataReader.ReadError.self) {
            _ = try GGUFMetadataReader.parse(at: url)
        }
    }
}
