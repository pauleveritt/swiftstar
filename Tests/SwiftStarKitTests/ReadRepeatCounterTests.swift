import Testing
@testable import SwiftStarKit

struct ReadRepeatCounterTests {
    @Test func identicalWindowReaskedCountsAsSameWindowReRead() {
        let reads: [(path: String, startLine: Int?, maxLines: Int?)] = [
            (path: "a.swift", startLine: 250, maxLines: 90),
            (path: "a.swift", startLine: 250, maxLines: 90),
        ]
        let report = ReadRepeatCounter.summarize(reads, contextSize: 32768)
        #expect(report.calls == 2)
        #expect(report.distinctPairs == 1)
        #expect(report.sameWindowRepeats == 1)
        #expect(report.paths.count == 1)
        #expect(report.paths[0].repeatedWindows == [
            ReadRepeatReport.RepeatedWindow(startLine: 250, maxLines: 90, count: 2)
        ])
    }

    @Test func distinctWindowsOnOnePathAreNotRepeats() {
        // The 255/90 -> 257/90 walk-forward from the treatment capture: two
        // different windows of one file are healthy, not a same-window re-read.
        let reads: [(path: String, startLine: Int?, maxLines: Int?)] = [
            (path: "a.swift", startLine: 255, maxLines: 90),
            (path: "a.swift", startLine: 257, maxLines: 90),
        ]
        let report = ReadRepeatCounter.summarize(reads, contextSize: 32768)
        #expect(report.sameWindowRepeats == 0)
        #expect(report.distinctPairs == 2)
        #expect(report.paths[0].repeatedWindows.isEmpty)
    }

    @Test func bareReadCollidesWithExplicitTierRead() {
        // The load-bearing rule: a bare read and `start=1,max=500` deliver the
        // same head of the file at the 32768 tier, so they are ONE window.
        let reads: [(path: String, startLine: Int?, maxLines: Int?)] = [
            (path: "a.swift", startLine: nil, maxLines: nil),
            (path: "a.swift", startLine: 1, maxLines: 500),
        ]
        let report = ReadRepeatCounter.summarize(reads, contextSize: 32768)
        #expect(report.distinctPairs == 1)
        #expect(report.sameWindowRepeats == 1)
    }

    @Test func bareReReadsCountAsSameWindowRepeats() {
        // The control's "4x bare" signature: three whole-file re-asks are three
        // same-window re-reads; a windowed read of the same path is a distinct
        // window, not a repeat of the bare read.
        let reads: [(path: String, startLine: Int?, maxLines: Int?)] = [
            (path: "a.swift", startLine: nil, maxLines: nil),
            (path: "a.swift", startLine: nil, maxLines: nil),
            (path: "a.swift", startLine: nil, maxLines: nil),
            (path: "a.swift", startLine: 1, maxLines: 80),
        ]
        let report = ReadRepeatCounter.summarize(reads, contextSize: 32768)
        #expect(report.calls == 4)
        #expect(report.distinctPairs == 2)
        #expect(report.sameWindowRepeats == 2)
    }

    @Test func sameWindowOnDifferentPathsAreNotRepeats() {
        let reads: [(path: String, startLine: Int?, maxLines: Int?)] = [
            (path: "a.swift", startLine: 1, maxLines: 10),
            (path: "b.swift", startLine: 1, maxLines: 10),
        ]
        let report = ReadRepeatCounter.summarize(reads, contextSize: 32768)
        #expect(report.sameWindowRepeats == 0)
        #expect(report.distinctPairs == 2)
    }

    @Test func equalCountPathsSortByPathDeterministically() {
        let reads: [(path: String, startLine: Int?, maxLines: Int?)] = [
            (path: "b.swift", startLine: 1, maxLines: 10),
            (path: "a.swift", startLine: 1, maxLines: 10),
        ]
        let report = ReadRepeatCounter.summarize(reads, contextSize: 32768)
        #expect(report.paths.map { $0.path } == ["a.swift", "b.swift"])
    }
}
