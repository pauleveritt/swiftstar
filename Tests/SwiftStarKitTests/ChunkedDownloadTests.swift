import Testing
import Foundation
@testable import SwiftStarKit

struct ChunkedDownloadTests {
    @Test func bitmapRoundTrip() throws {
        var b = DownloadBitmap(chunkCount: 10)
        b.set(0); b.set(3); b.set(9)
        #expect(b.isSet(0) && b.isSet(3) && b.isSet(9))
        #expect(!b.isSet(1))
        #expect(b.completedCount == 3)
        let data = b.serialize()
        let restored = try DownloadBitmap.deserialize(data, chunkCount: 10)
        #expect(restored == b)
    }

    @Test func bitmapRejectsWidthMismatch() {
        let b = DownloadBitmap(chunkCount: 10)
        #expect(throws: DownloadBitmapError.self) {
            _ = try DownloadBitmap.deserialize(b.serialize(), chunkCount: 20)
        }
    }

    @Test func bitmapCompletedCountIgnoresUnusedBits() {
        // 3 chunks fit in one 64-bit word; the high unused bits must not count.
        var b = DownloadBitmap(chunkCount: 3)
        b.set(0); b.set(1); b.set(2)
        #expect(b.completedCount == 3)
    }

    @Test func planChunkCountAndRanges() {
        let plan = ChunkedPlan(chunkSize: 100)
        #expect(plan.chunkCount(forTotalBytes: 250) == 3)
        #expect(plan.range(forChunk: 0, totalBytes: 250) == 0..<100)
        #expect(plan.range(forChunk: 1, totalBytes: 250) == 100..<200)
        #expect(plan.range(forChunk: 2, totalBytes: 250) == 200..<250)
    }

    @Test func planProgressAndMissing() {
        let plan = ChunkedPlan(chunkSize: 100)
        var bitmap = DownloadBitmap(chunkCount: 3)
        bitmap.set(0)
        #expect(plan.completedBytes(bitmap: bitmap, totalBytes: 250) == 100)
        #expect(plan.missingChunkIndices(bitmap: bitmap) == [1, 2])
        #expect(!plan.isComplete(bitmap: bitmap))
        bitmap.set(1); bitmap.set(2)
        #expect(plan.completedBytes(bitmap: bitmap, totalBytes: 250) == 250)
        #expect(plan.isComplete(bitmap: bitmap))
    }

    @Test func emptyBitmapSerializesStably() throws {
        let a = DownloadBitmap(chunkCount: 5).serialize()
        let b = DownloadBitmap(chunkCount: 5).serialize()
        #expect(a == b)
    }
}
