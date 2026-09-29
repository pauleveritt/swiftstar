import Testing
@testable import SwiftStarKit

struct SeverityTests {
    @Test func twentyThousandWindowReachesCritical() {
        #expect(Severity.ofContext(used: 15000, size: 20000) == .critical)
        #expect(Severity.ofContext(used: 10000, size: 20000) == .warning)
        #expect(Severity.ofContext(used: 9999, size: 20000) == .healthy)
        #expect(Severity.ofContext(used: nil, size: 20000) == .healthy)
        #expect(Severity.ofContext(used: 100, size: nil) == .healthy)
        #expect(Severity.ofContext(used: 100, size: 0) == .healthy)
    }

    @Test func boundariesAndNegativeUsed() {
        #expect(Severity.ofContext(used: 14999, size: 20000) == .warning)
        #expect(Severity.ofContext(used: 15000, size: 20000) == .critical)
        #expect(Severity.ofContext(used: 9999, size: 20000) == .healthy)
        #expect(Severity.ofContext(used: 10000, size: 20000) == .warning)
        #expect(Severity.ofContext(used: -5, size: 20000) == .healthy)
    }
}
