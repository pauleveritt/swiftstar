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

    @Test func appPolicyReadRendersTheEngineWindowFormat() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "hello".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)
        let req = request("read", [], workspace: ws, path: "a.txt")

        let first = executor.execute(req)
        let second = executor.execute(req)
        #expect(first.text.hasSuffix(": lines 1-1 of 1\n1 hello\n"))
        #expect(second.text == first.text,
                "the app policy has no read cache — a second read serves the same window")
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

    // MARK: - P24.1 windowed reads and `more` continuation

    /// n lines, "l1".."ln", at `big.txt` in `ws`.
    private func writeLines(_ n: Int, _ ws: URL, prefix: String = "l") throws {
        let text = (1...n).map { "\(prefix)\($0)" }.joined(separator: "\n") + "\n"
        try text.write(to: ws.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
    }

    @Test func readHonorsStartLineAndMaxLines() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try writeLines(40, ws)
        let executor = HostToolExecutor(policy: .app)
        let r = executor.execute(request("read",
            [param("start_line", "10"), param("max_lines", "3")],
            workspace: ws, path: "big.txt"))
        #expect(r.ok)
        #expect(r.text.contains("lines 10-12 of 40; continue_offset=13;"))
        #expect(r.text.contains("10 l10\n11 l11\n12 l12\n"))
        #expect(!r.text.contains("13 l13"))
    }

    @Test func moreContinuesFromTheContinueOffset() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try writeLines(40, ws)
        let executor = HostToolExecutor(policy: .app)
        _ = executor.execute(request("read",
            [param("start_line", "1"), param("max_lines", "5")],
            workspace: ws, path: "big.txt"))
        let more = executor.execute(request("more", [param("count", "5")],
            workspace: ws, path: nil))
        #expect(more.ok)
        #expect(more.text.contains("lines 6-10 of 40"))
        #expect(more.text.contains("6 l6\n"))
        #expect(!more.text.contains("5 l5\n"), "no line may repeat across the seam")
    }

    @Test func readingToEOFClearsTheContinuation() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "hello".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)
        _ = executor.execute(request("read", [], workspace: ws, path: "a.txt"))
        let more = executor.execute(request("more", [], workspace: ws, path: nil))
        #expect(!more.ok)
        #expect(more.text.contains("no previous output to continue"))
    }

    @Test func moreWithNoPriorReadErrors() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        let executor = HostToolExecutor(policy: .app)
        let more = executor.execute(request("more", [], workspace: ws, path: nil))
        #expect(!more.ok)
        #expect(more.text.contains("no previous output to continue"))
    }

    /// D5: the `.app` executor is shared by the main agent and pool workers, so
    /// continuation state must be keyed by workspace root. A single scalar
    /// fails this test.
    @Test func continuationsAreKeyedPerWorkspaceRoot() throws {
        let wsA = try makeWorkspace(), wsB = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: wsA)
                try? FileManager.default.removeItem(at: wsB) }
        try writeLines(40, wsA)
        try writeLines(40, wsB, prefix: "b")
        let executor = HostToolExecutor(policy: .app)

        _ = executor.execute(request("read", [param("max_lines", "5")], workspace: wsA, path: "big.txt"))
        _ = executor.execute(request("read", [param("max_lines", "5")], workspace: wsB, path: "big.txt"))
        let moreA = executor.execute(request("more", [param("count", "2")], workspace: wsA, path: nil))
        #expect(moreA.text.contains("6 l6"), "A's `more` must continue A's file, not B's")
        #expect(!moreA.text.contains("b6"))
    }

    @Test func resetReadStateClearsContinuations() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try writeLines(40, ws)
        let executor = HostToolExecutor(policy: .app)
        _ = executor.execute(request("read", [param("max_lines", "5")], workspace: ws, path: "big.txt"))
        executor.resetReadState()
        let more = executor.execute(request("more", [], workspace: ws, path: nil))
        #expect(!more.ok)
        #expect(more.text.contains("no previous output to continue"))
    }

    @Test func contextSizeSelectsTheEngineTier() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try writeLines(200, ws)
        // 8192 → the engine's 120-line tier, so a 200-line file truncates.
        let small = HostToolExecutor(policy: .app, contextSize: 8192)
        #expect(small.execute(request("read", [], workspace: ws, path: "big.txt"))
            .text.contains("lines 1-120 of 200; continue_offset=121;"))
        // 32768 → the 500-line tier, so the same file reaches EOF.
        let large = HostToolExecutor(policy: .app, contextSize: 32768)
        #expect(large.execute(request("read", [], workspace: ws, path: "big.txt"))
            .text.contains("lines 1-200 of 200\n"))
        // setContextSize is the app's path (its executor is a `static let`).
        small.setContextSize(32768)
        #expect(small.execute(request("read", [], workspace: ws, path: "big.txt"))
            .text.contains("lines 1-200 of 200\n"))
    }

    /// A pool worker at its own (smaller) context must get its own read tier,
    /// not the parent's — the executor is shared, so a scalar context would
    /// hand a 4k worker the parent's 500-line windows.
    @Test func perRootContextOverridesTheParentTier() throws {
        let parent = try makeWorkspace(), worker = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: parent)
                try? FileManager.default.removeItem(at: worker) }
        try writeLines(200, parent)
        try writeLines(200, worker)
        let executor = HostToolExecutor(policy: .app, contextSize: 32768)
        executor.setContextSize(4096, forRoot: worker)   // 120-line tier

        #expect(executor.execute(request("read", [], workspace: parent, path: "big.txt"))
            .text.contains("lines 1-200 of 200\n"), "the parent keeps the 500-line tier")
        #expect(executor.execute(request("read", [], workspace: worker, path: "big.txt"))
            .text.contains("lines 1-120 of 200; continue_offset=121;"),
            "the worker root uses its own 120-line tier")

        executor.resetReadState()
        #expect(executor.execute(request("read", [], workspace: worker, path: "big.txt"))
            .text.contains("lines 1-200 of 200\n"), "reset clears per-root overrides")
    }

    /// Sibling success for the two refusal tests above (BRIEF rule 4).
    @Test func readOutsideGrantStillRefusesAndInsideStillServes() throws {
        let ws = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }
        try "hello".write(to: ws.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let executor = HostToolExecutor(policy: .app)
        let refused = executor.execute(request("read", [], workspace: ws, path: nil))
        #expect(!refused.ok)
        #expect(refused.text.contains("outside the workspace grant"))
        #expect(executor.execute(request("read", [], workspace: ws, path: "a.txt")).ok)
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
