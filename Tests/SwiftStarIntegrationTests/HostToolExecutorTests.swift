import Testing
import Foundation
@testable import SwiftStarAppKit
@testable import SwiftStarKit

/// Item 4 (P22 cleanup): `AgentController.executeHostTool` and
/// `PoolOrchestrator.executeHostTool` were near-duplicate ~100-line
/// implementations of the same six tool families. Unified into
/// `HostToolExecutor`, parameterized by `Policy` so each call site keeps its
/// exact prior behavior. This suite pins the real, deliberate differences the
/// unification had to preserve — not just the shared logic (list/edit are
/// byte-for-byte identical between the two originals and get no dedicated
/// coverage here beyond what confirms the shared code path works at all).
///
/// No subprocess here (that's `HostToolExecutorBashTests`, integration-tier
/// gated below) — these are pure file I/O, same tier as
/// `HostToolConfinementTests`.
struct HostToolExecutorTests {
    private func makeWorkspace() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("host-tool-executor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func request(_ name: String, _ params: [ToolParam], workspace: URL, path: String? = nil) -> ToolExecutionRequest {
        ToolExecutionRequest(name: name, params: params, workspace: workspace,
                             resolvedPath: path.map { workspace.appendingPathComponent($0).path })
    }

    private func param(_ name: String, _ value: String) -> ToolParam {
        ToolParam(name: name, value: value)
    }

    // MARK: - read/more: app policy (no cache, split confinement/read errors)

    @Test func appPolicyReadReturnsFullTextEveryTime() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "hello".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)
        let req = request("read", [], workspace: ws, path: "a.txt")

        let first = executor.execute(req)
        let second = executor.execute(req)
        #expect(first.text == "hello")
        #expect(second.text == "hello", "the app policy has no read cache — a second read is not 'unchanged'")
    }

    @Test func appPolicyReadMissingFileNamesThePathInTheError() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let executor = HostToolExecutor(policy: .app)
        let result = executor.execute(request("read", [], workspace: ws, path: "missing.txt"))
        #expect(!result.ok)
        #expect(result.text.contains("missing.txt"))
    }

    @Test func appPolicyReadOutsideWorkspaceRefusesWithGrantMessage() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let executor = HostToolExecutor(policy: .app)
        let result = executor.execute(request("read", [], workspace: ws, path: nil))
        // resolvedPath nil (outside grant, per HostToolConfinement's contract
        // when the caller passes no confined path) refuses before any I/O.
        #expect(!result.ok)
        #expect(result.text.contains("outside the workspace grant"))
    }

    // MARK: - read/more: pool policy (per-turn cache, folded generic error)

    @Test func poolPolicyReadCachesAnUnchangedFile() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "hello".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .pool(vettedCommands: []))
        let req = request("read", [], workspace: ws, path: "a.txt")

        let first = executor.execute(req)
        let second = executor.execute(req)
        #expect(first.text == "hello")
        #expect(second.text == "(unchanged since last read)")
    }

    @Test func poolPolicyReadCacheInvalidatesOnChange() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let file = ws.appendingPathComponent("a.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .pool(vettedCommands: []))
        let req = request("read", [], workspace: ws, path: "a.txt")

        _ = executor.execute(req)
        try "changed".write(to: file, atomically: true, encoding: .utf8)
        let afterChange = executor.execute(req)
        #expect(afterChange.text == "changed")
    }

    @Test func poolPolicyReadMissingFileUsesGenericMessageWithNoPath() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let executor = HostToolExecutor(policy: .pool(vettedCommands: []))
        let result = executor.execute(request("read", [], workspace: ws, path: "missing.txt"))
        #expect(!result.ok)
        #expect(result.text == "error: could not read")
    }

    // MARK: - write: parent-directory creation differs

    @Test func appPolicyWriteDoesNotCreateMissingParentDirectories() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let executor = HostToolExecutor(policy: .app)
        let result = executor.execute(request(
            "write", [param("content", "x")], workspace: ws, path: "sub/dir/a.txt"))
        #expect(!result.ok, "the app policy must not silently create sub/dir/")
    }

    @Test func poolPolicyWriteCreatesMissingParentDirectories() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let executor = HostToolExecutor(policy: .pool(vettedCommands: []))
        let result = executor.execute(request(
            "write", [param("content", "x")], workspace: ws, path: "sub/dir/a.txt"))
        #expect(result.ok)
        #expect(try String(contentsOf: ws.appendingPathComponent("sub/dir/a.txt"), encoding: .utf8) == "x")
    }

    // MARK: - search: case_sensitive param + count header differ

    @Test func appPolicySearchHonorsCaseSensitiveParamAndIncludesCountHeader() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "Needle\nother".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)

        let sensitive = executor.execute(request(
            "search", [param("query", "needle")], workspace: ws, path: "."))
        #expect(sensitive.text == "No matches\n", "default case_sensitive is true")

        let insensitive = executor.execute(request(
            "search", [param("query", "needle"), param("case_sensitive", "false")], workspace: ws, path: "."))
        #expect(insensitive.text.contains("1 match shown"))
        #expect(insensitive.text.contains("Needle"))
    }

    @Test func poolPolicySearchIgnoresCaseSensitiveParamAndHasNoCountHeader() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "Needle\nother".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .pool(vettedCommands: []))

        // Even with case_sensitive:false, the pool policy stays case-sensitive
        // (it never reads the param) — matching the original PoolOrchestrator
        // executor exactly.
        let result = executor.execute(request(
            "search", [param("query", "needle"), param("case_sensitive", "false")], workspace: ws, path: "."))
        #expect(result.text == "No matches\n")

        let caseMatch = executor.execute(request(
            "search", [param("query", "Needle")], workspace: ws, path: "."))
        #expect(!caseMatch.text.contains("match"), "no count header in the pool policy")
        #expect(caseMatch.text.contains("Needle"))
    }

    // MARK: - list/edit: identical between the two originals — one smoke test
    // each confirms the shared code path works under both policies.

    @Test func listWorksIdenticallyUnderBothPolicies() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "x".write(to: ws.appendingPathComponent("z.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        for policy: HostToolExecutor.Policy in [.app, .pool(vettedCommands: [])] {
            let result = HostToolExecutor(policy: policy).execute(request("list", [], workspace: ws, path: "."))
            #expect(result.text == "a.txt\nz.txt")
        }
    }

    @Test func editWorksIdenticallyUnderBothPolicies() throws {
        for policy: HostToolExecutor.Policy in [.app, .pool(vettedCommands: [])] {
            let ws = try makeWorkspace()
            defer { try? FileManager.default.removeItem(at: ws) }
            try "hello world".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
            let result = HostToolExecutor(policy: policy).execute(request(
                "edit", [param("old", "world"), param("new", "there")], workspace: ws, path: "a.txt"))
            #expect(result.ok)
            #expect(result.mutations == [ws.appendingPathComponent("a.txt").path])
            #expect(try String(contentsOf: ws.appendingPathComponent("a.txt"), encoding: .utf8) == "hello there")
        }
    }

    // MARK: - bash_status/bash_stop: explicit refusal only under the app policy

    @Test func appPolicyRefusesBashStatusAndBashStopExplicitly() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let executor = HostToolExecutor(policy: .app)
        for name in ["bash_status", "bash_stop"] {
            let result = executor.execute(request(name, [], workspace: ws))
            #expect(!result.ok)
            #expect(result.text.contains("not yet implemented in host mode"))
        }
    }

    @Test func poolPolicyBashStatusAndBashStopFallThroughToUnknownTool() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let executor = HostToolExecutor(policy: .pool(vettedCommands: []))
        for name in ["bash_status", "bash_stop"] {
            let result = executor.execute(request(name, [], workspace: ws))
            #expect(!result.ok)
            #expect(result.text.contains("unknown tool"))
        }
    }
}
