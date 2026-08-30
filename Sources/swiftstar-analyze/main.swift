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

func isUnusable(_ d: CaptureDir) -> Bool {
    let wire = d.dir.appendingPathComponent("wire.ndjson")
    let size = (try? FileManager.default.attributesOfItem(atPath: wire.path)[.size]) as? Int
    return (size ?? 0) == 0
}

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
        let flag = isUnusable(d) ? "  [unusable: empty/missing wire.ndjson]" : ""
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

/// A `read`/`more` tool_request reduced to what the read-guard cares about:
/// the worker (which session read it) and the path (what it read). Windowed
/// reads (`start_line`/`max_lines`/`offset`/`end_line`) are flagged because the
/// guard can only short-circuit a re-read of the *same* window, not any window
/// of an unchanged file — a distinction the design must honor, so the
/// measurement records it rather than folding it away.
struct ReadRequest {
    let worker: WorkerId
    let path: String
    let windowed: Bool
}

/// Every `read`/`more` tool_request on the wire, per worker, from the raw
/// NDJSON via the production pooled parser — no engine, no model. The
/// read-guard's "before" evidence is a function of these counts: a redundant
/// re-read (same session, same path, unchanged content) is the re-entry the
/// guard short-circuits. `more` carries no `path` — it continues the file the
/// session last `read` — so it is attributed to that path, flagged windowed.
func readRequests(_ dir: URL) -> [ReadRequest] {
    guard let text = try? String(contentsOf: dir.appendingPathComponent("wire.ndjson"), encoding: .utf8) else { return [] }
    var parser = PoolWireParser()
    var out: [ReadRequest] = []
    var lastPath: [WorkerId: String] = [:]
    for line in text.split(whereSeparator: \.isNewline) {
        guard let e = parser.feed(String(line)),
              case .toolRequest(_, let name, let params) = e.event,
              name == "read" || name == "more" else { continue }
        var path = ""
        var windowed = name == "more"
        for p in params {
            if p.name == "path" { path = p.value }
            if p.name == "start_line" || p.name == "max_lines" || p.name == "offset" || p.name == "end_line" { windowed = true }
        }
        if path.isEmpty { path = lastPath[e.worker] ?? "" }
        guard !path.isEmpty else { continue }
        lastPath[e.worker] = path
        out.append(ReadRequest(worker: e.worker, path: path, windowed: windowed))
    }
    return out
}

/// The read-guard's "before" evidence, measured from the capture alone:
/// how many read/more calls each session made, how many were re-reads of a
/// path that session had already read, and the top offenders. Redundant count
/// is `calls - distinct` — a ceiling on the guard's short-circuits, since a
/// re-read is only short-circuitable when the content is unchanged between the
/// two reads (a fact the wire cannot prove; a session with zero mutations is
/// the common case where every redundant read is of unchanged content).
func cmdRereads(_ dir: URL) {
    let reads = readRequests(dir)
    guard !reads.isEmpty else {
        print("no read/more tool_requests in \(dir.lastPathComponent)")
        return
    }
    let workers = Set(reads.map { $0.worker }).sorted()
    for worker in workers {
        let mine = reads.filter { $0.worker == worker }
        var byPath: [String: (count: Int, windowed: Int)] = [:]
        for r in mine {
            byPath[r.path, default: (0, 0)].count += 1
            if r.windowed { byPath[r.path, default: (0, 0)].windowed += 1 }
        }
        let redundant = mine.count - byPath.count
        print("worker \(worker.rawValue): \(mine.count) read/more call(s) across \(byPath.count) distinct path(s) — \(redundant) redundant re-read(s)")
        for (path, c) in byPath.sorted(by: { $0.value.count > $1.value.count }) where c.count > 1 {
            let w = c.windowed > 0 ? "  (windowed: \(c.windowed))" : ""
            print(String(format: "  %3d  %@%@", c.count, path, w))
        }
    }
}

// MARK: - main

let args = CommandLine.arguments
func usage() -> Never {
    FileHandle.standardError.write(Data("usage: swiftstar-analyze list | summary [DIR|--latest] | trace [DIR|--latest] | diff A B | rereads [DIR|--latest]\n".utf8))
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
default:
    usage()
}
