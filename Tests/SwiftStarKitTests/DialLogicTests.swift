import Testing
@testable import SwiftStarKit

struct DialLogicTests {
    @Test func contextThresholdsAreAbsolute() {
        #expect(DialLogic.contextSeverity(ctxUsed: 10_000) == .healthy)
        #expect(DialLogic.contextSeverity(ctxUsed: 37_500) == .warning)
        #expect(DialLogic.contextSeverity(ctxUsed: 74_999) == .warning)
        #expect(DialLogic.contextSeverity(ctxUsed: 75_000) == .critical)
        #expect(DialLogic.contextSeverity(ctxUsed: 92_500) == .critical)  // the measured ~7x point
    }

    @Test func memoryThresholdsAreGeneric() {
        #expect(DialLogic.memorySeverity(residentBytes: 60, plannedBytes: 100) == .healthy)
        #expect(DialLogic.memorySeverity(residentBytes: 70, plannedBytes: 100) == .warning)
        #expect(DialLogic.memorySeverity(residentBytes: 90, plannedBytes: 100) == .critical)
        #expect(DialLogic.memorySeverity(residentBytes: 50, plannedBytes: 0) == .healthy)  // no budget
    }

    @Test func fixedWidthPadsToWidth() {
        #expect(DialLogic.fixedWidth("41.2", width: 8) == "    41.2")
        #expect(DialLogic.fixedWidth("128340", width: 8) == "  128340")
        #expect(DialLogic.fixedWidth("12345678", width: 8) == "12345678")
    }

    @Test func sanitizeClampsGarbage() {
        let raw = MachineSnapshot(residentBytes: -5, watts: .nan, gpuUtilization: -1, cpuUtilization: 99.0)
        let clean = DialLogic.sanitize(raw)
        #expect(clean.residentBytes == 0)
        #expect(clean.watts == 0)
        #expect(clean.gpuUtilization == 0)
        #expect(clean.cpuUtilization == 99.0)  // clean values pass through
    }

    @Test func sanitizePassesThroughCleanValues() {
        let raw = MachineSnapshot(residentBytes: 1024, watts: 0.8, gpuUtilization: 98.0, cpuUtilization: 6.5)
        #expect(DialLogic.sanitize(raw) == raw)
    }
}
