import Testing
@testable import SwiftStarKit

struct SubagentPoolSizeTests {
    @Test func clampsBelowMinimum() { #expect(SubagentPoolSize.clamp(0) == 1) }
    @Test func clampsAboveMaximum() { #expect(SubagentPoolSize.clamp(99) == 8) }
    @Test func passesThroughInRange() { #expect(SubagentPoolSize.clamp(2) == 2) }
}
