import Foundation

/// Digests arbitrary shell output. "Never raw" means never an unbounded dump:
/// output that fits `inlineLimit` is shown whole (it is small, so showing it
/// is honest); larger output becomes a condenser-style head/tail plus the
/// artifact pointer. Total over `CommandOutput`.
public enum BashDigest {
    /// Combined output (UTF-8 bytes) shown inline before the artifact pointer
    /// takes over.
    static let inlineLimit = 4000

    public static func digest(_ out: CommandOutput, command: String, artifactPath: String) -> ToolDigest {
        let status = out.timedOut ? "bash: timed out" : "bash: exit \(out.exit)"
        let combined = out.stdout + out.stderr
        let body: String
        if combined.utf8.count <= inlineLimit {
            body = combined
        } else {
            body = ToolResultCondenser.condense(combined, limit: 6000)
                + "\nfull output: \(artifactPath)"
        }
        let summary = "\(status) (Ran: \(command))\n\(body)"
        return ToolDigest(summary: summary, command: command,
                          artifactPath: artifactPath,
                          outputDigest: ToolDigest.sha256(out.stdout))
    }
}
