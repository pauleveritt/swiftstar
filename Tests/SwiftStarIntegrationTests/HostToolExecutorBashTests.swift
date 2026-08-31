import Testing
import Foundation
@testable import SwiftStarAppKit
@testable import SwiftStarKit

/// Item 4 (P22 cleanup): `bash`'s policy differences — the app's `.allowAny`
/// (already gated by `shellAllowed` upstream, at `ToolCallbackResponder.consent`)
/// vs. the pool worker's `.vettedOnly` allowlist — plus the sync/async
/// entry points sharing the same behavior (item 3). Real subprocesses, so
/// this suite is integration-tier gated like its siblings (`just integration`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct HostToolExecutorBashTests {
    private let ws = FileManager.default.temporaryDirectory

    private func request(_ params: [ToolParam]) -> ToolExecutionRequest {
        ToolExecutionRequest(name: "bash", params: params, workspace: ws, resolvedPath: nil)
    }

    private func param(_ name: String, _ value: String) -> ToolParam {
        ToolParam(name: name, value: value)
    }

    @Test func appPolicyRunsAnyNonEmptyCommandSync() throws {
        let executor = HostToolExecutor(policy: .app)
        let result = executor.execute(request([param("command", "echo hi")]))
        #expect(result.ok)
        #expect(result.text.contains("hi"))
        #expect(result.validationRan)
    }

    @Test func appPolicyRunsAnyNonEmptyCommandAsync() async throws {
        let executor = HostToolExecutor(policy: .app)
        let result = await executor.execute(request([param("command", "echo hi-async")]))
        #expect(result.ok)
        #expect(result.text.contains("hi-async"))
    }

    @Test func appPolicyRefusesEmptyCommand() throws {
        let executor = HostToolExecutor(policy: .app)
        let result = executor.execute(request([]))
        #expect(!result.ok)
        #expect(result.text.contains("bash requires command"))
    }

    @Test func poolPolicyAllowsExactVettedCommand() throws {
        let executor = HostToolExecutor(policy: .pool(vettedCommands: ["echo vetted"]))
        let result = executor.execute(request([param("command", "echo vetted")]))
        #expect(result.ok)
        #expect(result.text.contains("vetted"))
    }

    @Test func poolPolicyAllowsCommandWithVettedPrefix() throws {
        // The original PoolOrchestrator executor matches by prefix, not just
        // exact equality — a validation command like "pytest tests/" is
        // vetted, and "pytest tests/ -k foo" (a variant the worker might try)
        // still matches.
        let executor = HostToolExecutor(policy: .pool(vettedCommands: ["pytest tests/"]))
        let result = executor.execute(request([param("command", "pytest tests/ -k foo")]))
        #expect(result.exitStatus != nil, "the command actually ran (even though pytest itself may not exist here)")
    }

    @Test func poolPolicyRefusesUnvettedCommand() throws {
        let executor = HostToolExecutor(policy: .pool(vettedCommands: ["echo vetted"]))
        let result = executor.execute(request([param("command", "rm -rf /")]))
        #expect(!result.ok)
        #expect(result.text.contains("vetted"))
    }

    @Test func poolPolicyRefusesEmptyCommandViaVettedCheckNotTheAppMessage() throws {
        // The pool policy has no "requires command" guard (the original
        // PoolOrchestrator executor never had one) — an empty command is
        // simply not in the vetted list.
        let executor = HostToolExecutor(policy: .pool(vettedCommands: ["echo vetted"]))
        let result = executor.execute(request([]))
        #expect(!result.ok)
        #expect(result.text.contains("vetted"))
        #expect(!result.text.contains("requires command"))
    }

    @Test func bashResultDigestsStdoutOnlyNotStderr() throws {
        // Both originals hash stdout alone (a different call,
        // WorktreeDispatcher.runValidation, hashes the combined text) — pinned
        // here so the shared bashResult helper cannot silently change it.
        let executor = HostToolExecutor(policy: .app)
        let stdoutOnly = executor.execute(request([param("command", "echo same")]))
        let withStderr = executor.execute(request([param("command", "echo same; >&2 echo noise")]))
        #expect(stdoutOnly.outputDigest == withStderr.outputDigest)
    }

    @Test func syncAndAsyncBashAgreeOnResult() async throws {
        let executor = HostToolExecutor(policy: .app)
        // Explicitly typed to pin down the sync overload — inside an `async`
        // test function, an unqualified call to the overloaded `execute`
        // doesn't reliably resolve to the sync candidate.
        let syncExecute: (ToolExecutionRequest) -> ToolExecutionResult = executor.execute
        let sync = syncExecute(request([param("command", "echo hi; exit 7")]))
        let async_ = await executor.execute(request([param("command", "echo hi; exit 7")]))
        #expect(sync.ok == async_.ok)
        #expect(sync.text == async_.text)
        #expect(sync.exitStatus == async_.exitStatus)
        #expect(sync.outputDigest == async_.outputDigest)
    }

    // MARK: - P24.3: bash results are digested; test/lint are host-owned tools

    @Test func bashResultIsDigestedNotRaw() {
        let executor = HostToolExecutor(policy: .app)
        let result = executor.execute(request([param("command", "echo small-output")]))
        #expect(result.ok)
        #expect(result.text.hasPrefix("bash: exit 0 (Ran: echo small-output)"))
        #expect(result.text.contains("small-output"))
    }

    @Test func testToolRunsSwiftTestAgainstFixtureProject() throws {
        // A tiny real Swift package: resolves to `swift test`, runs it, and
        // digests the outcome. Exercised once here; the paired-bill live run
        // (Task 12) is where the decision-completeness claim is measured.
        let pkg = FileManager.default.temporaryDirectory
            .appendingPathComponent("p24-3-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pkg) }
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "Fixture", targets: [.target(name: "Fixture"), .testTarget(name: "FixtureTests", dependencies: ["Fixture"])])
        """.write(toFile: pkg.appendingPathComponent("Package.swift").path, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: pkg.appendingPathComponent("Sources/Fixture"), withIntermediateDirectories: true)
        try "public func answer() -> Int { 42 }\n".write(toFile: pkg.appendingPathComponent("Sources/Fixture/Fixture.swift").path, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: pkg.appendingPathComponent("Tests/FixtureTests"), withIntermediateDirectories: true)
        try """
        import Testing
        @testable import Fixture
        @Test func answers() { #expect(answer() == 42) }
        """.write(toFile: pkg.appendingPathComponent("Tests/FixtureTests/FixtureTests.swift").path, atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)
        let result = executor.execute(ToolExecutionRequest(
            name: "test", params: [], workspace: pkg, resolvedPath: nil))
        #expect(result.ok)
        #expect(result.text.contains("Ran: swift test"))
        #expect(result.text.contains("all passed") || result.text.contains("failures"))
        #expect(result.validationRan)
    }
}
