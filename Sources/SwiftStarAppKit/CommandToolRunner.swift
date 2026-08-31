import Foundation
import SwiftStarKit

/// The run/archive/assemble glue for the run+digest family. Runs a fixed,
/// host-derived command, writes the full output to `.swiftstar/runs/`, calls
/// the pure digester, assembles the `ToolExecutionResult`. `assemble` is the
/// single place that logic lives — shared by the sync/async run paths and by
/// `HostToolExecutor`'s re-scoped `bash` (Task 9).
public enum CommandToolRunner {
    public enum ToolKind: Sendable {
        case test, lint, bash
    }

    public static func runsDir(for workspace: URL) -> URL {
        workspace.appendingPathComponent(".swiftstar/runs")
    }

    /// Writes the artifact, prunes to the last 20 per tool, digests, assembles.
    /// Total: an artifact write failure still yields the digest (without the
    /// pointer) rather than an error.
    public static func assemble(out: CommandOutput, command: String, kind: ToolKind,
                                runsDir: URL) -> ToolExecutionResult {
        let content = out.stdout + out.stderr
        let contentSha = ToolDigest.sha256(content)
        let path = runsDir.appendingPathComponent("\(kindName(kind))-\(contentSha).log")
        var artifactPath = path.path
        do {
            try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
            try content.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            artifactPath = ""
        }
        prune(runsDir: runsDir, kind: kind, keep: 20)
        let digest = digest(out, command: command, artifactPath: artifactPath, kind: kind)
        let ok: Bool
        switch kind {
        case .bash:
            ok = out.exit == 0 && !out.timedOut
        case .test, .lint:
            // "ran" — failures live in the digest + exitStatus; ok:false is
            // reserved for could-not-run (timeout, or exit 127 = not found).
            ok = !out.timedOut && out.exit != 127
        }
        return ToolExecutionResult(ok: ok, text: digest.summary,
                                   exitStatus: Int(out.exit),
                                   outputDigest: digest.outputDigest,
                                   validationRan: true)
    }

    public static func runTest(selector: String?, workspace: URL) -> ToolExecutionResult {
        runTest(selector: selector, workspace: workspace, run: { try SubprocessRunner.run($0, in: workspace) })
    }

    public static func runTest(selector: String?, workspace: URL) async -> ToolExecutionResult {
        await runTest(selector: selector, workspace: workspace, run: { try await SubprocessRunner.run($0, in: workspace) })
    }

    public static func runLint(workspace: URL) -> ToolExecutionResult {
        runLint(workspace: workspace, run: { try SubprocessRunner.run($0, in: workspace) })
    }

    public static func runLint(workspace: URL) async -> ToolExecutionResult {
        await runLint(workspace: workspace, run: { try await SubprocessRunner.run($0, in: workspace) })
    }

    /// `bash` runs the model's (already policy-admitted) command; only the
    /// OUTPUT is digested. The model never names a command for test/lint, but
    /// bash is the arbitrary shell tool and keeps its command param.
    public static func runBash(command: String, workspace: URL) -> ToolExecutionResult {
        runBash(command: command, workspace: workspace, run: { try SubprocessRunner.run($0, in: workspace) })
    }

    public static func runBash(command: String, workspace: URL) async -> ToolExecutionResult {
        await runBash(command: command, workspace: workspace, run: { try await SubprocessRunner.run($0, in: workspace) })
    }

    // MARK: - shared plumbing

    private static func runTest(selector: String?, workspace: URL,
                                run: (String) throws -> SubprocessRunner.Result) -> ToolExecutionResult {
        guard let base = ProjectCommandResolver.testCommand(in: workspace) else {
            return refusal("no `Package.swift` or `pyproject.toml` in workspace")
        }
        if let selector, !ProjectCommandResolver.isValidSelector(selector) {
            return refusal("refused: selector may only contain [A-Za-z0-9_./:-]")
        }
        let command = selector.map { "\(base) \($0)" } ?? base
        return runAndAssemble(command: command, kind: .test, workspace: workspace, run: run)
    }

    private static func runTest(selector: String?, workspace: URL,
                                run: (String) async throws -> SubprocessRunner.Result) async -> ToolExecutionResult {
        guard let base = ProjectCommandResolver.testCommand(in: workspace) else {
            return refusal("no `Package.swift` or `pyproject.toml` in workspace")
        }
        if let selector, !ProjectCommandResolver.isValidSelector(selector) {
            return refusal("refused: selector may only contain [A-Za-z0-9_./:-]")
        }
        let command = selector.map { "\(base) \($0)" } ?? base
        return await runAndAssemble(command: command, kind: .test, workspace: workspace, run: run)
    }

    private static func runLint(workspace: URL,
                                run: (String) throws -> SubprocessRunner.Result) -> ToolExecutionResult {
        guard let command = ProjectCommandResolver.lintCommand(in: workspace) else {
            return refusal("no ruff target (`pyproject.toml`, `.ruff.toml`, `ruff.toml`) in workspace")
        }
        return runAndAssemble(command: command, kind: .lint, workspace: workspace, run: run)
    }

    private static func runLint(workspace: URL,
                                run: (String) async throws -> SubprocessRunner.Result) async -> ToolExecutionResult {
        guard let command = ProjectCommandResolver.lintCommand(in: workspace) else {
            return refusal("no ruff target (`pyproject.toml`, `.ruff.toml`, `ruff.toml`) in workspace")
        }
        return await runAndAssemble(command: command, kind: .lint, workspace: workspace, run: run)
    }

    private static func runBash(command: String, workspace: URL,
                                run: (String) throws -> SubprocessRunner.Result) -> ToolExecutionResult {
        runAndAssemble(command: command, kind: .bash, workspace: workspace, run: run)
    }

    private static func runBash(command: String, workspace: URL,
                                run: (String) async throws -> SubprocessRunner.Result) async -> ToolExecutionResult {
        await runAndAssemble(command: command, kind: .bash, workspace: workspace, run: run)
    }

    private static func runAndAssemble(command: String, kind: ToolKind, workspace: URL,
                                       run: (String) throws -> SubprocessRunner.Result) -> ToolExecutionResult {
        do {
            let r = try run(command)
            let out = CommandOutput(stdout: r.stdout, stderr: r.stderr, exit: r.exit, timedOut: r.timedOut)
            return assemble(out: out, command: command, kind: kind, runsDir: runsDir(for: workspace))
        } catch {
            return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
        }
    }

    private static func runAndAssemble(command: String, kind: ToolKind, workspace: URL,
                                       run: (String) async throws -> SubprocessRunner.Result) async -> ToolExecutionResult {
        do {
            let r = try await run(command)
            let out = CommandOutput(stdout: r.stdout, stderr: r.stderr, exit: r.exit, timedOut: r.timedOut)
            return assemble(out: out, command: command, kind: kind, runsDir: runsDir(for: workspace))
        } catch {
            return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
        }
    }

    private static func digest(_ out: CommandOutput, command: String, artifactPath: String,
                               kind: ToolKind) -> ToolDigest {
        switch kind {
        case .test: return TestDigest.digest(out, command: command, artifactPath: artifactPath)
        case .lint: return RuffDigest.digest(out, command: command, artifactPath: artifactPath)
        case .bash: return BashDigest.digest(out, command: command, artifactPath: artifactPath)
        }
    }

    private static func kindName(_ kind: ToolKind) -> String {
        switch kind {
        case .test: return "test"
        case .lint: return "lint"
        case .bash: return "bash"
        }
    }

    /// Keep the newest `keep` artifacts per tool (content-addressed names make
    /// the newest-K filter deterministic: sort by modification date).
    private static func prune(runsDir: URL, kind: ToolKind, keep: Int) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: runsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let prefix = kindName(kind) + "-"
        let sorted = entries
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { ($0.contentModificationDate ?? .distantPast) > ($1.contentModificationDate ?? .distantPast) }
        if sorted.count > keep {
            for stale in sorted.dropFirst(keep) { try? FileManager.default.removeItem(at: stale) }
        }
    }

    private static func refusal(_ reason: String) -> ToolExecutionResult {
        ToolExecutionResult(ok: false, text: "error: \(reason)")
    }
}

private extension URL {
    var contentModificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
