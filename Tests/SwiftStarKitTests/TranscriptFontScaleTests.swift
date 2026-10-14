import Foundation
import Testing
@testable import SwiftStarKit

struct TranscriptFontScaleTests {
    /// Five ascending sizes; the middle one, 18, is the default (SU.9).
    @Test func scale() {
        #expect(TranscriptFontScale.sizes == [14, 16, 18, 20, 24])
        #expect(TranscriptFontScale.defaultSize == 18)
        #expect(TranscriptFontScale.slot(for: TranscriptFontScale.defaultSize) == 2)
    }

    struct ClampCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let size: Int
        let clamped: Int
    }

    static let clampCases: [ClampCase] = [
        .init(testDescription: "clampKeepsValidSizes (14)", size: 14, clamped: 14),
        .init(testDescription: "clampKeepsValidSizes (18)", size: 18, clamped: 18),
        .init(testDescription: "clampKeepsValidSizes (24)", size: 24, clamped: 24),
        .init(testDescription: "clampPullsOutOfRangeToNearestSlot (0)", size: 0, clamped: 14),
        .init(testDescription: "clampPullsOutOfRangeToNearestSlot (100)", size: 100, clamped: 24),
        .init(testDescription: "clampTiesResolveToSmallerSize (17)", size: 17, clamped: 16),
        .init(testDescription: "clampTiesResolveToSmallerSize (22)", size: 22, clamped: 20),
        .init(testDescription: "clampPullsToNearest (23)", size: 23, clamped: 24),
        // The old scale's smallest, 12, lands on the new smallest.
        .init(testDescription: "storedOldSmallest (12)", size: 12, clamped: 14),
    ]

    @Test(arguments: clampCases) func clamp(_ c: ClampCase) {
        #expect(TranscriptFontScale.clamp(c.size) == c.clamped)
    }

    @Test func fontSlotRoundTrip() {
        for s in TranscriptFontScale.sizes {
            #expect(TranscriptFontScale.size(forSlot: TranscriptFontScale.slot(for: s)) == s)
        }
        #expect(TranscriptFontScale.slot(for: 999) == TranscriptFontScale.sizes.count - 1)
        #expect(TranscriptFontScale.size(forSlot: 99) == TranscriptFontScale.sizes.last)
        #expect(TranscriptFontScale.size(forSlot: -3) == TranscriptFontScale.sizes.first)
    }

    /// The roles keep macOS's proportions to its 13 pt body.
    @Test func rolePoints() {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }
        #expect(TranscriptFontScale.points(.headline, base: 18) == 18)
        #expect(near(TranscriptFontScale.points(.caption, base: 18), 14.4))
        #expect(near(TranscriptFontScale.points(.caption2, base: 18), 12.96))
        #expect(near(TranscriptFontScale.points(.caption, base: 14), 11.2))
    }

    /// View › Bigger and Smaller step one slot; nil at either end (SU.6f).
    @Test func steps() {
        #expect(TranscriptFontScale.bigger(18) == 20)
        #expect(TranscriptFontScale.smaller(18) == 16)
        #expect(TranscriptFontScale.bigger(24) == nil)
        #expect(TranscriptFontScale.smaller(14) == nil)
        // An off-scale value steps from the slot it clamps to (21 → 20).
        #expect(TranscriptFontScale.bigger(21) == 24)
        #expect(TranscriptFontScale.smaller(21) == 18)
    }
}
