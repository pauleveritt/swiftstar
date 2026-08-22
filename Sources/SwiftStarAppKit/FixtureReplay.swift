import Foundation

/// Replays the bundled `golden.ndjson` capture through the wire parser so the
/// lead dials have data before P7. Single pass, no loop; default ~30 lines/sec.
public enum FixtureReplay {
    public static func lines(cadenceNanoseconds: UInt64 = 33_000_000) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                guard let url = Bundle.module.url(forResource: "golden", withExtension: "ndjson"),
                      let text = try? String(contentsOf: url, encoding: .utf8) else {
                    continuation.finish()
                    return
                }
                for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
                    if Task.isCancelled { break }
                    let s = String(line)
                    guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    continuation.yield(s)
                    do {
                        try await Task.sleep(nanoseconds: cadenceNanoseconds)
                    } catch {
                        break  // cancelled: stop yielding to a terminated stream
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
