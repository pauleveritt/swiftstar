import Foundation
import Testing
@testable import SwiftStarKit

struct TranscriptFontScaleTests {
    /// fourAscendingSizes, defaultIsThirdSlotNextToLargest.
    @Test func scale() {
        #expect(TranscriptFontScale.sizes == [12, 14, 16, 20])
        #expect(TranscriptFontScale.defaultSize == 16)
    }

    struct ClampCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let size: Int
        let clamped: Int
    }

    static let clampCases: [ClampCase] = [
        .init(testDescription: "clampKeepsValidSizes (12)", size: 12, clamped: 12),
        .init(testDescription: "clampKeepsValidSizes (14)", size: 14, clamped: 14),
        .init(testDescription: "clampKeepsValidSizes (16)", size: 16, clamped: 16),
        .init(testDescription: "clampKeepsValidSizes (20)", size: 20, clamped: 20),
        .init(testDescription: "clampPullsOutOfRangeToNearestSlot (0)", size: 0, clamped: 12),
        .init(testDescription: "clampPullsOutOfRangeToNearestSlot (100)", size: 100, clamped: 20),
        .init(testDescription: "clampPullsOutOfRangeToNearestSlot (13, tie → smaller)", size: 13, clamped: 12),
        .init(testDescription: "clampPullsOutOfRangeToNearestSlot (17, nearer 16)", size: 17, clamped: 16),
        .init(testDescription: "clampTiesResolveToSmallerSize (15)", size: 15, clamped: 14),
        // Nothing between 18 and 20 rounds down to 16 except the tie at 18.
        .init(testDescription: "clampReachesTheLargestSlotFromBelow (19)", size: 19, clamped: 20),
        .init(testDescription: "clampReachesTheLargestSlotFromBelow (21)", size: 21, clamped: 20),
        // 18 was the largest slot before the scale widened. The tie rule lands
        // it on 16: a user who had picked the old maximum reopens at the
        // default, not the new maximum. Pinned deliberately.
        .init(testDescription: "storedOldLargestDemotesToDefault (18)", size: 18, clamped: 16),
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
}
