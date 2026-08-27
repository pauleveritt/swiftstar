import Testing
@testable import SwiftStarKit

struct SubagentPoolSizeTests {
    @Test func clampsBelowMinimum() { #expect(SubagentPoolSize.clamp(0) == 2) }
    @Test func clampsAboveMaximum() { #expect(SubagentPoolSize.clamp(99) == 8) }
    @Test func passesThroughInRange() { #expect(SubagentPoolSize.clamp(2) == 2) }
    @Test func workerCapacityIsPoolMinusOne() {
        #expect(SubagentPoolSize.workerCapacity(2) == 1)
        #expect(SubagentPoolSize.workerCapacity(3) == 2)
        #expect(SubagentPoolSize.workerCapacity(8) == 7)
    }
    @Test func workerCapacityNeverBelowOne() {
        #expect(SubagentPoolSize.workerCapacity(1) == 1)  // pool 1 clamps to 2, minus 1
        #expect(SubagentPoolSize.workerCapacity(0) == 1)
    }
}
