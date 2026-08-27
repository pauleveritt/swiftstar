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

struct CaptureDir: Comparable {
    let name: String
    let dir: URL
    let kind: String
    static func < (l: CaptureDir, r: CaptureDir) -> Bool { l.name < r.name }
}

func captureDirs() -> [CaptureDir] {
    var out: [CaptureDir] = []
    for (kind, sub) in [("live", "live"), ("agenttest", "agenttest"), ("evidence", "evidence")] {
        let base = captureRoot().appendingPathComponent(sub)
        if let entries = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
            for e in entries where e.hasDirectoryPath {
                out.append(CaptureDir(name: e.lastPathComponent, dir: e, kind: kind))
            }
        }
    }
    return out.sorted(by: >)
}

func isUnusable(_ d: CaptureDir) -> Bool {
    let wire = d.dir.appendingPathComponent("wire.ndjson")
    let size = (try? FileManager.default.attributesOfItem(atPath: wire.path)[.size] as? Int) ?? 0
    return size == nil || size == 0
}

func resolveDir(_ spec: String) -> URL {
    if spec == "--latest" {
        guard let d = captureDirs().first else {
            FileHandle.standardError.write(Data("no captures found under \(captureRoot().path)\n".utf8))
            exit(2)
        }
        return d.dir
    }
    if spec.hasPrefix("/") { return URL(fileURLWithPath: spec) }
    return captureRoot().appendingPathComponent(spec)
}

// MARK: - parsing

func parseWire(_ dir: URL) -> [WireEvent] {
    guard let text = try? String(contentsOf: dir.appendingPathComponent("wire.ndjson"), encoding: .utf8) else { return [] }
    var p = WireEventParser()
    var out: [WireEvent] = []
    for line in text.split(whereSeparator: \.isNewline) {
        if let e = p.feed(String(line)) { out.append(e) }
    }
    return out
}

func parseTrace(_ dir: URL) -> [TraceEvent] {
    for name in ["agent.trace", "wire.trace"] {
        if let text = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) {
            var p = TraceParser()
            var out: [TraceEvent] = []
            for line in text.split(whereSeparator: \.isNewline) {
                if let e = p.feed(String(line)) { out.append(e) }
            }
            return out
        }
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

/// Segment the wire's statuses into turns (idle ends a turn) — the same shape
/// the golden-replay test uses.
func turns(_ events: [WireEvent]) -> [[StatusSnapshot]] {
    var statuses: [StatusSnapshot] = []
    for e in events { if case .status(let s) = e { statuses.append(s) } }
    var out: [[StatusSnapshot]] = []
    var current: [StatusSnapshot] = []
    for s in statuses {
        if s.state == "idle", !current.isEmpty {
            current.append(s); out.append(current); current = []
        } else if s.state != "idle" {
            current.append(s)
        }
    }
    if !current.isEmpty { out.append(current) }
    return out
}

/// The turn's decode average with the app's own (fixed) math: µs unit +
/// first-generating baseline (prefill excluded).
func decodeAverage(_ turn: [StatusSnapshot]) -> Double? {
    var baseline: StatusSnapshot?
    for s in turn { baseline = TurnSummary.baseline(for: s, current: baseline) }
    guard let b = baseline, let last = turn.last else { return nil }
    return TurnSummary.averageDecodeTPS(first: b, last: last)
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

func cmdSummary(_ dir: URL) {
    let events = parseWire(dir)
    let outcomes = parseOutcomes(dir)
    let trace = parseTrace(dir)
    let ts = turns(events)
    print("Session \(dir.lastPathComponent): \(ts.count) turn(s), \(outcomes.count) outcome(s), \(compactionCount(trace)) compaction(s), Σsuffix \(suffixTotal(trace))")
    for (i, t) in ts.enumerated() {
        let avg = decodeAverage(t).map { String(format: "%.1f", $0) } ?? "-"
        let outcome = i < outcomes.count ? outcomes[i] : nil
        let gen = outcome?.generatedTokens ?? t.last?.generated ?? 0
        let ctx = outcome?.ctxUsed ?? t.last?.ctxUsed ?? 0
        let tools = outcome?.toolCalls.count ?? 0
        print(String(format: "  %2d  decode %@ tok/s  tokens %d  ctx %d  tools %d", i + 1, avg, gen, ctx, tools))
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
            print(String(format: "sync  prompt %d  cached %d  suffix %d  rc %d  %d ms", prompt, cached, suffix, rc, ms))
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

// MARK: - main

let args = CommandLine.arguments
func usage() -> Never {
    FileHandle.standardError.write(Data("usage: swiftstar-analyze list | summary [DIR|--latest] | trace [DIR|--latest] | diff A B\n".utf8))
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
default:
    usage()
}
