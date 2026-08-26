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

    /// Strip ephemeral worktree prefixes out of evidence text (V7).
    ///
    /// Every repair round runs in a fresh `swiftstar-wt-<UUID>` worktree, and
    /// tracebacks name it absolutely. That put a per-run UUID inside the
    /// packet, so a fixed seed produced a *different prompt* on every run and
    /// no two runs were comparable: the round-2 packets of 20260826-104811 and
    /// 20260826-112536 (same model, path style and seed) differed by exactly
    /// that line, and the first repaired where the second failed. It also
    /// defeats prompt-prefix caching and injects an absolute host path into
    /// runs whose whole purpose is a relative-vs-absolute path arm.
    ///
    /// Matches the UUID shape rather than one known URL on purpose: round 1's
    /// grade comes from the FAILED phase's worktree, not the round's own, so
    /// normalising against a single URL would miss it.
    ///
    /// The prefix is removed rather than replaced with a placeholder, which
    /// leaves `File "app.py", line 42` — the workspace-relative form the
    /// directive already tells the model its paths are in.
    public static func normalizingWorktreePaths(_ text: String) -> String {
        let marker = "swiftstar-wt-"
        guard text.contains(marker) else { return text }

        // Hand-rolled rather than NSRegularExpression: this type is deliberately
        // Foundation-free and pure.
        var out = ""
        var i = text.startIndex
        var tokenStart = text.startIndex   // start of the path token we are inside

        while i < text.endIndex {
            let c = text[i]
            if c == " " || c == "\n" || c == "\t" || c == "\"" || c == "'" {
                out.append(contentsOf: text[tokenStart...i])
                i = text.index(after: i)
                tokenStart = i
                continue
            }
            // At a marker: drop everything from the token start through the
            // segment separator that ends the worktree directory name.
            if text[i...].hasPrefix(marker) {
                var j = text.index(i, offsetBy: marker.count)
                while j < text.endIndex, text[j] != "/" {
                    let ch = text[j]
                    // A worktree name is hex and dashes; anything else means this
                    // is not a worktree path and must be left alone.
                    guard ch.isHexDigit || ch == "-" else { break }
                    j = text.index(after: j)
                }
                if j < text.endIndex, text[j] == "/" {
                    i = text.index(after: j)
                    tokenStart = i
                    continue
                }
            }
            i = text.index(after: i)
        }
        out.append(contentsOf: text[tokenStart...])
        return out
    }

    /// Strip pytest's wall-clock duration out of evidence text (V7, source 2).
    ///
    /// pytest ends its summary with `... in 0.20s` (or `in 1m 5.43s` on slower
    /// suites). That number changes on every run, so the same failing suite
    /// produced a different packet each time. Found in the 2026-08-26
    /// determinism probe: three identical fixture runs, and the entire diff
    /// between two of their packets was `in 0.20s` vs `in 0.16s`. Beyond
    /// reproducibility it breaks prompt-prefix caching for everything after it.
    ///
    /// The summary line is kept and only the number elided — how many tests
    /// failed is the signal; how long they took is noise the model cannot act on.
    public static func normalizingDurations(_ text: String) -> String {
        var out = ""
        var i = text.startIndex
        let marker = " in "

        while i < text.endIndex {
            guard text[i...].hasPrefix(marker) else {
                out.append(text[i])
                i = text.index(after: i)
                continue
            }
            var j = text.index(i, offsetBy: marker.count)
            let numberStart = j
            // <digits>[.<digits>][m ]<digits>[.<digits>]s — accept the plain and
            // the minutes form, and require the trailing `s` so ordinary prose
            // ("in 3 steps") is left alone.
            var sawDigit = false
            while j < text.endIndex {
                let c = text[j]
                if c.isNumber { sawDigit = true } else if c == "." || c == "m" || c == " " {
                    // separators inside a duration; a space is only legal after `m`
                    if c == " " && !(j > numberStart && text[text.index(before: j)] == "m") { break }
                } else { break }
                j = text.index(after: j)
            }
            guard sawDigit, j < text.endIndex, text[j] == "s",
                  text.index(after: j) == text.endIndex || !text[text.index(after: j)].isLetter else {
                out.append(text[i])
                i = text.index(after: i)
                continue
            }
            out += marker + "<elapsed>"
            i = text.index(after: j)
        }
        return out
    }

    /// Everything that varies between two runs of the same input (V7).
    /// `RepairLoop` calls this; the parts are public so each is testable alone.
    public static func normalizingEphemera(_ text: String) -> String {
        normalizingDurations(normalizingWorktreePaths(text))
    }

    /// Tail-cap a pytest run's output: the failure summary is at the end.
    /// Returns the kept text and a note when anything was dropped.
    /// Caps on UTF-8 byte length, not Character count, to respect true payload size.
    public static func cappedFailureOutput(_ output: String, cap: Int) -> (String, String?) {
        let byteCount = output.utf8.count
        guard byteCount > cap else { return (output, nil) }

        // Keep the last `cap` bytes, but don't split a multi-byte Character.
        // Walk backward from the end accumulating what we are KEEPING, and stop
        // before the next character would push us over the cap.
        //
        // The earlier version walked backward decrementing the *remaining*
        // count until it fell under the cap, then kept everything it had
        // walked past -- i.e. it kept `byteCount - cap` bytes rather than
        // `cap`. That is wrong in both directions: it under-keeps below 2x cap
        // (9018 bytes at cap 8192 kept 816) and over-keeps above it (88919
        // kept 79826, which pushed a repair packet to 37180 tokens against a
        // 32768 context and killed the one 2026-08-26 cell that had a full
        // 13-assertion failure surface to show). The old tests could not catch
        // either: they assert only `<= cap`, which an under-sized result
        // satisfies, and every input they used was below 2x cap.
        var keptBytes = 0
        var charIndex = output.endIndex

        while charIndex > output.startIndex {
            let previous = output.index(before: charIndex)
            let size = output[previous].utf8.count
            if keptBytes + size > cap { break }
            keptBytes += size
            charIndex = previous
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
