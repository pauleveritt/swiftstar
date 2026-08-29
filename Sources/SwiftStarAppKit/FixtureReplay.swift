import Foundation

/// Replays the bundled `golden.ndjson` capture through the wire parser so the
/// lead dials have data before P7. Single pass, no loop; default ~30 lines/sec.
///
/// `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}` are byte-identical
/// copies of `fixtures/agent/golden.{ndjson,trace}` — SwiftPM resource
/// bundling (`.process("Resources")` in `Package.swift`) needs a real file
/// inside the target's own tree, so the fixture used by tests and the copy
/// shipped in the app bundle cannot be the same file on disk. A relative
/// symlink was tried and rejected (2026-08-29): SwiftPM's resource copy step
/// preserves the symlink rather than dereferencing it, and the relative
/// target breaks once relocated into `.build/.../SwiftStar_SwiftStarAppKit.bundle/`
/// (`Bundle.module.url(forResource:)` then resolves to a dangling link).
/// **On every recapture, update both copies together** — this is manual;
/// `Tests/SwiftStarIntegrationTests/FixtureReplayTests.bundledFixtureMatchesRepoFixture`
/// is the drift detector, not a sync mechanism. See
/// `fixtures/agent/provenance.md`'s "Recapture rule" for the full history.
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
