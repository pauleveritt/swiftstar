import Testing
import Foundation
@testable import SwiftStarAppKit
@testable import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct CommandToolRunnerTests {
    private func tmpWorkspace() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("p24-3-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func assembleWritesArtifactAndDigests() throws {
        let ws = try tmpWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let runs = CommandToolRunner.runsDir(for: ws)
        let out = CommandOutput(stdout: "ok\n", stderr: "", exit: 0, timedOut: false)
        let result = CommandToolRunner.assemble(out: out, command: "echo ok", kind: .bash, runsDir: runs)
        #expect(result.ok)
        #expect(result.validationRan)
        #expect(result.outputDigest == ToolDigest.sha256("ok\n"))
        let written = try FileManager.default.contentsOfDirectory(atPath: runs.path)
        #expect(written.count == 1)
        #expect(written[0].hasPrefix("bash-"))
        let content = try String(contentsOfFile: runs.appendingPathComponent(written[0]).path)
        #expect(content == "ok\n")
    }

    @Test func testKindOkIsRanNotCommandSuccess() throws {
        let ws = try tmpWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let runs = CommandToolRunner.runsDir(for: ws)
        // exit 1 = failing tests = a successful RUN for test/lint (ok true);
        // bash keeps exit==0 semantics (sibling: the same input, kind .bash).
        let out = CommandOutput(stdout: "", stderr: "", exit: 1, timedOut: false)
        let asTest = CommandToolRunner.assemble(out: out, command: "swift test", kind: .test, runsDir: runs)
        #expect(asTest.ok)
        #expect(asTest.exitStatus == 1)
        let asBash = CommandToolRunner.assemble(out: out, command: "false", kind: .bash, runsDir: runs)
        #expect(!asBash.ok)
    }

    @Test func runTestRefusesWhenNoProject() throws {
        let ws = try tmpWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let result = CommandToolRunner.runTest(selector: nil, workspace: ws)
        #expect(!result.ok)
        #expect(result.text.contains("no `Package.swift` or `pyproject.toml`"))
    }

    @Test func runTestRefusesShellMetacharacterSelector() throws {
        let ws = try tmpWorkspace()
        try "dummy".write(toFile: ws.appendingPathComponent("Package.swift").path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ws) }
        let result = CommandToolRunner.runTest(selector: "a; rm -rf /", workspace: ws)
        #expect(!result.ok)
        #expect(result.text.contains("selector may only contain"))
    }

    @Test func runBashDigestsRealSubprocessOutput() throws {
        let ws = try tmpWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let result = CommandToolRunner.runBash(command: "echo dig-me", workspace: ws)
        #expect(result.ok)
        #expect(result.text.contains("dig-me"))
        #expect(result.text.contains("(Ran: echo dig-me)"))
        #expect(result.validationRan)
    }
}
