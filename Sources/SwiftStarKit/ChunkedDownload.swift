import Foundation

public enum DownloadBitmapError: Error, Equatable, Sendable {
    case widthMismatch(expectedBytes: Int, actualBytes: Int)
}

/// Fixed-width bitset over download chunks. The last word's high bits are
/// unused and never counted: `set()` never touches them, and `deserialize`
/// masks them on load (so corrupt persisted data cannot overcount).
public struct DownloadBitmap: Equatable, Sendable {
    public private(set) var words: [UInt64]
    public let chunkCount: Int

    public init(chunkCount: Int) {
        precondition(chunkCount >= 0, "chunkCount must be non-negative")
        self.chunkCount = chunkCount
        self.words = [UInt64](repeating: 0, count: (chunkCount + 63) / 64)
    }

    public mutating func set(_ index: Int) {
        precondition(index >= 0 && index < chunkCount)
        words[index / 64] |= (1 << UInt64(index % 64))
    }

    public mutating func clear(_ index: Int) {
        guard index >= 0 && index < chunkCount else { return }
        words[index / 64] &= ~(1 << UInt64(index % 64))
    }

    public func isSet(_ index: Int) -> Bool {
        guard index >= 0 && index < chunkCount else { return false }
        return words[index / 64] & (1 << UInt64(index % 64)) != 0
    }

    public var completedCount: Int {
        words.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    public var isEmpty: Bool { completedCount == 0 }

    public func serialize() -> Data {
        var data = Data()
        for word in words {
            var le = word.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func deserialize(_ data: Data, chunkCount: Int) throws -> DownloadBitmap {
        let expectedWords = (chunkCount + 63) / 64
        // Exact byte length: truncation (e.g. 12 bytes for a 1-word bitmap)
        // must be rejected, not silently accepted via integer division.
        guard data.count == expectedWords * 8 else {
            throw DownloadBitmapError.widthMismatch(expectedBytes: expectedWords * 8, actualBytes: data.count)
        }
        var bitmap = DownloadBitmap(chunkCount: chunkCount)
        data.withUnsafeBytes { raw in
            for i in 0..<expectedWords {
                bitmap.words[i] = raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self).littleEndian
            }
        }
        // Mask stray high bits in the last word (persisted corruption must not
        // overcount completed chunks).
        let usedInLast = chunkCount % 64
        if usedInLast != 0, let last = bitmap.words.last {
            let mask = (UInt64(1) << UInt64(usedInLast)) - 1
            bitmap.words[bitmap.words.count - 1] = last & mask
        }
        return bitmap
    }
}

/// Chunk arithmetic for a resumable parallel download.
public struct ChunkedPlan: Equatable, Sendable {
    public let chunkSize: Int

    public init(chunkSize: Int = 16 * 1024 * 1024) {
        precondition(chunkSize > 0, "chunkSize must be positive")
        self.chunkSize = chunkSize
    }

    public func chunkCount(forTotalBytes total: Int64) -> Int {
        precondition(total >= 0, "total must be non-negative")
        return Int((total + Int64(chunkSize) - 1) / Int64(chunkSize))
    }

    public func range(forChunk index: Int, totalBytes total: Int64) -> Range<Int64> {
        precondition(index >= 0, "chunk index must be non-negative")
        let start = Int64(index) * Int64(chunkSize)
        let end = min(start + Int64(chunkSize), total)
        return start..<end
    }

    public func completedBytes(bitmap: DownloadBitmap, totalBytes total: Int64) -> Int64 {
        // Iterate the plan's own chunk count, not the bitmap's: the bitmap is
        // built from the plan, so the two agree by construction; this loop
        // guards the caller from passing a bitmap of a different width.
        let n = min(bitmap.chunkCount, chunkCount(forTotalBytes: total))
        return (0..<n).reduce(Int64(0)) { acc, i in
            bitmap.isSet(i) ? acc + Int64(range(forChunk: i, totalBytes: total).count) : acc
        }
    }

    public func missingChunkIndices(bitmap: DownloadBitmap) -> [Int] {
        (0..<bitmap.chunkCount).filter { !bitmap.isSet($0) }
    }

    public func isComplete(bitmap: DownloadBitmap) -> Bool {
        (0..<bitmap.chunkCount).allSatisfy { bitmap.isSet($0) }
    }
}
