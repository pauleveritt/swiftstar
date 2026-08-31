import Testing
import Foundation

/// Task 6: the ten `swiftstar-analyze` verbs moved into `swiftstar-eval`
/// unchanged. This spawns the real built binary (real process, real files —
/// integration tier) so it is sensitive to the actual dispatch registry in
/// `Sources/swiftstar-eval/main.swift` and `AnalyzeVerbs.swift`, not just a
/// name list — breaking one verb's entry in `analyzeVerbHandlers` makes this
/// fail.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct AnalyzeVerbsDispatchTests {
    /// `.build/debug/swiftstar-eval` — SwiftPM's stable symlink to whichever
    /// arch/config subdirectory `swift test` (run from the repo root) just
    /// built into.
    static var binary: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/debug/swiftstar-eval")
    }

    @discardableResult
    private func run(_ args: [String], cwd: URL) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = Self.binary
        process.arguments = args
        process.currentDirectoryURL = cwd
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    /// A capture directory with just enough on it (a bare wire.ndjson) for
    /// each verb to run its real logic instead of hitting a missing-file
    /// guard before dispatch is even exercised.
    private func makeCapture() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("t6-reachable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wire = "{\"t\":\"hello\",\"v\":1,\"caps\":[\"status\"],\"ts\":0}\n{\"t\":\"ready\",\"ts\":1}\n"
        try wire.write(to: dir.appendingPathComponent("wire.ndjson"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func everyAnalyzeVerbIsReachable() throws {
        let dir = try makeCapture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("t6-index-\(UUID().uuidString).tsv")
        defer { try? FileManager.default.removeItem(at: output) }

        let invocations: [(verb: String, args: [String])] = [
            ("list", []),
            ("summary", [dir.path]),
            ("trace", [dir.path]),
            ("diff", [dir.path, dir.path]),
            ("rereads", [dir.path]),
            ("findings", [dir.path]),
            ("taxonomy", [dir.path]),
            ("validate", [dir.path]),
            ("report", ["/nonexistent-does-not-matter.tsv"]),
            ("index", [output.path]),
        ]
        for (verb, args) in invocations {
            let result = try run([verb] + args, cwd: dir)
            #expect(!result.stderr.contains("usage: swiftstar-eval"),
                    "\(verb) fell through to the usage message — not reachable in the dispatch registry")
        }
    }

    @Test func summariseIsRejected() throws {
        // Sibling refusal (binding rule 4): a near-miss verb name is not
        // silently accepted.
        let dir = try makeCapture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = try run(["summarise", "--latest"], cwd: dir)
        #expect(result.status == 2)
        #expect(result.stderr.contains("usage: swiftstar-eval"))
    }
}
