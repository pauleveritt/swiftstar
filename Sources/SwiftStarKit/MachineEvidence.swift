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
    ///
    /// Middle-truncates rather than head-truncates: a bug fix is as likely to
    /// live near the end of a file as the start (e.g. a route handler at the
    /// bottom of a small file), so keeping only the head can silently hide the
    /// very code that needs fixing. Instead this keeps roughly the first half
    /// of the cap and the last half, drops the middle, and marks the drop
    /// inline (not just in the returned note) since the rendered evidence
    /// otherwise concatenates head and tail with nothing to say a chunk of
    /// code is missing between them.
    public static func cappedContent(_ content: String, cap: Int) -> (String, String?) {
        let byteCount = content.utf8.count
        guard byteCount > cap else { return (content, nil) }

        let headCap = cap / 2
        let tailCap = cap - headCap

        // Keep the first `headCap` bytes, but don't split a multi-byte Character.
        // Walk forward from the start, accumulating byte count until we would exceed the cap.
        var headByteAccum = 0
        var headEnd = content.startIndex
        while headEnd < content.endIndex {
            let char = content[headEnd]
            let charBytes = char.utf8.count
            if headByteAccum + charBytes > headCap {
                break
            }
            headByteAccum += charBytes
            content.formIndex(after: &headEnd)
        }

        // Keep the last `tailCap` bytes, but don't split a multi-byte Character.
        // Walk backward from the end, accumulating byte count until we would exceed the cap.
        var tailByteAccum = 0
        var tailStart = content.endIndex
        while tailStart > content.startIndex {
            let priorIndex = content.index(before: tailStart)
            let char = content[priorIndex]
            let charBytes = char.utf8.count
            if tailByteAccum + charBytes > tailCap {
                break
            }
            tailByteAccum += charBytes
            tailStart = priorIndex
        }

        // For content only barely over the cap, the head and tail windows can
        // overlap; clamp so we never re-emit the same bytes twice.
        if tailStart < headEnd {
            tailStart = headEnd
        }

        let head = String(content[..<headEnd])
        let tail = String(content[tailStart...])
        let droppedBytes = byteCount - head.utf8.count - tail.utf8.count
        let marker = "\n\n<<< \(droppedBytes) bytes truncated from the middle of this file >>>\n\n"
        let kept = head + marker + tail
        let note = "file content middle truncated: kept first \(head.utf8.count) and last "
            + "\(tail.utf8.count) of \(byteCount) total bytes"
        return (kept, note)
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
