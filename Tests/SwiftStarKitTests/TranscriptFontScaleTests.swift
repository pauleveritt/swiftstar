import Foundation
import Testing
@testable import SwiftStarKit

struct TranscriptFontScaleTests {
    @Test func fourAscendingSizes() {
        #expect(TranscriptFontScale.sizes == [12, 14, 16, 18])
    }

    @Test func defaultIsThirdSlotNextToLargest() {
        #expect(TranscriptFontScale.defaultSize == 16)
        #expect(TranscriptFontScale.sizes[2] == TranscriptFontScale.defaultSize)
        #expect(TranscriptFontScale.sizes[3] == 18)  // the largest
    }

    @Test func clampKeepsValidSizes() {
        #expect(TranscriptFontScale.clamp(16) == 16)
        #expect(TranscriptFontScale.clamp(14) == 14)
    }

    @Test func clampPullsOutOfRangeToNearestSlot() {
        #expect(TranscriptFontScale.clamp(0) == 12)
        #expect(TranscriptFontScale.clamp(100) == 18)
        #expect(TranscriptFontScale.clamp(13) == 12)  // equidistant from 12 and 14 → smaller
        #expect(TranscriptFontScale.clamp(17) == 16)  // equidistant from 16 and 18 → smaller
    }

    @Test func clampTiesResolveToSmallerSize() {
        // 15 is equidistant from 14 and 16; ties resolve to the smaller size.
        #expect(TranscriptFontScale.clamp(15) == 14)
    }
}
