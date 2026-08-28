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

    /// Parse a `--trace` file's bytes lossily. The engine's token-dump lines
    /// embed raw bytes, and a truncated multibyte sequence is a real
    /// occurrence (verified: `captures/live/20260827-200648/agent.trace`
    /// carries `text=" \xe2\x8c"` at byte 246,007), so an all-or-nothing
    /// `String(contentsOf:encoding:.utf8)` read returns nil and the whole file
    /// is silently dropped — the analyzer reports "no trace" and Σsuffix 0 for
    /// a session with 28 real prefill syncs. Malformed subsequences become
    /// U+FFFD; every other line still parses.
    public static func parse(data: Data) -> [TraceEvent] {
        let text = String(decoding: data, as: UTF8.self)
        var parser = TraceParser()
        var events: [TraceEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let event = parser.feed(s) { events.append(event) }
        }
        return events
    }

    /// Convenience over a trace file URL (the `swiftstar-analyze` CLI and the
    /// app's Diagnostics both read from disk): missing/unreadable files yield
    /// an empty array, never a crash.
    public static func read(url: URL) -> [TraceEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return parse(data: data)
    }
}

/// Whole-run token totals from every `.prefillSync` event in a `--trace` file
/// (P12.7 piece 2): the three fields the engine itself reports, summed
/// verbatim across every phase and tool round — never derived (e.g. suffix is
/// NOT computed as prompt - cached; it is the engine's own reported value,
/// summed). Deliberately excludes "stateful tokens" (Σprompt - final
/// ctx_used): that requires attributing a single ctx_used across multiple
/// independent pooled `WorkerId` sessions, an open design question left to a
/// later phase of P12.7 (see docs/superpowers/plans/2026-08-24-p12-reliable-agency.md,
/// section "### P12.7").
public struct TraceTokenTotals: Equatable, Sendable {
    public var sumPrompt: Int
    public var sumCached: Int
    public var sumSuffix: Int

    public init(sumPrompt: Int = 0, sumCached: Int = 0, sumSuffix: Int = 0) {
        self.sumPrompt = sumPrompt
        self.sumCached = sumCached
        self.sumSuffix = sumSuffix
    }
}

public enum TraceSummary {
    /// Sums every `.prefillSync` event's `prompt`/`cached`/`suffix` fields.
    /// Non-`.prefillSync` events (compaction, ignored) are skipped. An empty
    /// or all-non-sync input yields all-zero totals — never a crash — so a
    /// short run or a missing/empty trace file never fails a run that would
    /// otherwise have succeeded.
    public static func sum(events: [TraceEvent]) -> TraceTokenTotals {
        var totals = TraceTokenTotals()
        for event in events {
            guard case .prefillSync(let prompt, let cached, let suffix, _, _) = event else { continue }
            totals.sumPrompt += prompt
            totals.sumCached += cached
            totals.sumSuffix += suffix
        }
        return totals
    }

    /// Convenience over raw `--trace` file text: feeds every non-blank line
    /// through a fresh `TraceParser` and sums the resulting `.prefillSync`
    /// events. Missing/empty text yields all-zero totals.
    public static func sum(traceText: String) -> TraceTokenTotals {
        var parser = TraceParser()
        var events: [TraceEvent] = []
        for line in traceText.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let event = parser.feed(s) { events.append(event) }
        }
        return sum(events: events)
    }
}
