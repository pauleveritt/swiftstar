import Testing
import Foundation
import SwiftStarKit

/// P25 Cycle 1/2 gate: parse the real DeepSeek V4 Flash artifact (91 GiB on
/// disk; only the GGUF header/kv/tensor-directory is read, never the weight
/// payload) and confirm the registered `Variant`'s declared contract verifies
/// against it with zero mismatches. Gated like every other real-file/
/// real-process test (`SWIFTSTAR_INTEGRATION=1 swift test`) since it depends
/// on the artifact actually being present on this machine.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct DeepSeekV4FlashMetadataIntegrationTests {
    @Test func realArtifactParsesAndVerifiesCleanly() throws {
        let variant = VariantRegistry.deepSeekV4Flash
        guard FileManager.default.isReadableFile(atPath: variant.modelFile.path) else {
            Issue.record("DeepSeek V4 Flash artifact not found at \(variant.modelFile.path) — skip on a machine without it staged")
            return
        }

        let metadata = try GGUFMetadataReader.parse(at: variant.modelFile)
        #expect(metadata.architecture == "deepseek4")
        #expect(metadata.ropeScalingType == "yarn")
        #expect(metadata.ropeFreqBase == 10_000.0)

        let mismatches = VariantVerifier.verify(variant, metadata: metadata)
        #expect(mismatches.isEmpty, "unexpected mismatches against the real file: \(mismatches.map(\.message))")
    }
}
