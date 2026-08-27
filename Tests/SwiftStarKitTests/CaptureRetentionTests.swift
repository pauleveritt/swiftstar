import Testing
import Foundation
@testable import SwiftStarKit

struct CaptureRetentionTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)  // fixed reference instant

    private func daysAgo(_ n: Int) -> Date {
        Self.now.addingTimeInterval(-Double(n) * 86_400)
    }

    private func entry(_ name: String, daysAgo n: Int, sizeBytes: Int64 = 1_024) -> CaptureEntry {
        CaptureEntry(name: name, modified: daysAgo(n), sizeBytes: sizeBytes)
    }

    @Test func emptyListDeletesNothing() {
        let result = CaptureRetention.directoriesToDelete(
            entries: [], policy: CaptureRetentionPolicy(), now: Self.now)
        #expect(result.isEmpty)
    }

    @Test func listShorterThanKeepCountKeepsEverythingRegardlessOfAge() {
        // 5 entries, all ancient, keepCount 20: the count rule alone keeps all 5.
        let entries = (0..<5).map { entry("dir\($0)", daysAgo: 400) }
        let result = CaptureRetention.directoriesToDelete(
            entries: entries, policy: CaptureRetentionPolicy(keepCount: 20, keepDays: 14), now: Self.now)
        #expect(result.isEmpty)
    }

    @Test func oldDirectoriesBeyondBothCutoffsAreDeleted() {
        // 25 entries, one per day going back 25 days; keepCount 20, keepDays 14.
        // Directories 0...19 (0-19 days old) are kept by the count rule.
        // Directories 20...24 are older than 14 days AND outside the top 20 —
        // deleted.
        let entries = (0..<25).map { entry("dir\($0)", daysAgo: $0) }
        let result = CaptureRetention.directoriesToDelete(
            entries: entries, policy: CaptureRetentionPolicy(keepCount: 20, keepDays: 14), now: Self.now)
        let deletedNames = Set(result.map(\.name))
        #expect(deletedNames == Set(["dir20", "dir21", "dir22", "dir23", "dir24"]))
    }

    @Test func recentDirectoryOutsideTopCountIsKeptByAge() {
        // keepCount 1: only the single most recent is kept by count. A second
        // directory, 2 days old (within the 14-day window), must still survive
        // via the age rule — proving the union, not just the count rule, applies.
        let entries = [
            entry("newest", daysAgo: 0),
            entry("recent-but-not-top1", daysAgo: 2),
        ]
        let result = CaptureRetention.directoriesToDelete(
            entries: entries, policy: CaptureRetentionPolicy(keepCount: 1, keepDays: 14), now: Self.now)
        #expect(result.isEmpty)
    }

    @Test func oldDirectoryWithinTopCountIsKeptByCount() {
        // All 3 entries are older than the 14-day cutoff, but keepCount 3 keeps
        // all of them — the count rule alone can keep an entry the age rule
        // would have discarded.
        let entries = [
            entry("a", daysAgo: 100),
            entry("b", daysAgo: 200),
            entry("c", daysAgo: 300),
        ]
        let result = CaptureRetention.directoriesToDelete(
            entries: entries, policy: CaptureRetentionPolicy(keepCount: 3, keepDays: 14), now: Self.now)
        #expect(result.isEmpty)
    }

    @Test func boundaryExactlyAtAgeCutoffIsKept() {
        // Exactly `keepDays` old (14.0 days), outside the top count: the cutoff
        // comparison is strict (`modified < cutoff`), so exactly-at-the-boundary
        // is still "recent" and kept.
        let entries = [
            entry("newer1", daysAgo: 0),
            entry("newer2", daysAgo: 1),
            entry("boundary", daysAgo: 14),
        ]
        let result = CaptureRetention.directoriesToDelete(
            entries: entries, policy: CaptureRetentionPolicy(keepCount: 2, keepDays: 14), now: Self.now)
        #expect(result.isEmpty)
    }

    @Test func justOverTheAgeCutoffAndOutsideCountIsDeleted() {
        let entries = [
            entry("newer1", daysAgo: 0),
            entry("newer2", daysAgo: 1),
            entry("just-over", daysAgo: 15),
        ]
        let result = CaptureRetention.directoriesToDelete(
            entries: entries, policy: CaptureRetentionPolicy(keepCount: 2, keepDays: 14), now: Self.now)
        #expect(result.map(\.name) == ["just-over"])
    }

    @Test func evidenceIsNeverDeletedEvenWhenFedIn() {
        // Sanity check per the spec: even if a caller's entry list mistakenly
        // includes an "evidence" directory, ancient and outside every keep
        // window, the pure function refuses to select it.
        let entries = [
            CaptureEntry(name: "evidence", modified: daysAgo(9_999), sizeBytes: 999_999),
            entry("dir0", daysAgo: 9_999),
        ]
        let result = CaptureRetention.directoriesToDelete(
            entries: entries, policy: CaptureRetentionPolicy(keepCount: 0, keepDays: 0), now: Self.now)
        #expect(!result.map(\.name).contains("evidence"))
        #expect(result.map(\.name) == ["dir0"])
    }

    @Test func zeroKeepCountAndZeroKeepDaysDeletesEverythingButEvidence() {
        // daysAgo 1/2 (not 0): keepDays 0 makes the cutoff exactly "now," and
        // the boundary comparison is strict (see boundaryExactlyAtAgeCutoffIsKept),
        // so an entry modified exactly at "now" would be kept, not deleted —
        // these are both strictly older.
        let entries = [
            entry("a", daysAgo: 1),
            entry("b", daysAgo: 2),
            CaptureEntry(name: "evidence", modified: daysAgo(999), sizeBytes: 1),
        ]
        let result = CaptureRetention.directoriesToDelete(
            entries: entries, policy: CaptureRetentionPolicy(keepCount: 0, keepDays: 0), now: Self.now)
        #expect(Set(result.map(\.name)) == Set(["a", "b"]))
    }

    @Test func sizeBytesPassesThroughForCallerLogging() {
        let entries = [entry("stale", daysAgo: 999, sizeBytes: 42_000_000)]
        let result = CaptureRetention.directoriesToDelete(
            entries: entries, policy: CaptureRetentionPolicy(keepCount: 0, keepDays: 0), now: Self.now)
        #expect(result.first?.sizeBytes == 42_000_000)
    }

    @Test func negativeKeepCountBehavesLikeZero() {
        let entries = [entry("a", daysAgo: 999)]
        let result = CaptureRetention.directoriesToDelete(
            entries: entries, policy: CaptureRetentionPolicy(keepCount: -5, keepDays: 0), now: Self.now)
        #expect(result.map(\.name) == ["a"])
    }
}
