import Foundation

/// ds4-engine's report on one session (`ds4-dogfood report <dir> --json`,
/// AN.4), and its Markdown: Analyze's report card, and the text the fork's
/// model is asked about. Every figure and label is the engine's; nothing
/// here computes a rate or decides a flag (what's missing is ds4-engine#246).
public struct SessionReport: Decodable, Equatable, Sendable {
    public static let schema = "ds4-session-report/2"

    public struct Session: Decodable, Equatable, Sendable {
        /// A session this one continues; `kept` is how many of its prompts
        /// the conversation keeps (nil: all).
        public struct Earlier: Decodable, Equatable, Sendable {
            public let id: String
            public let prompts, kept: Int?
        }

        public let id: String
        public let modelId: String?
        public let contextSize: Int?
        public let outcome: String?
        public let earlier: [Earlier]?
        public let rewoundTo, filesChanged, errors: Int?
        public let closed, telemetryOk: Bool?
        /// The `session` event's DFlash label, such as "off (no drafter)".
        public let dflash: String?

        enum CodingKeys: String, CodingKey {
            case id, outcome, earlier, closed, dflash, errors
            case modelId = "model_id", contextSize = "context_size", rewoundTo = "rewound_to"
            case filesChanged = "files_changed", telemetryOk = "telemetry_ok"
        }
    }

    /// Where the wall clock went, in ms; nil when its source is absent.
    public struct Time: Decodable, Equatable, Sendable {
        public let wallMs, startupMs, prefixCacheMs, promptSyncMs, decodeMs: Double?
        public let otherEngineMs, toolsMs, receiptMs, idleMs: Double?
        /// Outside the split above.
        public let candidateReadyMs, indexPrimedMs: Double?

        enum CodingKeys: String, CodingKey {
            case candidateReadyMs = "candidate_ready_ms", indexPrimedMs = "index_primed_ms"
            case wallMs = "wall_ms", startupMs = "startup_ms", prefixCacheMs = "prefix_cache_ms"
            case promptSyncMs = "prompt_sync_ms", decodeMs = "decode_ms", otherEngineMs = "other_engine_ms"
            case toolsMs = "tools_ms", receiptMs = "receipt_ms", idleMs = "idle_ms"
        }
    }

    public struct Rates: Decodable, Equatable, Sendable {
        public let prefill, decode: Double?
    }

    /// One prefix-cache event; its label carries the time saved or spent,
    /// and on a miss what changed.
    public struct PrefixCache: Decodable, Equatable, Sendable {
        public let prompt: Int?
        public let label: String?
    }

    /// One load of a resumed conversation's saved state.
    public struct ConversationState: Decodable, Equatable, Sendable {
        public let prompt: Int?
        public let bytes: Int64?
        public let loadMs: Double?
        public let label, error: String?

        enum CodingKeys: String, CodingKey {
            case prompt, bytes, label, error, loadMs = "load_ms"
        }
    }

    /// Counters printed raw, as the engine sends them.
    public struct Signals: Decodable, Equatable, Sendable {
        public struct Constraint: Decodable, Equatable, Sendable {
            public let maskedTokenCount, forbiddenArgmax: Int?
            public let removedProbabilityMass: [Double]?

            enum CodingKeys: String, CodingKey {
                case maskedTokenCount = "masked_token_count", forbiddenArgmax = "forbidden_argmax"
                case removedProbabilityMass = "removed_probability_mass"
            }
        }

        public struct ResultBytes: Decodable, Equatable, Sendable {
            public let total, shown: Int?
        }

        public let constraint: Constraint?
        public let thinkInertOpeners, citationCorrections: Int?
        public let resultBytes: ResultBytes?

        enum CodingKeys: String, CodingKey {
            case constraint, thinkInertOpeners = "think_inert_openers"
            case citationCorrections = "citation_corrections", resultBytes = "result_bytes"
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
            /// The guard notice the call got: `already_shown`, `repeated_call`, `call_cycle`.
            public let loopGuard: String?

            enum CodingKeys: String, CodingKey {
                case tool, detail, ok, flags, loopGuard = "loop_guard"
            }
        }

        /// A failed native span or an `error` event after this prompt.
        public struct TurnError: Decodable, Equatable, Sendable {
            public let label: String?
        }

        public struct Compaction: Decodable, Equatable, Sendable {
            public let tokens: Int?
            public let label: String?
        }

        public let prompt: Int
        public let text: String?
        public let seconds: Double?
        /// Nil without events.
        public let answered, interrupted: Bool?
        public let reason: String?
        public let errors: [TurnError]?
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
    public let conversationState: [ConversationState]?
    public let signals: Signals?
    public let turns: [Turn]?
    public let dflash: DFlash?
    public let loopGuards: LoopGuards?
    public let gpu: GPU?
    public let suggestions: [Suggestion]?
    public let notes: [String]?

    enum CodingKeys: String, CodingKey {
        case schema, session, time, rates, turns, dflash, gpu, signals, suggestions, notes
        case prefixCache = "prefix_cache", conversationState = "conversation_state", loopGuards = "loop_guards"
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

    /// What Analyze takes from the report (AN.3, D8): the Markdown for the
    /// card and the prompt, and the engine's suggestions for the remedies.
    public var analysisReport: AnalysisReport {
        AnalysisReport(
            markdown: markdown(),
            suggestions: (suggestions ?? []).compactMap { s in
                s.diff.map { EngineSuggestion(line: $0, why: s.why ?? s.rule) }
            })
    }

    /// The label the engine puts on a sync with no new tokens; such syncs
    /// are counted, not listed.
    static let emptySyncLabel = "nothing new to prefill"

    /// The report as Markdown: flagged steps first, which the analysis
    /// instruction asks about, then the session, its prompts, the prefill
    /// syncs, raw signals, suggestions and notes.
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

        if let signals {
            lines += ["", "### Signals", ""]
            lines += signalLines(signals, f)
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
    /// loop-guard notices, refused calls, engine errors, a prompt with no
    /// answer and compactions, then the session's loop-guard labels.
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
                if let loopGuard = call.loopGuard {
                    rows.append(Flagged(prompt: prompt, did: did, why: "loop guard: \(loopGuard)"))
                }
                for flag in call.flags ?? [] {
                    rows.append(Flagged(prompt: prompt, did: did, why: flag))
                }
            }
            for refused in turn.tools?.refused ?? [] {
                rows.append(Flagged(prompt: prompt, did: refused.name ?? "—", why: refused.label ?? "refused"))
            }
            for error in turn.errors ?? [] {
                rows.append(Flagged(prompt: prompt, did: "—", why: error.label ?? "engine error"))
            }
            if turn.answered == false {
                let why = turn.interrupted == true ? "interrupted" : turn.reason
                rows.append(Flagged(prompt: prompt, did: "—", why: "no answer" + (why.map { " (\($0))" } ?? "")))
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
        if let t = time, t.candidateReadyMs != nil || t.indexPrimedMs != nil {
            rows.append(("Start-up", "candidate ready \(t.candidateReadyMs.map(f.duration) ?? "—") · "
                + "index primed \(t.indexPrimedMs.map(f.duration) ?? "—")"))
        }
        if let earlier = session.earlier, !earlier.isEmpty {
            rows.append(("Continues", earlier.map { e in
                let prompts = e.prompts.map { p in
                    e.kept.map { "\($0) of \(p) prompts kept" } ?? "\(p) prompt\(p == 1 ? "" : "s")"
                }
                return e.id + (prompts.map { " (\($0))" } ?? "")
            }.joined(separator: ", ")))
        }
        if let rewound = session.rewoundTo {
            rows.append(("Rewound", "to prompt \(rewound)"))
        }
        if let r = rates {
            rows.append(("Rates", "prefill \(MetricsFormatting.rate(r.prefill, locale: f.locale)) · "
                + "decode \(MetricsFormatting.rate(r.decode, locale: f.locale)), over the session"))
        }
        for p in prefixCache ?? [] {
            rows.append(("Prefix cache", (p.prompt.map { "prompt \($0): " } ?? "") + (p.label ?? "—")))
        }
        // The engine's label carries the size and load time already
        // ("conversation state loaded: 305 MiB in 0.02 s").
        for c in conversationState ?? [] {
            rows.append(("Conversation state", (c.prompt.map { "prompt \($0): " } ?? "") + (c.label ?? "—")
                + (c.error.map { "; \($0)" } ?? "")))
        }
        if let g = gpu {
            rows.append(("GPU", "peak \(g.peakGib.map(f.gib) ?? "—") of \(g.budgetGib.map(f.gib) ?? "—")"
                + (g.planGib.map { "; plan \(f.gib($0))" } ?? "")))
        }
        let ending = [
            session.filesChanged.map { "\($0) files changed" },
            session.closed.map { $0 ? "closed" : "not closed" },
            session.telemetryOk.map { $0 ? "telemetry ok" : "telemetry not ok" },
            session.errors.map { "\($0) engine errors" },
        ].compactMap { $0 }
        if !ending.isEmpty {
            rows.append(("Ending", ending.joined(separator: " · ")))
        }
        if let label = session.dflash, dflash == nil {
            rows.append(("DFlash", label))
        }
        if let d = dflash {
            let per = d.acceptedPerBlock.map { $0.formatted(.number.precision(.fractionLength(2)).locale(f.locale)) }
            rows.append(("DFlash", (session.dflash.map { "\($0) · " } ?? "") + "\(d.blocks.map(String.init) ?? "—") blocks · \(per ?? "—") accepted per block"
                + (d.nMax.map { " of \($0)" } ?? "")))
        }
        return rows
    }

    private func signalLines(_ s: Signals, _ f: Format) -> [String] {
        var lines: [String] = []
        if let c = s.constraint {
            let mass = (c.removedProbabilityMass ?? []).map { String($0) }.joined(separator: ", ")
            lines.append("- constraint: masked_token_count \(c.maskedTokenCount.map(String.init) ?? "—") · "
                + "forbidden_argmax \(c.forbiddenArgmax.map(String.init) ?? "—") · removed_probability_mass [\(mass)]")
        }
        if let n = s.thinkInertOpeners { lines.append("- think_inert_openers: \(n)") }
        if let n = s.citationCorrections { lines.append("- citation_corrections: \(n)") }
        if let b = s.resultBytes {
            lines.append("- result bytes: \(b.total.map(f.number) ?? "—") total, \(b.shown.map(f.number) ?? "—") shown")
        }
        return lines
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

/// One of the engine's suggestions, as Analyze's remedies take it (AN.3, D2):
/// its one added line (`+- …`) and why it fired.
public struct EngineSuggestion: Equatable, Sendable {
    public let line: String
    public let why: String

    public init(line: String, why: String) {
        self.line = line
        self.why = why
    }
}

/// The report as Analyze uses it (AN.3, D8).
public struct AnalysisReport: Equatable, Sendable {
    public let markdown: String
    public let suggestions: [EngineSuggestion]

    public init(markdown: String, suggestions: [EngineSuggestion] = []) {
        self.markdown = markdown
        self.suggestions = suggestions
    }
}
