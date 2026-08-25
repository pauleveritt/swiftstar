import Foundation

/// The repair packet's machine-evidence channel (D6): pytest failure output +
/// the current writable-file contents, injected post-validation and exempt from
/// the redaction *gate* (but audited, not enforced). Constructible only from a
/// grade + worktree reads — `RepairLoop` builds it, never a packet builder.
public struct MachineEvidence: Equatable, Sendable {
    public let failureOutput: String
    public let fileContents: [String: String]
    public let truncations: [String]

    public init(failureOutput: String, fileContents: [String: String], truncations: [String] = []) {
        self.failureOutput = failureOutput
        self.fileContents = fileContents
        self.truncations = truncations
    }

    /// Tail-cap a pytest run's output: the failure summary is at the end.
    /// Returns the kept text and a note when anything was dropped.
    public static func cappedFailureOutput(_ output: String, cap: Int) -> (String, String?) {
        guard output.count > cap else { return (output, nil) }
        let kept = String(output.suffix(cap))
        return (kept, "failure output truncated: \(output.count) -> \(kept.count) bytes")
    }

    /// Cap one file's content, noting the truncation.
    public static func cappedContent(_ content: String, cap: Int) -> (String, String?) {
        guard content.count > cap else { return (content, nil) }
        let kept = String(content.prefix(cap))
        return (kept, "file content truncated: \(content.count) -> \(kept.count) bytes")
    }

    /// Non-fatal redaction audit: which redacted strings are visible in the
    /// evidence. Logged, never enforced — the answer being present in the
    /// failure output is the L1 signal, but the run should say so (D6).
    public func redactHits(_ redacts: [String]) -> [String] {
        let all = failureOutput + "\n" + fileContents.values.joined(separator: "\n")
        return redacts.filter { all.contains($0) }
    }

    /// The block appended to `taskText`, under a stable header (D6).
    public func render() -> String {
        var s = "## Failure evidence (machine output)\n\n"
        s += "Acceptance suite output (tail):\n```\n\(failureOutput)\n```\n\n"
        s += "Current contents of the files you may edit:\n\n"
        for path in fileContents.keys.sorted() {
            s += "=== \(path) ===\n\(fileContents[path] ?? "")\n\n"
        }
        if !truncations.isEmpty {
            s += "Truncations:\n" + truncations.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        return s
    }
}
