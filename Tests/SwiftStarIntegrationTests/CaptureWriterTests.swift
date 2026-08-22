import Testing
import Foundation
@testable import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct CaptureWriterTests {
    @Test func writesVerbatimFilesAndProvenance() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("p5-capture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let wire = Data("{\"t\":\"hello\",\"v\":1,\"caps\":[\"status\"],\"ts\":0}\n{\"t\":\"ready\",\"ts\":1}\n".utf8)
        let stderr = Data("ds4: memory: KV 1.57 GiB + resident model 44.94 GiB = 46.51 GiB planned\n".utf8)
        let manifest = CaptureManifest(
            submoduleSHA: "24caf7b836084042130b558ae39cd6954389bdbe",
            commandLine: ["ds4-agent", "--json-events", "--non-interactive", "-m", "laguna-s-2.1.gguf"],
            model: "laguna-s-2.1.gguf",
            ctx: 32768,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try CaptureWriter.write(directory: dir, wire: wire, stderr: stderr, manifest: manifest)

        #expect(try Data(contentsOf: dir.appendingPathComponent("wire.ndjson")) == wire)
        #expect(try Data(contentsOf: dir.appendingPathComponent("wire.stderr")) == stderr)
        let provenance = try String(contentsOf: dir.appendingPathComponent("provenance.md"), encoding: .utf8)
        #expect(provenance.contains("24caf7b836084042130b558ae39cd6954389bdbe"))
        #expect(provenance.contains("--json-events"))
        #expect(provenance.contains("32768"))
    }

    @Test func missingDirectoryIsCreated() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("p5-capture-\(UUID().uuidString)", isDirectory: true)
        let dir = parent.appendingPathComponent("nested/capture", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let manifest = CaptureManifest(submoduleSHA: "s", commandLine: ["c"], model: "m", ctx: 1, startedAt: Date())
        try CaptureWriter.write(directory: dir, wire: Data(), stderr: Data(), manifest: manifest)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("wire.ndjson").path))
    }
}
