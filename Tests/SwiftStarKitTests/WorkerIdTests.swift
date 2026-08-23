import Foundation
import Testing
@testable import SwiftStarKit

struct WorkerIdTests {
    @Test func orchestratorIsZero() {
        #expect(WorkerId.orchestrator.rawValue == 0)
    }
    @Test func orderingFollowsRawValue() {
        #expect(WorkerId(2) > WorkerId(1))
        #expect(WorkerId(1) < WorkerId(2))
    }
    @Test func roundTripsThroughCodable() throws {
        let id = WorkerId(7)
        let data = try JSONEncoder().encode(id)
        #expect(try JSONDecoder().decode(WorkerId.self, from: data) == id)
    }
}
