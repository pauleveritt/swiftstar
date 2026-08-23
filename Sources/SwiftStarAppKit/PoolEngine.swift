import Foundation
import SwiftStarKit

/// The app-side pool engine (D1/D2): builds the pooled spawn argv, reads the
/// `.kv` rendered text inference-free (D6 crash-recovery backing), and the
/// deterministic loaders the packet-maker uses (D5). No SwiftUI; integration
/// tier (real Process/files). The multiplex drain and the dispatch loop live in
/// the app target (they need the scheduler + `WorktreeDispatcher`).
public enum PoolEngine {
    /// The engine argv for a pooled spawn: the existing agent argv plus
    /// `--subagent-pool N` (one orchestrator + N-1 worker sessions).
    public static func argv(settings: AgentSettings, workers: Int) -> [String] {
        AgentCommand.argv(settings: settings) + ["--subagent-pool", String(workers)]
    }

    /// Read the rendered conversation from a session `.kv` file (D6): the full
    /// text lives as plain UTF-8 behind a fixed 48-byte header. No model, no
    /// engine. Throws on a missing file or a sub-48-byte header.
    public static func readKVText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard data.count > 48 else { throw PoolEngineError.kvTooShort(data.count) }
        let body = data.dropFirst(48)
        return String(decoding: body, as: UTF8.self)
    }

    /// The deterministic file listing (D5): a sorted list of the repo's
    /// tracked files, via `git ls-files` (falls back to an empty list on a
    /// non-repo, which the packet-maker then treats as "no file list").
    public static func listFiles(in repo: URL) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "ls-files"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return [] }
        guard p.terminationStatus == 0,
              let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return [] }
        return out.split(separator: "\n").map(String.init).sorted()
    }
}

public enum PoolEngineError: Error, Equatable {
    case kvTooShort(Int)
}
