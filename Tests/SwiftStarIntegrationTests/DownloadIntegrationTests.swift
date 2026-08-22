import Testing
import Foundation
import SwiftStarKit
import SwiftStarAppKit

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct DownloadIntegrationTests {

    private func makeFileAndServer(bytes: Int, chunkSize: Int) throws -> (source: URL, log: URL, port: Int, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("source.bin")
        var data = Data()
        for i in 0..<bytes { data.append(UInt8(i % 251)) }
        try data.write(to: source)
        let port = try FakeServerHarness.freePort()
        let log = dir.appendingPathComponent("ranges.log")
        let binary = try FakeServerHarness.compileFile(at: FakeServerHarness.repoRoot.appendingPathComponent("Tools/RangeFileServer.swift"), into: dir)
        let server = try FakeServerHarness.spawn(binary, arguments: ["--port", "\(port)", "--file", source.path, "--log", log.path], env: [:])
        _ = server.stderr.fileHandleForReading.availableData  // wait for listening line
        return (source, log, port, dir)
    }

    @Test func fullDownloadIsByteIdentical() async throws {
        let (source, _, port, _) = try makeFileAndServer(bytes: 1_000_000, chunkSize: 100_000)
        let dest = source.deletingLastPathComponent().appendingPathComponent("out.bin")
        let runner = DownloadRunner()
        await runner.start(spec: DownloadSpec(
            url: URL(string: "http://127.0.0.1:\(port)/")!,
            destination: dest, chunkSize: 100_000, maxConcurrency: 3
        ))
        #expect(runner.state == .done(dest))
        let destData = try Data(contentsOf: dest)
        let srcData = try Data(contentsOf: source)
        #expect(destData == srcData)
    }

    @Test func resumeDownloadsOnlyMissingChunks() async throws {
        let (source, log, port, _) = try makeFileAndServer(bytes: 1_000_000, chunkSize: 100_000)
        let dest = source.deletingLastPathComponent().appendingPathComponent("out2.bin")
        // Seed the first two chunks + bitmap, as if a prior run died mid-way.
        let dir = URL(fileURLWithPath: dest.path + ".dld")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plan = ChunkedPlan(chunkSize: 100_000)
        let total = Int64(1_000_000)
        let full = try Data(contentsOf: source)
        for i in 0..<2 {
            let r = plan.range(forChunk: i, totalBytes: total)
            try full.subdata(in: Int(r.lowerBound)..<Int(r.upperBound)).write(to: dir.appendingPathComponent("\(i).part"))
        }
        var bm = DownloadBitmap(chunkCount: plan.chunkCount(forTotalBytes: total))
        bm.set(0)
        bm.set(1)
        try bm.serialize().write(to: dir.appendingPathComponent("bitmap.bin"))

        // A fresh runner is a "restart".
        let runner = DownloadRunner()
        await runner.start(spec: DownloadSpec(
            url: URL(string: "http://127.0.0.1:\(port)/")!,
            destination: dest, chunkSize: 100_000, maxConcurrency: 3
        ))
        #expect(runner.state == .done(dest))
        let destData = try Data(contentsOf: dest)
        #expect(destData == full)
        let ranges = try String(contentsOf: log, encoding: .utf8)
        let served = Set(ranges.split(separator: "\n").map(String.init))
        #expect(!served.contains("0-99999"), "chunk 0 must not be re-downloaded")
        #expect(!served.contains("100000-199999"), "chunk 1 must not be re-downloaded")
        #expect(served.contains("200000-299999"), "chunk 2 must be downloaded")
        #expect(served.contains("900000-999999"), "chunk 9 must be downloaded")
    }

    @Test func serverErrorFailsCleanly() async throws {
        let (_, _, port, _) = try makeFileAndServer(bytes: 100_000, chunkSize: 100_000)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("p3-fail-\(UUID().uuidString)")
            .appendingPathComponent("out.bin")
        let runner = DownloadRunner()
        // Wrong port → connection refused → clean .failed with a message.
        await runner.start(spec: DownloadSpec(
            url: URL(string: "http://127.0.0.1:\(port - 1)/")!,
            destination: dest
        ))
        if case .failed(let message) = runner.state {
            #expect(!message.isEmpty)
        } else {
            Issue.record("expected .failed, got \(runner.state)")
        }
    }
}
