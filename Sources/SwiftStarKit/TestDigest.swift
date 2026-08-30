import Foundation

/// Clusters test failures by (file, message signature) so every failure in a
/// cluster maps to the same edit; emits ≤2 representatives plus counts.
/// Parses either pytest's `--json-report` JSON (Task 5) or `swift test`'s
/// XCTest text, sharing one clustering core. Total over `CommandOutput`.
public enum TestDigest {
    public struct Failure: Equatable, Sendable {
        public let testID: String
        public let file: String
        public let line: Int?
        public let message: String
    }

    static let maxClusters = 2

    public static func digest(_ out: CommandOutput, command: String, artifactPath: String) -> ToolDigest {
        let (failures, passed): ([Failure], Int?)
        if let parsed = parsePytestJSON(out.stdout) {
            (failures, passed) = parsed
        } else {
            (failures, passed) = (parseXCTestText(out.stdout), nil)
        }
        let summary = summarize(out: out, command: command, artifactPath: artifactPath,
                                failures: failures, passed: passed)
        return ToolDigest(summary: summary, command: command,
                          artifactPath: artifactPath,
                          outputDigest: ToolDigest.sha256(out.stdout))
    }

    // MARK: - XCTest text parser (Task 4)

    /// `swift test` emits `<file>:<line>: error: <testID> : <message>` lines.
    static func parseXCTestText(_ stdout: String) -> [Failure] {
        let pattern = #"^(.*\.swift):(\d+): error: (.+?) : (.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var failures: [Failure] = []
        for line in stdout.split(separator: "\n") {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            guard let m = regex.firstMatch(in: s, range: range),
                  m.numberOfRanges == 5 else { continue }
            failures.append(Failure(
                testID: String(s[Range(m.range(at: 3), in: s)!]),
                file: String(s[Range(m.range(at: 1), in: s)!]),
                line: Int(s[Range(m.range(at: 2), in: s)!]),
                message: String(s[Range(m.range(at: 4), in: s)!])))
        }
        return failures
    }

    /// Parses `pytest --json-report` stdout: the `summary.passed` count and,
    /// for each failed test, a `Failure` keyed by (file-from-nodeid, the last
    /// `E   ` assertion line of `call.longrepr`). Returns nil when the stdout
    /// is not that shape (fall back to the XCTest text path).
    static func parsePytestJSON(_ stdout: String) -> ([Failure], Int?)? {
        guard let data = stdout.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tests = obj["tests"] as? [[String: Any]] else { return nil }
        var failures: [Failure] = []
        var passed: Int? = nil
        if let summary = obj["summary"] as? [String: Any],
           let p = summary["passed"] as? Int { passed = p }
        for t in tests {
            guard t["outcome"] as? String == "failed",
                  let nodeid = t["nodeid"] as? String else { continue }
            let file = nodeid.components(separatedBy: "::")[0]
            let message: String
            if let call = t["call"] as? [String: Any],
               let longrepr = call["longrepr"] as? String {
                let assertionLines = longrepr.split(separator: "\n")
                    .filter { $0.hasPrefix("E   ") }
                message = assertionLines.last.map {
                    String($0.dropFirst(4))
                } ?? longrepr.split(separator: "\n").first.map(String.init) ?? "unknown failure"
            } else {
                message = "unknown failure"
            }
            failures.append(Failure(testID: nodeid, file: file, line: nil, message: message))
        }
        return (failures, passed)
    }

    // MARK: - clustering core (shared)

    typealias Cluster = (key: (file: String, message: String), failures: [Failure])

    /// Absolute paths (XCTest) display as basenames; relative paths (pytest
    /// nodeids) display as-is. The cluster *key* always keeps the full path —
    /// two same-named files in different directories are different fixes.
    static func displayFile(_ file: String) -> String {
        file.hasPrefix("/") ? URL(fileURLWithPath: file).lastPathComponent : file
    }

    static func makeClusters(_ failures: [Failure]) -> [Cluster] {
        var byKey: [(key: (file: String, message: String), failures: [Failure])] = []
        for f in failures {
            let key = (f.file, f.message)
            if let i = byKey.firstIndex(where: { $0.key == key }) {
                byKey[i].failures.append(f)
            } else {
                byKey.append((key: key, failures: [f]))
            }
        }
        return byKey.sorted { $0.failures.count > $1.failures.count }
    }

    static func summarize(out: CommandOutput, command: String, artifactPath: String,
                          failures: [Failure], passed: Int?) -> String {
        let exitLabel = out.timedOut ? "timed out" : "exit \(out.exit)"
        let clusters = makeClusters(failures)
        var lines: [String] = []
        if let passed, !failures.isEmpty {
            lines.append("test: \(passed) passed, \(failures.count) failed (\(exitLabel))")
        } else if failures.isEmpty && !out.timedOut && out.exit == 0 {
            lines.append("test: all passed (\(exitLabel))")
        } else if failures.isEmpty {
            lines.append("test: no failures parsed (\(exitLabel))")
        } else {
            lines.append("test: \(failures.count) failures in \(clusters.count) cluster\(clusters.count == 1 ? "" : "s") (\(exitLabel))")
        }
        lines.append("Ran: \(command)")
        for (i, cluster) in clusters.prefix(maxClusters).enumerated() {
            let rep = cluster.failures[0]
            let count = cluster.failures.count
            lines.append("[\(i + 1)] \(displayFile(cluster.key.file)) — \(count) failure\(count == 1 ? "" : "s")")
            lines.append("    \(rep.testID)")
            if let line = rep.line {
                lines.append("    \(rep.message)   (\(displayFile(rep.file)):\(line))")
            } else {
                lines.append("    \(rep.message)   (\(displayFile(rep.file)))")
            }
        }
        if clusters.count > maxClusters {
            lines.append("and \(clusters.count - maxClusters) more clusters (see full output)")
        }
        lines.append("full output: \(artifactPath)")
        return lines.joined(separator: "\n")
    }
}
