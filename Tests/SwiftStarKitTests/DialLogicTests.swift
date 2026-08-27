import Testing
@testable import SwiftStarKit

struct DialLogicTests {
    @Test func contextThresholdsAreAbsolute() {
        #expect(DialLogic.contextSeverity(ctxUsed: 10_000) == .healthy)
        #expect(DialLogic.contextSeverity(ctxUsed: 25_000) == .warning)
        #expect(DialLogic.contextSeverity(ctxUsed: 37_499) == .warning)
        #expect(DialLogic.contextSeverity(ctxUsed: 37_500) == .critical)
        #expect(DialLogic.contextSeverity(ctxUsed: 51_200) == .critical)  // the app's 50k — critical reachable
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

    @Test func sanitizeClampsNonFiniteAndWatts() {
        // +∞ passes the old NaN/negative clamp; it must be clamped to 0.
        let raw = MachineSnapshot(residentBytes: nil, watts: .infinity, gpuUtilization: .infinity, cpuUtilization: .nan)
        let clean = DialLogic.sanitize(raw)
        #expect(clean.watts == 0)
        #expect(clean.gpuUtilization == 0)
        #expect(clean.cpuUtilization == 0)
        // A garbage IOReport watts delta must not render as 9.2e18 W.
        let huge = MachineSnapshot(residentBytes: nil, watts: 1_000_000, gpuUtilization: 5, cpuUtilization: 5)
        #expect(DialLogic.sanitize(huge).watts == DialLogic.wattsMax)
    }
}
