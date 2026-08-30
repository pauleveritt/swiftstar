import Foundation
import Testing
@testable import SwiftStarKit

struct TranscriptFontScaleTests {
    @Test func fourAscendingSizes() {
        #expect(TranscriptFontScale.sizes == [12, 14, 16, 20])
    }

    @Test func defaultIsThirdSlotNextToLargest() {
        #expect(TranscriptFontScale.defaultSize == 16)
        #expect(TranscriptFontScale.sizes[2] == TranscriptFontScale.defaultSize)
        #expect(TranscriptFontScale.sizes[3] == 20)  // the largest
    }

    @Test func clampKeepsValidSizes() {
        #expect(TranscriptFontScale.clamp(16) == 16)
        #expect(TranscriptFontScale.clamp(14) == 14)
        #expect(TranscriptFontScale.clamp(20) == 20)
    }

    @Test func clampPullsOutOfRangeToNearestSlot() {
        #expect(TranscriptFontScale.clamp(0) == 12)
        #expect(TranscriptFontScale.clamp(100) == 20)
        #expect(TranscriptFontScale.clamp(13) == 12)  // equidistant from 12 and 14 → smaller
        #expect(TranscriptFontScale.clamp(17) == 16)  // 1 from 16, 3 from 20 → 16
    }

    @Test func clampTiesResolveToSmallerSize() {
        // 15 is equidistant from 14 and 16; ties resolve to the smaller size.
        #expect(TranscriptFontScale.clamp(15) == 14)
    }

    @Test func clampReachesTheLargestSlotFromBelow() {
        // The gap above 16 is now 4 pt, not 2 — nothing between 18 and 20
        // rounds down. Pins the new largest slot as reachable by the clamp,
        // which [12, 14, 16, 18] could not express.
        #expect(TranscriptFontScale.clamp(19) == 20)
        #expect(TranscriptFontScale.clamp(21) == 20)
    }

    @Test func storedOldLargestDemotesToDefault() {
        // 18 was the largest slot before the scale widened. It is now
        // equidistant from 16 and 20, so the tie rule lands it on 16: a user
        // who had picked the old maximum reopens at the default, not at the
        // new maximum. Pinned deliberately — silent, and the tie rule's doing.
        #expect(TranscriptFontScale.clamp(18) == 16)
    }
}
