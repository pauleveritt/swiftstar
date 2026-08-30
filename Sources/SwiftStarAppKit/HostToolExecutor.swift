import Foundation
import CryptoKit
import SwiftStarKit

/// The unified host-tool executor (item 4, P22 cleanup): one implementation
/// backing both `AgentController`'s Agent-tab tool calls and
/// `PoolOrchestrator`'s pool-worker tool calls, previously two near-duplicate
/// ~100-line implementations sharing only `HostToolConfinement`'s
/// symlink-resolving confinement helper. Runs the six tool families
/// (`read`/`more`/`list`/`search`/`write`/`edit`/`bash`) under the
/// consent-cleared grant `ToolCallbackResponder` already produced — this type
/// does not re-check consent, only executes.
///
/// The two call sites have real, deliberate policy differences, captured in
/// `Policy` rather than dropped:
/// - the pool worker (`.pool`) confines `bash` to a vetted-commands allowlist
///   (not the app's `shellAllowed` boolean gate — that gate is enforced
///   earlier, in `ToolCallbackResponder.consent`, before `execute` ever runs)
///   and creates parent directories before `write` (a fresh worktree may not
///   have the target directory yet);
/// - the app (`.app`) `bash` just runs (already gated by `shellAllowed`
///   upstream), `search` honors a `case_sensitive` param and prefixes its
///   output with a match-count header, and `bash_status`/`bash_stop` get an
///   explicit descriptive refusal rather than falling through to "unknown
///   tool" (the pool worker is never offered those tools at all, so it never
///   needs the distinction).
///
/// P24.2 (D2): reads no longer differ by policy — the `.pool` per-turn read
/// cache was retired and both policies share one windowed read path.
///
/// Both a sync and an async `execute` are provided (item 3, P22 cleanup):
/// `PoolOrchestrator.runPhase` is a deliberately synchronous poll-loop harness
/// and uses the sync one; `AgentController` needs `bash` off the MainActor and
/// uses the async one. Only `bash` differs between them — everything else is
/// pure, synchronous file I/O either way.
public final class HostToolExecutor: @unchecked Sendable {
    public enum BashPolicy: Sendable {
        /// The app's mode: `ToolCallbackResponder.consent` already checked
        /// `shellAllowed` before `execute` was called — `bash` just runs.
        case allowAny
        /// The pool worker's mode: `bash` is confined to the packet's vetted
        /// validation/self-test commands, checked here (the worker's call site
        /// always passes `shellAllowed: true` to `respond`, trusting this gate
        /// instead of the app's boolean one).
        case vettedOnly([String])
    }

    public struct Policy: Sendable {
        public var searchSupportsCaseSensitiveParam: Bool
        public var searchIncludesCountHeader: Bool
        public var createParentDirectoriesOnWrite: Bool
        public var bash: BashPolicy
        public var explicitBashStatusStopRefusal: Bool

        public init(searchSupportsCaseSensitiveParam: Bool,
                    searchIncludesCountHeader: Bool, createParentDirectoriesOnWrite: Bool,
                    bash: BashPolicy, explicitBashStatusStopRefusal: Bool) {
            self.searchSupportsCaseSensitiveParam = searchSupportsCaseSensitiveParam
            self.searchIncludesCountHeader = searchIncludesCountHeader
            self.createParentDirectoriesOnWrite = createParentDirectoriesOnWrite
            self.bash = bash
            self.explicitBashStatusStopRefusal = explicitBashStatusStopRefusal
        }

        /// `AgentController`'s Agent-tab policy.
        public static let app = Policy(
            searchSupportsCaseSensitiveParam: true,
            searchIncludesCountHeader: true, createParentDirectoriesOnWrite: false,
            bash: .allowAny, explicitBashStatusStopRefusal: true)

        /// `PoolOrchestrator`'s pool-worker policy for one phase. Construct a
        /// fresh instance per phase (resetting the vetted-commands allowlist and
        /// the read continuation map with the instance) — `vettedCommands` is
        /// the packet's validation/self-test commands for that phase only.
        public static func pool(vettedCommands: [String]) -> Policy {
            Policy(searchSupportsCaseSensitiveParam: false,
                  searchIncludesCountHeader: false, createParentDirectoriesOnWrite: true,
                  bash: .vettedOnly(vettedCommands), explicitBashStatusStopRefusal: false)
        }
    }

    private let policy: Policy
    private let lock = NSLock()

    /// P24.1 (D5): `more` continuation per workspace root. The `.app` executor
    /// is a process-lifetime static shared by the main agent and every pool
    /// worker (`AgentPoolTurnLoop.swift:138`), so a single scalar would let a
    /// worker's read retarget the main agent's next `more`. Workers run in
    /// per-turn UUID worktrees, so roots are disjoint for free.
    private var continuations: [String: (path: String, nextLine: Int, bare: Bool, byteOffset: Int)] = [:]
    private var contextSize: Int
    /// P24.1: per-root context override. The engine tiers its read chunk off
    /// **the worker's** effective context (`agent_read_default_lines` takes
    /// `agent_worker_effective_ctx_size(w)`), and P23 gave pool workers their
    /// own, clamped to `[4096, parent]`. Because every worker shares this one
    /// `.app` executor, a scalar `contextSize` would hand a 4k worker the
    /// parent's 500-line, 7000-byte windows — half its context in one tool
    /// result, the incoherence D2 exists to prevent. Keyed by worktree root,
    /// which is already disjoint per worker (D5).
    private var contextSizeByRoot: [String: Int] = [:]

    /// `AGENT_FILE_MAX_BYTES` (`ds4_agent.c:7884`) — 16 MiB.
    static let fileMaxBytes = 16 * 1024 * 1024

    public init(policy: Policy, contextSize: Int = 32768) {
        self.policy = policy
        self.contextSize = contextSize
    }

    /// D3: the app's executor is a `static let` with no settings at type-init,
    /// so it takes its context size at session start instead of construction.
    public func setContextSize(_ n: Int) {
        lock.withLock { contextSize = n }
    }

    /// Register a pool worker's own context for reads inside its worktree, so
    /// the read tier matches the context the worker actually runs at rather
    /// than the parent's. Cleared with the rest of the read state.
    public func setContextSize(_ n: Int, forRoot root: URL) {
        let key = HostToolConfinement.realPath(root.path, workspace: root) ?? root.path
        lock.withLock { contextSizeByRoot[key] = n }
    }

    /// Clears `more` continuations and per-root context overrides. Only the
    /// app's process-lifetime static needs this; `PoolOrchestrator` gets a
    /// fresh instance per phase.
    public func resetReadState() {
        lock.withLock { continuations.removeAll(); contextSizeByRoot.removeAll() }
    }

    /// Synchronous entry point — used by `PoolOrchestrator.runPhase`, a
    /// deliberately synchronous poll-loop harness (see `SubprocessRunner`'s
    /// doc comment for why blocking there is intentional).
    public func execute(_ request: ToolExecutionRequest) -> ToolExecutionResult {
        if let result = nonBashResult(request) { return result }
        let command = bashCommand(request)
        if let refusal = bashRefusal(command) { return refusal }
        let r: SubprocessRunner.Result
        do {
            r = try SubprocessRunner.run(command, in: request.workspace)
        } catch {
            return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
        }
        return bashResult(r)
    }

    /// The async twin of `execute` (item 3, P22 cleanup): identical mapping,
    /// but awaits `SubprocessRunner`'s async `run` so `bash` never blocks the
    /// MainActor. `AgentController` uses this one.
    public func execute(_ request: ToolExecutionRequest) async -> ToolExecutionResult {
        if let result = nonBashResult(request) { return result }
        let command = bashCommand(request)
        if let refusal = bashRefusal(command) { return refusal }
        let r: SubprocessRunner.Result
        do {
            r = try await SubprocessRunner.run(command, in: request.workspace)
        } catch {
            return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
        }
        return bashResult(r)
    }

    // MARK: - everything except bash (pure, synchronous either way)

    /// Every tool family except `bash`, plus the `bash_status`/`bash_stop`
    /// refusal. Returns `nil` only for `bash` itself, which each `execute`
    /// overload runs with its own (sync or async) `SubprocessRunner.run`.
    private func nonBashResult(_ request: ToolExecutionRequest) -> ToolExecutionResult? {
        if policy.explicitBashStatusStopRefusal,
           request.name == "bash_status" || request.name == "bash_stop" {
            return ToolExecutionResult(
                ok: false,
                text: "bash_status/bash_stop are not yet implemented in host mode; use a plain bash with a short timeout")
        }
        switch request.name {
        case "read", "more":
            return readResult(request)
        case "list":
            guard let path = HostToolConfinement.realPath(request) else {
                return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
            }
            do {
                let entries = try FileManager.default.contentsOfDirectory(atPath: path)
                return ToolExecutionResult(ok: true, text: entries.sorted().joined(separator: "\n"))
            } catch {
                return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
            }
        case "search":
            return searchResult(request)
        case "write":
            return writeResult(request)
        case "edit":
            return editResult(request)
        case "bash":
            return nil
        default:
            return ToolExecutionResult(ok: false, text: "error: unknown tool \(request.name)")
        }
    }

    private func readResult(_ request: ToolExecutionRequest) -> ToolExecutionResult {
        // P24.2 (D2): one read path for both policies — windowed, in the
        // engine's format (ds4_agent.c:8102-8174), byte-budgeted so the
        // responder's condenser never has to cut it (D2). The `.pool` hash
        // cache was retired: its whole-file delivery starved the model and its
        // "(unchanged since last read)" was dishonest once delivery is
        // partial. Confinement and the read stay separate guards, each with
        // its own message (the read failure names the path).
        let root = HostToolConfinement.realPath(request.workspace.path,
                                                workspace: request.workspace)
            ?? request.workspace.path
        var windowRequest = ReadWindowRequest(
            startLine: intParam(request, "start_line") ?? 1,
            maxLines: intParam(request, "max_lines"),
            whole: boolParam(request, "whole"),
            raw: boolParam(request, "raw"))
        let path: String

        if request.name == "more" {
            // D4: `more` continues; it never re-reads. Consent defaults its
            // missing `path` to the workspace root, so the recorded
            // continuation — not `resolvedPath` — is the authority.
            guard let c = lock.withLock({ continuations[root] }) else {
                return ToolExecutionResult(ok: false,
                    text: "error: no previous output to continue")
            }
            path = c.path
            windowRequest = ReadWindowRequest(
                startLine: c.nextLine,
                maxLines: intParam(request, "count"),
                whole: false, raw: c.bare,
                startByteOffset: c.byteOffset)
        } else {
            guard let p = HostToolConfinement.realPath(request) else {
                return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
            }
            path = p
        }

        // Engine parity (`agent_read_file_bytes`): refuse a file over
        // AGENT_FILE_MAX_BYTES rather than loading it. The host had no cap, so
        // a huge file was read wholly into memory before windowing ever ran.
        if let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int,
           size > Self.fileMaxBytes {
            return ToolExecutionResult(ok: false,
                text: "error: file too large: \(path) exceeds \(Self.fileMaxBytes) bytes")
        }
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return ToolExecutionResult(ok: false, text: "error: could not read \(path)")
        }
        let ctx = lock.withLock { contextSizeByRoot[root] ?? contextSize }
        let window = ReadWindow.render(
            text: text, path: path, request: windowRequest,
            defaultLines: ReadWindow.defaultLines(contextSize: ctx),
            byteBudget: ReadWindow.byteBudget(contextSize: ctx))
        lock.withLock {
            // Mirrors agent_worker_set_more (ds4_agent.c:8167-8170): record on
            // a truncated read, CLEAR at EOF so a later `more` refuses honestly.
            if let next = window.nextLine {
                continuations[root] = (path: path, nextLine: next,
                                       bare: windowRequest.raw,
                                       byteOffset: window.nextByteOffset ?? 0)
            } else {
                continuations.removeValue(forKey: root)
            }
        }
        return ToolExecutionResult(ok: true, text: window.text)
    }

    private func intParam(_ r: ToolExecutionRequest, _ name: String) -> Int? {
        r.params.first(where: { $0.name == name }).flatMap { Int($0.value) }
    }

    /// Mirrors `agent_parse_bool_default` (`ds4_agent.c`): true/yes/1 and
    /// false/no/0, case-insensitively, anything else the caller's default.
    /// Accepting only "true"/"1" made `whole: "yes"` a silent no-op — a second
    /// contract behind one tool name (D1).
    private func boolParam(_ r: ToolExecutionRequest, _ name: String,
                           default def: Bool = false) -> Bool {
        guard let v = r.params.first(where: { $0.name == name })?.value,
              !v.isEmpty else { return def }
        switch v.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return def
        }
    }

    private func searchResult(_ request: ToolExecutionRequest) -> ToolExecutionResult {
        guard let path = HostToolConfinement.realPath(request) else {
            return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
        }
        let query = request.params.first(where: { $0.name == "query" })?.value ?? ""
        var caseSensitive = true
        if policy.searchSupportsCaseSensitiveParam,
           let v = request.params.first(where: { $0.name == "case_sensitive" })?.value {
            caseSensitive = v != "false" && v != "0"
        }
        let matches = Self.searchRecursive(root: path, query: query, caseSensitive: caseSensitive, maxResults: 50)
        if matches.isEmpty {
            return ToolExecutionResult(ok: true, text: "No matches\n")
        }
        guard policy.searchIncludesCountHeader else {
            return ToolExecutionResult(ok: true, text: matches.joined(separator: "\n"))
        }
        let header = "\(matches.count) match\(matches.count == 1 ? "" : "es") shown\n\n"
        return ToolExecutionResult(ok: true, text: header + matches.joined(separator: "\n"))
    }

    private func writeResult(_ request: ToolExecutionRequest) -> ToolExecutionResult {
        guard let path = HostToolConfinement.realPath(request) else {
            return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
        }
        let content = request.params.first(where: { $0.name == "content" })?.value ?? ""
        do {
            if policy.createParentDirectoriesOnWrite {
                let url = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return ToolExecutionResult(ok: true, text: "wrote \(path)", mutations: [path])
        } catch {
            return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
        }
    }

    private func editResult(_ request: ToolExecutionRequest) -> ToolExecutionResult {
        guard let path = HostToolConfinement.realPath(request) else {
            return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
        }
        let old = request.params.first(where: { $0.name == "old" })?.value ?? ""
        let new = request.params.first(where: { $0.name == "new" })?.value ?? ""
        guard !old.isEmpty else {
            return ToolExecutionResult(ok: false, text: "error: edit requires non-empty old text")
        }
        guard let data = FileManager.default.contents(atPath: path),
              var text = String(data: data, encoding: .utf8) else {
            return ToolExecutionResult(ok: false, text: "error: could not read \(path)")
        }
        guard let range = text.range(of: old) else {
            return ToolExecutionResult(ok: false, text: "error: old text not found in \(path)")
        }
        text.replaceSubrange(range, with: new)
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            return ToolExecutionResult(ok: true, text: "edited \(path)", mutations: [path])
        } catch {
            return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
        }
    }

    // MARK: - bash (the only case needing sync/async duplication)

    private func bashCommand(_ request: ToolExecutionRequest) -> String {
        request.params.first(where: { $0.name == "command" })?.value ?? ""
    }

    /// The bash gate, evaluated before running anything: the app's
    /// non-empty-command check (`.allowAny`) or the pool worker's
    /// vetted-commands allowlist (`.vettedOnly`). Returns the refusal, or nil
    /// to proceed.
    private func bashRefusal(_ command: String) -> ToolExecutionResult? {
        switch policy.bash {
        case .allowAny:
            guard !command.isEmpty else {
                return ToolExecutionResult(ok: false, text: "error: bash requires command")
            }
            return nil
        case .vettedOnly(let vetted):
            let allowed = vetted.contains { command == $0 || command.hasPrefix($0) }
            guard allowed else {
                return ToolExecutionResult(
                    ok: false, text: "error: bash is limited to the vetted validation/self-test commands")
            }
            return nil
        }
    }

    /// Assemble the `bash` result from a finished `SubprocessRunner.Result`:
    /// stdout+stderr concatenated (no separator — matches both originals),
    /// digested over stdout alone (also matches both originals; validation's
    /// combined digest lives in `WorktreeDispatcher.runValidation`, a
    /// different call entirely).
    private func bashResult(_ r: SubprocessRunner.Result) -> ToolExecutionResult {
        let combined = r.stdout + (r.stderr.isEmpty ? "" : r.stderr)
        let digest = "sha256:" + SHA256.hash(data: Data(r.stdout.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return ToolExecutionResult(
            ok: r.exit == 0 && !r.timedOut,
            text: combined,
            exitStatus: Int(r.exit),
            outputDigest: digest, validationRan: true)
    }

    /// Recursive grep for `search`: walks `root` depth-first, reads each
    /// regular file as UTF-8, and collects `path:lineNo:line` for lines
    /// containing `query` (substring; case-sensitive unless `caseSensitive` is
    /// false), capped at `maxResults` matches. Skips unreadable/binary files.
    private static func searchRecursive(
        root: String, query: String, caseSensitive: Bool, maxResults: Int
    ) -> [String] {
        guard !query.isEmpty else { return [] }
        let fm = FileManager.default
        var results: [String] = []
        let enumerator = fm.enumerator(atPath: root)
        while let entry = enumerator?.nextObject() as? String {
            if results.count >= maxResults { break }
            let full = (root as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir),
                  !isDir.boolValue else { continue }
            guard let data = fm.contents(atPath: full),
                  let text = String(data: data, encoding: .utf8) else { continue }
            let needle = caseSensitive ? query : query.lowercased()
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if results.count >= maxResults { break }
                let hay = caseSensitive ? String(line) : String(line).lowercased()
                if hay.contains(needle) {
                    results.append("\(entry):\(i + 1):\(line)")
                }
            }
        }
        return results
    }
}
