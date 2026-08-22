import Foundation

public enum DownloadBitmapError: Error, Equatable, Sendable {
    case widthMismatch(expectedWords: Int, actualWords: Int)
}

/// Fixed-width bitset over download chunks. The last word's high bits are
/// unused and never counted (set() never touches them).
public struct DownloadBitmap: Equatable, Sendable {
    public private(set) var words: [UInt64]
    public let chunkCount: Int

    public init(chunkCount: Int) {
        self.chunkCount = chunkCount
        self.words = [UInt64](repeating: 0, count: (chunkCount + 63) / 64)
    }

    public mutating func set(_ index: Int) {
        precondition(index >= 0 && index < chunkCount)
        words[index / 64] |= (1 << UInt64(index % 64))
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
        let expected = (chunkCount + 63) / 64
        let actual = data.count / 8
        guard actual == expected else {
            throw DownloadBitmapError.widthMismatch(expectedWords: expected, actualWords: actual)
        }
        var bitmap = DownloadBitmap(chunkCount: chunkCount)
        data.withUnsafeBytes { raw in
            for i in 0..<expected {
                bitmap.words[i] = raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self).littleEndian
            }
        }
        return bitmap
    }
}

/// Chunk arithmetic for a resumable parallel download.
public struct ChunkedPlan: Equatable, Sendable {
    public let chunkSize: Int

    public init(chunkSize: Int = 16 * 1024 * 1024) {
        self.chunkSize = chunkSize
    }

    public func chunkCount(forTotalBytes total: Int64) -> Int {
        Int((total + Int64(chunkSize) - 1) / Int64(chunkSize))
    }

    public func range(forChunk index: Int, totalBytes total: Int64) -> Range<Int64> {
        let start = Int64(index) * Int64(chunkSize)
        let end = min(start + Int64(chunkSize), total)
        return start..<end
    }

    public func completedBytes(bitmap: DownloadBitmap, totalBytes total: Int64) -> Int64 {
        (0..<bitmap.chunkCount).reduce(Int64(0)) { acc, i in
            bitmap.isSet(i) ? acc + Int64(range(forChunk: i, totalBytes: total).count) : acc
        }
    }

    public func missingChunkIndices(bitmap: DownloadBitmap) -> [Int] {
        (0..<bitmap.chunkCount).filter { !bitmap.isSet($0) }
    }

    public func isComplete(bitmap: DownloadBitmap) -> Bool {
        missingChunkIndices(bitmap: bitmap).isEmpty
    }
}
