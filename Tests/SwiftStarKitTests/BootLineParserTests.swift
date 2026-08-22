import Testing
@testable import SwiftStarKit

struct BootLineParserTests {
    @Test func parsesPlannedGib() {
        let line = "ds4: memory: KV 1.57 GiB (raw 1.57 + compressed 0.00) + buffers 0.00 GiB + resident model 44.94 GiB = 46.51 GiB planned"
        let bytes = BootLineParser.plannedBytes(from: line)
        #expect(bytes != nil)
        // 46.51 GiB → integer bytes; within a GiB of the P1 fixture's planned_bytes.
        let expected = Int64(49_943_965_040)
        #expect(abs((bytes ?? 0) - expected) < 1_073_741_824)
    }

    @Test func nonMemoryLineReturnsNil() {
        #expect(BootLineParser.plannedBytes(from: "ds4: Metal device Apple M5 Max") == nil)
        #expect(BootLineParser.plannedBytes(from: "") == nil)
    }

    @Test func missingPlannedWordReturnsNil() {
        #expect(BootLineParser.plannedBytes(from: "ds4: memory: KV 1.57 GiB") == nil)
    }
}

    @Test func garbageValueReturnsNil() {
        // A nonsense magnitude must return nil, not trap on overflow.
        #expect(BootLineParser.plannedBytes(from: "ds4: memory: = 1e20 GiB planned") == nil)
        #expect(BootLineParser.plannedBytes(from: "ds4: memory: = -4 GiB planned") == nil)
    }

    @Test func earlierEqualsDoNotMislead() {
        // An "=" earlier in the line (e.g. a KV pair) must not break parsing.
        let line = "ds4: memory: name=test KV 1.57 GiB + resident model 44.94 GiB = 46.51 GiB planned"
        #expect(BootLineParser.plannedBytes(from: line) != nil)
    }
