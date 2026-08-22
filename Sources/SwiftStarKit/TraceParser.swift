import Foundation

/// One parsed event from the engine's `--trace` side-channel. `.ignored` carries
/// the raw line for anything not modelled — the trace is a diagnostic side-channel,
/// so unknown lines are never a refusal (unlike the handshake-guarded wire).
public enum TraceEvent: Equatable, Sendable {
    case compaction(reason: String, old: Int, new: Int, tailStart: Int, tail: Int)
    case prefillSync(prompt: Int, cached: Int, suffix: Int, rc: Int, ms: Double)
    case ignored(String)
}

/// Streaming parser for the `--trace` file, shaped like `WireEventParser`. Feed
/// one line; it returns a typed event or nil. Trace timestamps are deliberately
/// not carried — the analyzer's findings are session-level and trace-internal
/// order suffices.
public struct TraceParser: Sendable {
    public init() {}

    public mutating func feed(_ line: String) -> TraceEvent? {
        let message = Self.stripTimestamp(line)
        guard !message.isEmpty else { return nil }
        if message.hasPrefix("compacted reason=") {
            return Self.parseCompaction(message)
        }
        if message.hasPrefix("prefill sync done ") {
            return Self.parsePrefillSync(message)
        }
        return .ignored(line)
    }

    /// Trace lines are "<YYYY-MM-DD HH:MM:SS.mmm> <message>" (agent_trace_time,
    /// 23 chars + one space). Anything that is not that shape passes through whole.
    static func stripTimestamp(_ line: String) -> String {
        let a = Array(line)
        guard a.count > 24, a[4] == "-", a[7] == "-", a[10] == " ",
              a[13] == ":", a[16] == ":", a[19] == ".", a[23] == " " else { return line }
        return String(line.dropFirst(24))
    }

    /// `compacted reason="<escaped>" old=<n> new=<n> tail_start=<n> tail=<n>`
    static func parseCompaction(_ message: String) -> TraceEvent? {
        let prefix = "compacted reason=\""
        guard message.hasPrefix(prefix) else { return nil }
        let body = Array(message.dropFirst(prefix.count))
        var reason = ""
        var i = 0
        while i < body.count {
            if body[i] == "\\", i + 1 < body.count {
                let c = body[i + 1]
                switch c {
                case "n": reason.append("\n")
                case "r": reason.append("\r")
                case "t": reason.append("\t")
                default: reason.append(c)
                }
                i += 2
            } else if body[i] == "\"" {
                i += 1
                break
            } else {
                reason.append(body[i])
                i += 1
            }
        }
        let rest = String(body[i...])
        guard let old = Self.intField(rest, "old"),
              let new = Self.intField(rest, "new"),
              let tailStart = Self.intField(rest, "tail_start"),
              let tail = Self.intField(rest, "tail") else { return nil }
        return .compaction(reason: reason, old: old, new: new, tailStart: tailStart, tail: tail)
    }

    /// `prefill sync done [tool_round=<n>] prompt=<n> cached=<n> suffix=<n> rc=<n> <ms> ms`
    /// (`tool_round` is present in the agent turn loop, `ds4_agent.c:12071`, and absent
    /// at the older sync site `:5622` — both parse.)
    static func parsePrefillSync(_ message: String) -> TraceEvent? {
        guard let prompt = Self.intField(message, "prompt"),
              let cached = Self.intField(message, "cached"),
              let suffix = Self.intField(message, "suffix"),
              let rc = Self.intField(message, "rc") else { return nil }
        let ms = Self.millisField(message) ?? 0
        return .prefillSync(prompt: prompt, cached: cached, suffix: suffix, rc: rc, ms: ms)
    }

    /// First numeric run after the first occurrence of `key=`.
    static func intField(_ s: String, _ key: String) -> Int? {
        guard let r = s.range(of: " \(key)=") ?? s.range(of: "\(key)=") else { return nil }
        var v = ""
        for ch in s[r.upperBound...] {
            if ch.isNumber { v.append(ch) } else { break }
        }
        return Int(v)
    }

    /// The numeric token immediately before the trailing " ms".
    static func millisField(_ s: String) -> Double? {
        guard let r = s.range(of: " ms") else { return nil }
        let before = s[..<r.lowerBound]
        var v = ""
        for ch in before.reversed() {
            if ch.isNumber || ch == "." { v.append(ch) } else { break }
        }
        return Double(String(v.reversed()))
    }
}
