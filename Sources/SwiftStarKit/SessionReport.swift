import Foundation

/// ds4-engine's report on one session (`ds4-dogfood report <dir> --json`,
/// AN.4), and its Markdown: Analyze's report card, and the text the fork's
/// model is asked about. Every figure and label is the engine's; nothing
/// here computes a rate or decides a flag (what's missing is ds4-engine#246).
public struct SessionReport: Decodable, Equatable, Sendable {
    public static let schema = "ds4-session-report/1"

    public struct Session: Decodable, Equatable, Sendable {
        public let id: String
        public let modelId: String?
        public let contextSize: Int?
        public let outcome: String?

        enum CodingKeys: String, CodingKey {
            case id, outcome
            case modelId = "model_id", contextSize = "context_size"
        }
    }

    /// Where the wall clock went, in ms; nil when its source is absent.
    public struct Time: Decodable, Equatable, Sendable {
        public let wallMs, startupMs, prefixCacheMs, promptSyncMs, decodeMs: Double?
        public let otherEngineMs, toolsMs, receiptMs, idleMs: Double?

        enum CodingKeys: String, CodingKey {
            case wallMs = "wall_ms", startupMs = "startup_ms", prefixCacheMs = "prefix_cache_ms"
            case promptSyncMs = "prompt_sync_ms", decodeMs = "decode_ms", otherEngineMs = "other_engine_ms"
            case toolsMs = "tools_ms", receiptMs = "receipt_ms", idleMs = "idle_ms"
        }
    }

    public struct Rates: Decodable, Equatable, Sendable {
        public let prefill, decode: Double?
    }

    public struct PrefixCache: Decodable, Equatable, Sendable {
        public let label: String?
        public let loadMs, fillMs: Double?

        enum CodingKeys: String, CodingKey {
            case label, loadMs = "load_ms", fillMs = "fill_ms"
        }
    }

    public struct Turn: Decodable, Equatable, Sendable {
        public struct Context: Decodable, Equatable, Sendable {
            public let used: Int
            public let size: Int?
        }

        public struct Sync: Decodable, Equatable, Sendable {
            public let turn: Int
            public let after: String?
            public let tokens: Int
            public let ms, tokS: Double?
            public let labels: [String]?

            enum CodingKeys: String, CodingKey {
                case turn, after, tokens, ms, labels, tokS = "tok_s"
            }
        }

        public struct Decode: Decodable, Equatable, Sendable {
            public let tokens: Int?
            public let tokS: Double?

            enum CodingKeys: String, CodingKey {
                case tokens, tokS = "tok_s"
            }
        }

        public struct Tokens: Decodable, Equatable, Sendable {
            public let thinking, visible, unsplit: Int?
        }

        public struct Refused: Decodable, Equatable, Sendable {
            public let name, label: String?
        }

        public struct Tools: Decodable, Equatable, Sendable {
            public let byKind: [String: Int]?
            public let errors: Int?
            public let refused: [Refused]?

            enum CodingKeys: String, CodingKey {
                case errors, refused, byKind = "by_kind"
            }
        }

        /// One of the digest's call records: `detail` is "<tool> <args> → <result>".
        public struct Call: Decodable, Equatable, Sendable {
            public let tool: String
            public let detail: String?
            public let ok: Bool
            public let flags: [String]?
        }

        public struct Compaction: Decodable, Equatable, Sendable {
            public let tokens: Int?
            public let label: String?
        }

        public let prompt: Int
        public let text: String?
        public let seconds: Double?
        public let context: Context?
        public let syncs: [Sync]?
        public let decode: Decode?
        public let tokens: Tokens?
        public let tools: Tools?
        public let calls: [Call]?
        public let compactions: [Compaction]?
    }

    public struct LoopGuards: Decodable, Equatable, Sendable {
        public let labels: [String]?
    }

    public struct GPU: Decodable, Equatable, Sendable {
        public let planGib, peakGib, budgetGib: Double?

        enum CodingKeys: String, CodingKey {
            case planGib = "plan_gib", peakGib = "peak_gib", budgetGib = "budget_gib"
        }
    }

    public struct DFlash: Decodable, Equatable, Sendable {
        public let blocks, nMax: Int?
        public let acceptedPerBlock: Double?

        enum CodingKeys: String, CodingKey {
            case blocks, nMax = "n_max", acceptedPerBlock = "accepted_per_block"
        }
    }

    public struct Suggestion: Decodable, Equatable, Sendable {
        public let rule: String
        public let file, diff, why: String?
        public let evidencePrompts: [Int]?

        enum CodingKeys: String, CodingKey {
            case rule, file, diff, why, evidencePrompts = "evidence_prompts"
        }
    }

    public let schema: String
    public let session: Session
    public let time: Time?
    public let rates: Rates?
    public let prefixCache: [PrefixCache]?
    public let turns: [Turn]?
    public let dflash: DFlash?
    public let loopGuards: LoopGuards?
    public let gpu: GPU?
    public let suggestions: [Suggestion]?
    public let notes: [String]?

    enum CodingKeys: String, CodingKey {
        case schema, session, time, rates, turns, dflash, gpu, suggestions, notes
        case prefixCache = "prefix_cache", loopGuards = "loop_guards"
    }

    private struct Envelope: Decodable {
        let schema: String?
    }

    /// The report, or `.malformed` for unreadable JSON or another schema,
    /// whose fields aren't guessed at.
    public static func decode(_ data: Data) -> Result<SessionReport, CatalogError> {
        do {
            let found = try JSONDecoder().decode(Envelope.self, from: data).schema
            guard found == schema else {
                return .failure(.malformed("report schema \(found ?? "missing"); SwiftStar reads \(schema)"))
            }
            return .success(try JSONDecoder().decode(SessionReport.self, from: data))
        } catch {
            return .failure(.malformed(String(describing: error).prefix(200).description))
        }
    }

    /// The label the engine puts on a sync with no new tokens; such syncs
    /// are counted, not listed.
    static let emptySyncLabel = "nothing new to prefill"

    /// The report as Markdown: flagged steps first, which the analysis
    /// instruction asks about, then the session, its prompts, the prefill
    /// syncs, suggestions and notes.
    public func markdown(locale: Locale = .current) -> String {
        let f = Format(locale: locale)
        let turns = turns ?? []
        var lines = [
            "**report**: " + [
                session.id, session.modelId ?? "—",
                "ctx " + (session.contextSize.map { f.number($0) } ?? "—"),
                time?.wallMs.map(f.duration) ?? "—", session.outcome ?? "—",
            ].joined(separator: ", "),
            "",
        ]

        lines += ["### Flagged steps", ""]
        let flagged = flaggedRows(turns)
        if flagged.isEmpty {
            lines.append("no flagged steps")
        } else {
            lines += ["| Prompt | Did | Why |", "|---|---|---|"]
            lines += flagged.map { "| \($0.prompt) | \(Self.cell($0.did)) | \(Self.cell($0.why, limit: 200)) |" }
        }

        lines += ["", "### Session", "", "| Row | Value |", "|---|---|"]
        lines += sessionRows(f).map { "| \($0.0) | \(Self.cell($0.1, limit: 400)) |" }

        if !turns.isEmpty {
            lines += ["", "### Prompts", "",
                      "| Prompt | Asked | Took | Context | Decode | Thinking / visible | Tools |",
                      "|---|---|---|---|---|---|---|"]
            lines += turns.map { promptRow($0, f) }
        }

        let syncs = turns.flatMap { t in (t.syncs ?? []).map { (t.prompt, $0) } }
        let listed = syncs.filter { $0.1.tokens > 0 }
        if !syncs.isEmpty {
            lines += ["", "### Prefill", ""]
            if !listed.isEmpty {
                lines += ["| Prompt | Step | After | Tokens | Time | Rate | Label |", "|---|---|---|---|---|---|---|"]
                lines += listed.map { prompt, s in
                    let labels = (s.labels ?? []).joined(separator: "; ")
                    return "| \(prompt) | \(s.turn) | \(Self.cell(s.after ?? "—")) | \(f.number(s.tokens)) | "
                        + "\(s.ms.map(f.milliseconds) ?? "—") | \(MetricsFormatting.rate(s.tokS, locale: locale)) | "
                        + "\(labels.isEmpty ? "—" : Self.cell(labels)) |"
                }
            }
            let empty = syncs.count - listed.count
            if empty > 0 {
                lines += ["", "\(empty) syncs with \(Self.emptySyncLabel) are not listed."]
            }
        }

        if let suggestions, !suggestions.isEmpty {
            lines += ["", "### Suggestions", ""]
            lines += suggestions.map { s in
                let prompts = (s.evidencePrompts ?? []).map(String.init).joined(separator: ", ")
                return "- `\(s.rule)`" + (prompts.isEmpty ? "" : " (prompts \(prompts))") + ": \(s.why ?? "")"
                    + (s.diff.map { " In `\(s.file ?? "AGENTS.md")`: `\($0)`" } ?? "")
            }
        }

        if let notes, !notes.isEmpty {
            lines += ["", "### Notes", ""]
            lines += notes.map { "- \($0)" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private struct Flagged {
        let prompt: String, did: String, why: String
    }

    /// The report's own judgments: failed calls, the digest's call flags,
    /// refused calls, compactions, then the session's loop-guard labels.
    private func flaggedRows(_ turns: [Turn]) -> [Flagged] {
        var rows: [Flagged] = []
        for turn in turns {
            let prompt = String(turn.prompt)
            for call in turn.calls ?? [] {
                let parts = (call.detail ?? call.tool).components(separatedBy: " → ")
                let did = parts[0].trimmingCharacters(in: .whitespaces)
                let result = parts.dropFirst().joined(separator: " → ")
                if !call.ok {
                    rows.append(Flagged(prompt: prompt, did: did, why: "failed: \(result)"))
                }
                for flag in call.flags ?? [] {
                    rows.append(Flagged(prompt: prompt, did: did, why: flag))
                }
            }
            for refused in turn.tools?.refused ?? [] {
                rows.append(Flagged(prompt: prompt, did: refused.name ?? "—", why: refused.label ?? "refused"))
            }
            for c in turn.compactions ?? [] {
                rows.append(Flagged(
                    prompt: prompt, did: c.tokens.map { "\($0) tokens" } ?? "—", why: c.label ?? "compaction"))
            }
        }
        for label in loopGuards?.labels ?? [] {
            rows.append(Flagged(prompt: "—", did: "—", why: label))
        }
        return rows
    }

    private func sessionRows(_ f: Format) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let t = time {
            let parts: [(String, Double?)] = [
                ("wall", t.wallMs), ("start-up", t.startupMs), ("prefix cache", t.prefixCacheMs),
                ("prompt sync", t.promptSyncMs), ("decode", t.decodeMs), ("other engine", t.otherEngineMs),
                ("tools", t.toolsMs), ("receipt", t.receiptMs), ("idle", t.idleMs),
            ]
            rows.append(("Time", parts.map { "\($0.0) \($0.1.map(f.duration) ?? "—")" }.joined(separator: " · ")))
        }
        if let r = rates {
            rows.append(("Rates", "prefill \(MetricsFormatting.rate(r.prefill, locale: f.locale)) · "
                + "decode \(MetricsFormatting.rate(r.decode, locale: f.locale)), over the session"))
        }
        for p in prefixCache ?? [] {
            let ms = p.loadMs ?? p.fillMs
            rows.append(("Prefix cache", (p.label ?? "—") + (ms.map { ", \(f.duration($0))" } ?? "")))
        }
        if let g = gpu {
            rows.append(("GPU", "peak \(g.peakGib.map(f.gib) ?? "—") of \(g.budgetGib.map(f.gib) ?? "—")"
                + (g.planGib.map { "; plan \(f.gib($0))" } ?? "")))
        }
        if let d = dflash {
            let per = d.acceptedPerBlock.map { $0.formatted(.number.precision(.fractionLength(2)).locale(f.locale)) }
            rows.append(("DFlash", "\(d.blocks.map(String.init) ?? "—") blocks · \(per ?? "—") accepted per block"
                + (d.nMax.map { " of \($0)" } ?? "")))
        }
        return rows
    }

    private func promptRow(_ t: Turn, _ f: Format) -> String {
        let context = t.context.map { c in f.number(c.used) + (c.size.map { " of \(f.number($0))" } ?? "") } ?? "—"
        let decode = t.decode.map { d in
            (d.tokens.map { "\(f.number($0)) tokens, " } ?? "") + MetricsFormatting.rate(d.tokS, locale: f.locale)
        } ?? "—"
        let tokens = t.tokens.map { k in
            let unsplit = k.unsplit ?? 0
            return "\(k.thinking.map(String.init) ?? "—") / \(k.visible.map(String.init) ?? "—")"
                + (unsplit > 0 ? " (\(unsplit) with no think close)" : "")
        } ?? "—"
        let kinds = (t.tools?.byKind ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
        let errors = t.tools?.errors ?? 0
        let tools = (kinds.isEmpty ? "—" : kinds.joined(separator: ", "))
            + (errors > 0 ? "; \(errors) error\(errors == 1 ? "" : "s")" : "")
        return "| \(t.prompt) | \(Self.cell(t.text ?? "—", limit: 80)) | \(t.seconds.map { f.duration($0 * 1000) } ?? "—") | "
            + "\(context) | \(decode) | \(tokens) | \(Self.cell(tools)) |"
    }

    /// One table cell: a whitespace run holding a newline becomes a space,
    /// a long text is cut with "…", and `|` is escaped, the backslashes
    /// before it doubled first so `a\|b` can't split the row either.
    public static func cell(_ text: String, limit: Int = 120) -> String {
        var text = text.replacingOccurrences(of: #"\s*\r?\n\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if text.count > limit { text = String(text.prefix(limit - 1)) + "…" }
        return text.replacingOccurrences(of: #"(\\*)\|"#, with: #"$1$1\\|"#, options: .regularExpression)
    }

    private struct Format {
        let locale: Locale

        func number(_ n: Int) -> String { MetricsFormatting.number(n, locale: locale) }
        func gib(_ v: Double) -> String { MetricsFormatting.gib(v, locale: locale) }
        func duration(_ ms: Double) -> String { MetricsFormatting.duration(seconds: ms / 1000, locale: locale) }

        /// A sync's time: whole ms under ten seconds, where most fall.
        func milliseconds(_ ms: Double) -> String {
            ms < 10_000 ? "\(Int(ms.rounded())) ms" : duration(ms)
        }
    }
}
