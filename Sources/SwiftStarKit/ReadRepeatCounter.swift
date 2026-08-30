import Foundation

/// The same-window repeat count for a capture's `read` calls.
public struct ReadRepeatReport: Equatable, Sendable {
    public struct RepeatedWindow: Equatable, Sendable {
        public let startLine: Int     // effective, ≥ 1
        public let maxLines: Int      // effective, tier-resolved
        public let count: Int
    }
    public struct PathRow: Equatable, Sendable {
        public let path: String
        public let calls: Int
        public let distinctWindows: Int
        public let repeatedWindows: [RepeatedWindow]
    }
    public let calls: Int
    public let distinctPairs: Int
    public let sameWindowRepeats: Int
    public let paths: [PathRow]
}

/// P24.2 (D3): the same-window repeat count, extracted pure so it is fast-tier
/// testable rather than buried in `swiftstar-analyze/main.swift`.
///
/// The key is the **effective** window: a `nil` `startLine` resolves to 1 and a
/// `nil`/non-positive `maxLines` resolves to the engine's context tier, so a
/// bare read and `start=1,max=<tier>` are the *same* window (they deliver the
/// same head of the file). `raw`/`whole` are not part of the key — they change
/// the rendering, not the covered lines.
public enum ReadRepeatCounter {
    /// `read` calls only (`more` is a continuation, never a re-read — the
    /// caller filters it). Pure and deterministic: the per-path table is sorted
    /// by calls desc then path asc, so equal-count paths do not scramble.
    public static func summarize(
        _ reads: [(path: String, startLine: Int?, maxLines: Int?)],
        contextSize: Int
    ) -> ReadRepeatReport {
        struct Key: Hashable { let path: String; let start: Int; let max: Int }
        let tier = ReadWindow.defaultLines(contextSize: contextSize)
        var seen = Set<Key>()
        var byPath: [String: (calls: Int, windows: [Key: Int])] = [:]
        for (path, startLine, maxLines) in reads {
            let start = ReadWindow.effectiveStartLine(startLine)
            let maxL = ReadWindow.effectiveMaxLines(maxLines, default: tier)
            let key = Key(path: path, start: start, max: maxL)
            seen.insert(key)
            byPath[path, default: (0, [:])].calls += 1
            byPath[path, default: (0, [:])].windows[key, default: 0] += 1
        }
        let rows: [ReadRepeatReport.PathRow] = byPath
            .map { entry in
                let (path, data) = entry
                let repeated = data.windows
                    .filter { $0.value > 1 }
                    .map { ReadRepeatReport.RepeatedWindow(
                        startLine: $0.key.start, maxLines: $0.key.max, count: $0.value) }
                    .sorted { ($0.startLine, $0.maxLines) < ($1.startLine, $1.maxLines) }
                return ReadRepeatReport.PathRow(
                    path: path, calls: data.calls,
                    distinctWindows: data.windows.count,
                    repeatedWindows: repeated)
            }
            .sorted {
                if $0.calls != $1.calls { return $0.calls > $1.calls }
                return $0.path < $1.path
            }
        return ReadRepeatReport(
            calls: reads.count,
            distinctPairs: seen.count,
            sameWindowRepeats: reads.count - seen.count,
            paths: rows)
    }
}
