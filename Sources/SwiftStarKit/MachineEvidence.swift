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
    /// Caps on UTF-8 byte length, not Character count, to respect true payload size.
    public static func cappedFailureOutput(_ output: String, cap: Int) -> (String, String?) {
        let byteCount = output.utf8.count
        guard byteCount > cap else { return (output, nil) }

        // Keep the last `cap` bytes, but don't split a multi-byte Character.
        // Walk backward from the end, accumulating byte count until we exceed the cap.
        var byteIndex = byteCount
        var charIndex = output.endIndex

        while byteIndex > cap && charIndex > output.startIndex {
            output.formIndex(before: &charIndex)
            let char = output[charIndex]
            byteIndex -= char.utf8.count
        }

        let kept = String(output[charIndex...])
        return (kept, "failure output truncated: \(byteCount) -> \(kept.utf8.count) bytes")
    }

    /// Cap one file's content, noting the truncation.
    /// Caps on UTF-8 byte length, not Character count, to respect true payload size.
    public static func cappedContent(_ content: String, cap: Int) -> (String, String?) {
        let byteCount = content.utf8.count
        guard byteCount > cap else { return (content, nil) }

        // Keep the first `cap` bytes, but don't split a multi-byte Character.
        // Walk forward from the start, accumulating byte count until we would exceed the cap.
        var byteAccum = 0
        var charIndex = content.startIndex

        while charIndex < content.endIndex {
            let char = content[charIndex]
            let charBytes = char.utf8.count
            if byteAccum + charBytes > cap {
                break
            }
            byteAccum += charBytes
            content.formIndex(after: &charIndex)
        }

        let kept = String(content[..<charIndex])
        return (kept, "file content truncated: \(byteCount) -> \(kept.utf8.count) bytes")
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
