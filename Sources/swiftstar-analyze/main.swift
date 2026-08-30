import Foundation
import SwiftStarKit

// swiftstar-analyze — read the capture trees back (P21). Run from the checkout.
//
//   swiftstar-analyze list                       capture dirs, newest first, flagging unusable ones
//   swiftstar-analyze summary [DIR | --latest]   per-turn table: decode average, tokens, ctx, tools, Σsuffix
//   swiftstar-analyze trace  [DIR | --latest]    the prefill-sync/cache + compaction story
//   swiftstar-analyze diff A B                   paired-bill comparison (Σsuffix)
//
// All parsers are the production ones (WireEventParser, TraceParser,
// TurnSummary); this is ~150 lines of plumbing, not re-derived math.

// MARK: - discovery

func captureRoot() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("captures")
}

struct CaptureDir {
    let name: String
    let dir: URL
    let kind: String
    let modified: Date
}

/// Every capture tree, newest first. Ordering is by mtime, not by directory
/// name: the trees use three different naming conventions (the drive stamps the
/// model into the name, rescued evidence is hand-named), so a lexical sort puts
/// `evidence/20260826-spike-run` ahead of a live session captured hours later.
func captureDirs() -> [CaptureDir] {
    var out: [CaptureDir] = []
    func add(_ base: URL, kind: String, recurse: Bool) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for e in entries where e.hasDirectoryPath {
            // The drive writes its dirs at the captures/ root, beside the
            // per-producer subdirectories — skip those when scanning the root.
            if !recurse, ["live", "agenttest", "evidence"].contains(e.lastPathComponent) { continue }
            let modified = (try? e.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            out.append(CaptureDir(name: e.lastPathComponent, dir: e, kind: kind, modified: modified))
        }
    }
    for sub in ["live", "agenttest", "evidence"] {
        add(captureRoot().appendingPathComponent(sub), kind: sub, recurse: true)
    }
    add(captureRoot(), kind: "drive", recurse: false)
    return out.sorted { $0.modified > $1.modified }
}

/// Why a capture cannot answer "what did my last session do".
enum Unusable: String {
    /// No wire at all, or a zero-byte one.
    case emptyWire = "empty/missing wire.ndjson"
    /// A non-empty wire that records no turn the user started — the shape of an
    /// agent spawned and left idle (handshake + statuses + the engine's
    /// field-less startup ready). Size alone cannot tell this from a real
    /// session: `live/20260830-163255` carried 4 KB of handshake and zero
    /// turns, and under the old size-only predicate it shadowed
    /// `live/20260830-155556` — 3 real turns, 53 tool calls — as `--latest`.
    case noWork = "no work recorded (idle spawn)"
}

func unusableReason(_ d: CaptureDir) -> Unusable? {
    let wire = d.dir.appendingPathComponent("wire.ndjson")
    let size = (try? FileManager.default.attributesOfItem(atPath: wire.path)[.size]) as? Int
    if (size ?? 0) == 0 { return .emptyWire }
    let lines = (try? String(contentsOf: wire, encoding: .utf8))?
        .split(whereSeparator: \.isNewline).map(String.init) ?? []
    return CaptureUsability.recordsWork(wireLines: lines) ? nil : .noWork
}

func isUnusable(_ d: CaptureDir) -> Bool { unusableReason(d) != nil }

func resolveDir(_ spec: String) -> URL {
    if spec == "--latest" {
        // "My last session" means the app's most recent usable capture, not
        // whichever directory was written most recently — rescued evidence and
        // agenttest cells would otherwise shadow it.
        let all = captureDirs()
        let candidate = all.first { $0.kind == "live" && !isUnusable($0) }
            ?? all.first { !isUnusable($0) }
        guard let candidate else {
            FileHandle.standardError.write(Data("no usable captures found under \(captureRoot().path)\n".utf8))
            exit(2)
        }
        return candidate.dir
    }
    if spec.hasPrefix("/") { return URL(fileURLWithPath: spec) }
    return captureRoot().appendingPathComponent(spec)
}

// MARK: - parsing

/// The orchestrator's own events. A pooled capture interleaves subagent
/// sessions on one wire, each with its own independent counters — folding them
/// together produces a merged fiction (measured: one agenttest capture reports a
/// single 19,030-token "turn" that never happened).
func parseWire(_ dir: URL) -> [WireEvent] {
    guard let text = try? String(contentsOf: dir.appendingPathComponent("wire.ndjson"), encoding: .utf8) else { return [] }
    var p = WireEventParser()
    var out: [WireEvent] = []
    for line in text.split(whereSeparator: \.isNewline) {
        guard PoolWireParser.worker(of: String(line)) == .orchestrator else { continue }
        if let e = p.feed(String(line)) { out.append(e) }
    }
    return out
}

/// Per-worker status streams for a pooled capture, so a subagent's session can
/// be summarized on its own terms instead of silently vanishing.
func workerStatusCounts(_ dir: URL) -> [WorkerId: Int] {
    guard let text = try? String(contentsOf: dir.appendingPathComponent("wire.ndjson"), encoding: .utf8) else { return [:] }
    var counts: [WorkerId: Int] = [:]
    for line in text.split(whereSeparator: \.isNewline) {
        let worker = PoolWireParser.worker(of: String(line))
        guard worker != .orchestrator else { continue }
        counts[worker, default: 0] += 1
    }
    return counts
}

func parseTrace(_ dir: URL) -> [TraceEvent] {
    // `TraceParser.read` decodes lossily: the engine's token-dump lines embed
    // raw bytes, and a truncated multibyte sequence (real occurrence —
    // `captures/live/20260827-200648`) made the old all-or-nothing UTF-8 read
    // return nil, reporting "no trace" for a session with 28 prefill syncs.
    for name in ["agent.trace", "wire.trace"] {
        let events = TraceParser.read(url: dir.appendingPathComponent(name))
        if !events.isEmpty { return events }
    }
    return []
}

func parseOutcomes(_ dir: URL) -> [TurnOutcome] {
    guard let text = try? String(contentsOf: dir.appendingPathComponent("outcomes.ndjson"), encoding: .utf8) else { return [] }
    var out: [TurnOutcome] = []
    for line in text.split(whereSeparator: \.isNewline) {
        if let data = String(line).data(using: .utf8),
           let o = try? JSONDecoder().decode(TurnOutcome.self, from: data) { out.append(o) }
    }
    return out
}

/// The turn's decode work with the app's own math (`DecodeAccumulator`): per
/// generation segment, on the engine's clock.
func decodeWork(_ turn: [StatusSnapshot], finalGenerated: Int?) -> DecodeAccumulator {
    var acc = DecodeAccumulator()
    for s in turn { acc.apply(s) }
    acc.finish(finalGenerated: finalGenerated)
    return acc
}

func suffixTotal(_ trace: [TraceEvent]) -> Int {
    var total = 0
    for e in trace { if case .prefillSync(_, _, let suffix, _, _) = e { total += suffix } }
    return total
}

func compactionCount(_ trace: [TraceEvent]) -> Int {
    var count = 0
    for e in trace { if case .compaction = e { count += 1 } }
    return count
}

// MARK: - commands

func cmdList() {
    for d in captureDirs() {
        let flag = unusableReason(d).map { "  [unusable: \($0.rawValue)]" } ?? ""
        print("\(d.kind)/\(d.name)\(flag)")
    }
}

/// Pair each outcome with the turn that produced it, segmenting statuses the
/// same way the CLI used to — now production code (`TurnAlignment`) with real
/// unit coverage: the app writes outcomes only for turns whose terminal ready
/// carries data, so the startup prefill's phantom turn no longer borrows the
/// first outcome's ctx/tools.
func cmdSummary(_ dir: URL) {
    let events = parseWire(dir)
    let outcomes = parseOutcomes(dir)
    let trace = parseTrace(dir)
    let rows = TurnAlignment.align(events: events, outcomes: outcomes)
    print("Session \(dir.lastPathComponent): \(rows.count) turn(s), \(outcomes.count) outcome(s), \(compactionCount(trace)) compaction(s), Σsuffix \(suffixTotal(trace))")
    for (i, row) in rows.enumerated() {
        let outcome = row.outcome
        let work = decodeWork(row.statuses, finalGenerated: outcome?.generatedTokens)
        let avg = work.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "-"
        // The accumulator's total, not the outcome's: the engine's counter
        // resets per generation segment, so a tool-heavy turn's `ready` reports
        // only its last segment.
        let gen = work.generatedTokens
        let ctx = outcome?.ctxUsed ?? row.statuses.last?.ctxUsed ?? 0
        let tools = outcome?.toolCalls.count ?? 0
        print(String(format: "  %2d  decode %@ tok/s  tokens %d  ctx %d  tools %d", i + 1, avg, gen, ctx, tools))
    }
    let workers = workerStatusCounts(dir)
    if !workers.isEmpty {
        // Never silently drop them: the turns above are the orchestrator's, and
        // a reader who does not know this capture is pooled would miss that most
        // of the session happened in a subagent.
        let detail = workers.sorted { $0.key < $1.key }
            .map { "worker \($0.key.rawValue): \($0.value) event(s)" }
            .joined(separator: ", ")
        print("  (pooled capture — subagent traffic not counted above: \(detail))")
    }
}

func cmdTrace(_ dir: URL) {
    let trace = parseTrace(dir)
    guard !trace.isEmpty else {
        print("no trace (agent.trace / wire.trace) in \(dir.lastPathComponent)")
        return
    }
    for e in trace {
        switch e {
        case .prefillSync(let prompt, let cached, let suffix, let rc, let ms):
            // `ms` is a Double — a %d here reinterprets its bits and prints
            // garbage (a real 828.088 ms rendered as -1958505087).
            print(String(format: "sync  prompt %d  cached %d  suffix %d  rc %d  %.1f ms", prompt, cached, suffix, rc, ms))
        case .compaction(let reason, let old, let new, _, let tail):
            print("compaction  \(reason): \(old) -> \(new)  tail \(tail)")
        case .ignored:
            break
        }
    }
}

func cmdDiff(_ a: URL, _ b: URL) {
    // The paired-bill comparison P24's guardrail calls for: the only additively
    // meaningful trace metric is Σsuffix (Σprompt is cumulative + double-counts).
    let sa = suffixTotal(parseTrace(a))
    let sb = suffixTotal(parseTrace(b))
    print("Σsuffix  \(a.lastPathComponent): \(sa)")
    print("Σsuffix  \(b.lastPathComponent): \(sb)")
    if sa > 0 {
        print(String(format: "ratio: %.2f", Double(sb) / Double(sa)))
    }
}

/// A `read`/`more` tool_request reduced to what the measurement cares about:
/// the worker (which session read it), the path (what it read), and the raw
/// window parameters for same-window counting (P24.2, D3). `isMore` marks a
/// continuation, which is attributed to a path but never counted as a re-read.
struct ReadRequest {
    let worker: WorkerId
    let path: String
    let startLine: Int?    // nil for a bare read
    let maxLines: Int?     // nil for a bare read
    let isMore: Bool
}

/// Every `read`/`more` tool_request on the wire, per worker, from the raw
/// NDJSON via the production pooled parser — no engine, no model. `more`
/// carries no `path` — it continues the file the session last `read` — so it is
/// attributed to that path. `ctx_size` is captured per worker from the wire's
/// `status` events (pool workers run at their own clamped context, not the
/// orchestrator's) so the same-window key can resolve each worker's own bare-
/// read tier default.
func readRequests(_ dir: URL) -> (contextSizeByWorker: [WorkerId: Int], reads: [ReadRequest]) {
    guard let text = try? String(contentsOf: dir.appendingPathComponent("wire.ndjson"), encoding: .utf8) else { return ([:], []) }
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    var out: [ReadRequest] = []
    var lastPath: [WorkerId: String] = [:]
    var ctxSizeByWorker: [WorkerId: Int] = [:]

    func record(worker: WorkerId, name: String, params: [ToolParam]) {
        var path = ""
        var startLine: Int? = nil
        var maxLines: Int? = nil
        for p in params {
            if p.name == "path" { path = p.value }
            if p.name == "start_line" { startLine = Int(p.value) }
            if p.name == "max_lines" { maxLines = Int(p.value) }
        }
        if path.isEmpty { path = lastPath[worker] ?? "" }
        guard !path.isEmpty else { return }
        lastPath[worker] = path
        out.append(ReadRequest(worker: worker, path: path,
                               startLine: startLine, maxLines: maxLines,
                               isMore: name == "more"))
    }

    var pooled = PoolWireParser()
    for line in lines {
        guard let e = pooled.feed(line) else { continue }
        if case .status(let s) = e.event, ctxSizeByWorker[e.worker] == nil {
            ctxSizeByWorker[e.worker] = s.ctxSize
        }
        guard case .toolRequest(_, let name, let params) = e.event,
              name == "read" || name == "more" else { continue }
        record(worker: e.worker, name: name, params: params)
    }
    if !out.isEmpty { return (ctxSizeByWorker, out) }

    // Single-session fallback: a `swiftstar-drive` capture carries no
    // worker-tagged envelopes, so `PoolWireParser` sees nothing in it. Before
    // this, the committed verb could not analyse the committed capture
    // program's own output — the gap that made P24.1's measurement reach for a
    // one-off script. Everything is attributed to the orchestrator.
    var plain = AgentWireParser()
    for line in lines {
        guard let e = plain.feed(line) else { continue }
        if case .status(let s) = e, ctxSizeByWorker[.orchestrator] == nil {
            ctxSizeByWorker[.orchestrator] = s.ctxSize
        }
        guard case .toolRequest(_, let name, let params) = e,
              name == "read" || name == "more" else { continue }
        record(worker: .orchestrator, name: name, params: params)
    }
    return (ctxSizeByWorker, out)
}

/// P24.2 (D3) read evidence: how many `read` calls each session made, how many
/// were same-window re-reads — the *same effective* `(path, start_line,
/// max_lines)` asked again — and the top offenders, with repeated windows
/// listed per path.
///
/// Same-window of the *effective* window is the number that decides the
/// read-guard question: a bare read and `start=1,max=<tier>` are one window,
/// not two. The old same-path count (`calls - distinct paths`) labelled the
/// model's healthy walk across a file as redundant. `more` is attributed to a
/// path but never counted as a re-read (a continuation is not a repeat).
func cmdRereads(_ dir: URL) {
    let (ctxSizeByWorker, reads) = readRequests(dir)
    guard !reads.isEmpty else {
        print("no read/more tool_requests in \(dir.lastPathComponent)")
        return
    }
    let workers = Set(reads.map { $0.worker }).sorted()
    for worker in workers {
        let mine = reads.filter { $0.worker == worker }
        let moreCount = mine.filter { $0.isMore }.count
        let report = ReadRepeatCounter.summarize(
            mine.compactMap { $0.isMore ? nil : (path: $0.path, startLine: $0.startLine, maxLines: $0.maxLines) },
            contextSize: ctxSizeByWorker[worker] ?? 0)
        let moreSuffix = moreCount > 0 ? " [\(moreCount) more call(s)]" : ""
        print("worker \(worker.rawValue): \(report.calls) read call(s), \(report.distinctPairs) distinct (path, window) pair(s) — \(report.sameWindowRepeats) same-window re-read(s)\(moreSuffix)")
        for row in report.paths where row.calls > 1 {
            print(String(format: "  %3d  %@  [%d distinct window(s)]",
                         row.calls, row.path, row.distinctWindows))
            for item in row.repeatedWindows {
                print("          \(item.count)x  start_line=\(item.startLine) max_lines=\(item.maxLines)")
            }
        }
    }
}

// MARK: - findings and campaign analysis

/// Render the same typed findings the app's Diagnostics tab renders. Keeping
/// this in the CLI means a capture is not interpreted by a second diagnostics
/// implementation when it is reviewed outside the app.
func cmdFindings(_ dir: URL) {
    let findings = DiagnosticsAnalyzer().analyze(
        events: parseWire(dir), trace: parseTrace(dir))
    guard !findings.isEmpty else {
        print("no findings in \(dir.lastPathComponent)")
        return
    }
    let phraser = DeterministicPhraser()
    for finding in findings {
        print(phraser.phrase(finding))
    }
}

private struct TaxonomyWorker {
    var events: [String: Int] = [:]
    var tools: [String: Int] = [:]
    var errors: [String: Int] = [:]

    mutating func countEvent(_ name: String) {
        events[name, default: 0] += 1
    }

    mutating func countTool(_ name: String) {
        tools[name, default: 0] += 1
    }

    mutating func countError(_ error: String) {
        errors[error, default: 0] += 1
    }
}

/// Summarize the pooled wire by worker using the production parser. This is
/// the Swift replacement for the retired directive-taxonomy script; worker
/// streams are never folded together because that creates a session that never
/// existed.
func cmdTaxonomy(_ dir: URL) {
    let url = dir.appendingPathComponent("wire.ndjson")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        print("no wire.ndjson in \(dir.lastPathComponent)")
        return
    }

    var parser = PoolWireParser()
    var byWorker: [WorkerId: TaxonomyWorker] = [:]
    var unparsable = 0
    for raw in text.split(whereSeparator: \.isNewline) {
        let line = String(raw)
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            unparsable += 1
            continue
        }
        guard let parsed = parser.feed(line) else { continue }
        let worker = parsed.worker
        let type = object["t"] as? String ?? "?"
        byWorker[worker, default: TaxonomyWorker()].countEvent(type)
        if type == "tool_request", let name = object["name"] as? String {
            byWorker[worker, default: TaxonomyWorker()].countTool(name)
        }
        if case .status(let status) = parsed.event, !status.error.isEmpty {
            byWorker[worker, default: TaxonomyWorker()].countError(status.error)
        }
    }

    print("== \(dir.lastPathComponent)")
    let config = ["campaign.json", "run-config.json"].lazy
        .map { dir.appendingPathComponent($0) }
        .compactMap { try? Data(contentsOf: $0) }
        .compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        .first
    if let config {
        let seed = config["seed"] ?? "?"
        let think = config["think_budget"] ?? config["repairThink"] ?? "?"
        let outcome = config["outcome"] ?? "?"
        let seconds = config["seconds"] ?? "?"
        print("   seed=\(seed) think=\(think) outcome=\(outcome) \(seconds)s")
    }
    let dispatches = byWorker[.orchestrator]?.tools["dispatch"] ?? 0
    print("   dispatches: \(dispatches)")
    for worker in byWorker.keys.sorted() {
        let report = byWorker[worker] ?? TaxonomyWorker()
        let role = worker == .orchestrator ? "orchestrator" : "worker \(worker.rawValue)"
        let toolRequests = report.tools.values.reduce(0, +)
        let toolText = report.tools.sorted { $0.value > $1.value }
            .map { "\($0.key)x\($0.value)" }.joined(separator: ", ")
        let paddedRole = padRight(role, width: 14)
        let paddedThink = padLeft(String(report.events["think"] ?? 0), width: 5)
        let paddedText = padLeft(String(report.events["text"] ?? 0), width: 4)
        let paddedTools = padLeft(String(toolRequests), width: 3)
        print("   \(paddedRole) think=\(paddedThink) text=\(paddedText) tool_requests=\(paddedTools)  [\(toolText.isEmpty ? "none" : toolText)]")
        if !report.errors.isEmpty {
            print("   engine errors:")
            for (error, count) in report.errors.sorted(by: { $0.value > $1.value }).prefix(5) {
                print(String(format: "     %4d x %@", count, String(error.prefix(90))))
            }
        }
    }
    if unparsable > 0 { print("   WARNING: \(unparsable) unparsable wire line(s)") }
}

private func wilsonInterval(passes: Int, total: Int) -> (Double, Double) {
    guard total > 0 else { return (0, 0) }
    let z = 1.96
    let p = Double(passes) / Double(total)
    let denominator = 1 + z * z / Double(total)
    let centre = (p + z * z / (2 * Double(total))) / denominator
    let half = z * sqrt(p * (1 - p) / Double(total)
        + z * z / (4 * Double(total * total))) / denominator
    return (max(0, centre - half), min(1, centre + half))
}

private func tsvRows(_ url: URL) -> (header: [String], rows: [[String: String]])? {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
    guard let first = lines.first else { return nil }
    let header = first.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    let rows = lines.dropFirst().map { line -> [String: String] in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        return Dictionary(uniqueKeysWithValues: header.enumerated().map { index, key in
            (key, index < fields.count ? fields[index] : "")
        })
    }
    return (header, rows)
}

/// Report pass rates and failure modes from either campaign TSV schema. The
/// closure rule intentionally excludes harness voids/timeouts from the
/// denominator, matching the preregistration and both existing runners.
func cmdReport(_ paths: [URL]) {
    print("\n=== campaign report ===\n")
    for url in paths {
        guard let table = tsvRows(url) else {
            print("  (no results file yet: \(url.lastPathComponent))\n")
            continue
        }
        let key: String
        switch Array(table.header.prefix(3)) {
        case ["fixture", "rounds", "seed"]: key = "fixture"
        case ["spec", "think", "seed"]: key = "spec"
        default:
            print("  (unrecognized results header: \(url.lastPathComponent))\n")
            continue
        }
        let families = Dictionary(grouping: table.rows, by: { $0[key] ?? "" })
        print("  \(url.lastPathComponent) — \(table.rows.count) cells recorded")
        var totalPasses = 0
        var totalGraded = 0
        for family in families.keys.sorted() {
            let rows = families[family] ?? []
            let outcomes = rows.map { $0["outcome"] ?? "" }
            let voids = outcomes.filter { $0 == "harness-void" || $0 == "timeout" }.count
            let graded = rows.count - voids
            let passes = outcomes.filter { $0 == "pass" }.count
            totalPasses += passes
            totalGraded += graded
            if graded > 0 {
                let interval = wilsonInterval(passes: passes, total: graded)
                let label = padRight(family, width: 24)
                let rate = String(format: "%.0f", Double(passes) / Double(graded) * 100)
                let lower = String(format: "%.0f", interval.0 * 100)
                let upper = String(format: "%.0f", interval.1 * 100)
                let excluded = voids > 0 ? "  (\(voids) void/timeout excluded)" : ""
                print("    \(label) \(passes)/\(graded) = \(rate)%  [\(lower)%, \(upper)%]\(excluded)")
            } else {
                print("    \(family) — no graded cells")
            }
        }
        if families.count > 1, totalGraded > 0 {
            let interval = wilsonInterval(passes: totalPasses, total: totalGraded)
            let rate = String(format: "%.0f", Double(totalPasses) / Double(totalGraded) * 100)
            let lower = String(format: "%.0f", interval.0 * 100)
            let upper = String(format: "%.0f", interval.1 * 100)
            print("    \(padRight("POOLED", width: 24)) \(totalPasses)/\(totalGraded) = \(rate)%  [\(lower)%, \(upper)%]")
        }
        let failures = table.rows.filter { ($0["outcome"] ?? "") != "pass" }
        if !failures.isEmpty {
            var counts: [String: Int] = [:]
            for row in failures { counts[row["outcome"] ?? "", default: 0] += 1 }
            print("    failure modes:")
            for (outcome, count) in counts.sorted(by: { $0.value > $1.value }) {
                print("      \(padRight(outcome, width: 14)) \(count)")
            }
            var details: [String: Int] = [:]
            for row in failures {
                if let detail = row["detail"], !detail.isEmpty {
                    details[detail, default: 0] += 1
                }
            }
            for (detail, count) in details.sorted(by: { $0.value > $1.value }).prefix(8) {
                print("        \(String(format: "%3d", count))x  \(String(detail.prefix(88)))")
            }
            if table.header.contains("dispatches") {
                let noDispatch = failures.filter {
                    ($0["outcome"] ?? "") == "fail" && $0["dispatches"] == "0"
                }.count
                if noDispatch > 0 {
                    print("        \(noDispatch) graded failure(s) never dispatched a phase")
                }
            }
        }
        print()
    }
    print("Pre-registration: docs/superpowers/research/2026-08-28-overnight-campaign-preregistration.md")
}

private func escapedTSV(_ value: String) -> String {
    value.replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
}

private func padLeft(_ value: String, width: Int) -> String {
    guard value.count < width else { return value }
    return String(repeating: " ", count: width - value.count) + value
}

private func padRight(_ value: String, width: Int) -> String {
    guard value.count < width else { return value }
    return value + String(repeating: " ", count: width - value.count)
}

private func captureConfig(_ dir: URL) -> [String: Any]? {
    ["campaign.json", "run-config.json"].lazy
        .map { dir.appendingPathComponent($0) }
        .compactMap { try? Data(contentsOf: $0) }
        .compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        .first
}

/// Return an explicitly recorded engine identity. Missing metadata stays
/// blank: the analyzer must not turn a capture's location or model into a
/// guessed engine pin.
private func enginePin(_ dir: URL, config: [String: Any]?) -> String {
    var configs = config.map { [$0] } ?? []
    for name in ["campaign.json", "run-config.json"] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { continue }
        configs.append(object)
    }
    for config in configs {
        for key in ["engine_pin", "enginePin", "engine", "engine_sha",
                    "engineSHA", "submodule_sha", "submoduleSHA"] {
            if let value = config[key] as? String, !value.isEmpty { return value }
        }
    }

    guard let text = try? String(contentsOf: dir.appendingPathComponent("provenance.md"), encoding: .utf8) else {
        return ""
    }
    let markers = [
        "Submodule (`external/ds4`) SHA:",
        "Engine pin:",
        "Engine SHA:"
    ]
    for rawLine in text.split(whereSeparator: \.isNewline) {
        let line = String(rawLine)
        for marker in markers {
            guard let range = line.range(of: marker) else { continue }
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if value.first == "`", let end = value.dropFirst().firstIndex(of: "`") {
                let pin = String(value[value.index(after: value.startIndex)..<end])
                if !pin.isEmpty { return pin }
            }
        }
    }
    return ""
}

/// Write a cheap, re-derivable index rather than introducing a second
/// database/query layer. The output is ignored with the capture tree and can
/// always be regenerated from the same capture directories.
func cmdIndex(to output: URL) throws {
    let columns = ["kind", "name", "usable", "wire_bytes", "turns", "outcomes",
                   "workers", "sum_suffix", "variant", "seed", "outcome", "engine_pin"]
    var rows = [columns.joined(separator: "\t")]
    for capture in captureDirs() {
        let wire = capture.dir.appendingPathComponent("wire.ndjson")
        let wireBytes = (try? Data(contentsOf: wire).count) ?? 0
        let outcomes = parseOutcomes(capture.dir)
        let workers = workerStatusCounts(capture.dir).keys.sorted()
            .map { String($0.rawValue) }.joined(separator: ",")
        let config = captureConfig(capture.dir)
        let fields = [
            capture.kind, capture.name, isUnusable(capture) ? "0" : "1",
            String(wireBytes), String(parseWire(capture.dir).filter {
                if case .ready(_, let stop, _, _) = $0 { return stop != nil }
                return false
            }.count), String(outcomes.count), workers,
            String(suffixTotal(parseTrace(capture.dir))),
            "\(config?["variant"] ?? "")", "\(config?["seed"] ?? "")",
            "\(config?["outcome"] ?? "")", enginePin(capture.dir, config: config)
        ].map(escapedTSV)
        rows.append(fields.joined(separator: "\t"))
    }
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try rows.joined(separator: "\n").appending("\n")
        .write(to: output, atomically: true, encoding: .utf8)
    print("wrote \(rows.count - 1) capture row(s) to \(output.path)")
}

// MARK: - main

let args = CommandLine.arguments
func usage() -> Never {
    FileHandle.standardError.write(Data("usage: swiftstar-analyze list | summary [DIR|--latest] | trace [DIR|--latest] | diff A B | rereads [DIR|--latest] | findings [DIR|--latest] | taxonomy [DIR|--latest] | report [TSV ...] | index [OUTPUT]\n".utf8))
    exit(2)
}
guard args.count >= 2 else { usage() }
switch args[1] {
case "list":
    cmdList()
case "summary":
    guard args.count >= 3 else { usage() }
    cmdSummary(resolveDir(args[2]))
case "trace":
    guard args.count >= 3 else { usage() }
    cmdTrace(resolveDir(args[2]))
case "diff":
    guard args.count >= 4 else { usage() }
    cmdDiff(resolveDir(args[2]), resolveDir(args[3]))
case "rereads":
    guard args.count >= 3 else { usage() }
    cmdRereads(resolveDir(args[2]))
case "findings":
    guard args.count >= 3 else { usage() }
    cmdFindings(resolveDir(args[2]))
case "taxonomy":
    guard args.count >= 3 else { usage() }
    cmdTaxonomy(resolveDir(args[2]))
case "report":
    let paths: [URL]
    if args.count > 2 {
        paths = Array(args.dropFirst(2)).map { URL(fileURLWithPath: $0) }
    } else {
        let research = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/superpowers/research")
        paths = [
            research.appendingPathComponent("experiment-results-editing-n20.tsv"),
            research.appendingPathComponent("experiment-results-orchestrate.tsv")
        ]
    }
    cmdReport(paths)
case "index":
    let output = args.count > 2
        ? URL(fileURLWithPath: args[2])
        : captureRoot().appendingPathComponent("index.tsv")
    do { try cmdIndex(to: output) } catch {
        FileHandle.standardError.write(Data("index failed: \(error)\n".utf8))
        exit(1)
    }
default:
    usage()
}
