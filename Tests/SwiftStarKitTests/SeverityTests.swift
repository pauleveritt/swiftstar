import Testing
@testable import SwiftStarKit

struct SeverityTests {
    // twentyThousandWindowReachesCritical, boundariesAndNegativeUsed.
    @Test(arguments: [
        (Int?.some(15000), Int?.some(20000), Severity.critical), (14999, 20000, .warning), (10000, 20000, .warning),
        (9999, 20000, .healthy), (-5, 20000, .healthy), (nil, 20000, .healthy), (100, nil, .healthy),
        (100, 0, .healthy),
    ]) func ofContext(_ used: Int?, _ size: Int?, _ severity: Severity) {
        #expect(Severity.ofContext(used: used, size: size) == severity)
    }
}
