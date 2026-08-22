import Foundation
import Observation
import SwiftStarKit

public enum DownloadState: Equatable {
    case idle
    case downloading(fraction: Double)
    case done(URL)
    case failed(String)
}

public struct DownloadSpec: Equatable, Sendable {
    public var url: URL
    public var destination: URL
    public var chunkSize: Int
    public var maxConcurrency: Int

    public init(url: URL, destination: URL, chunkSize: Int = 16 * 1024 * 1024, maxConcurrency: Int = 4) {
        self.url = url
        self.destination = destination
        self.chunkSize = chunkSize
        self.maxConcurrency = maxConcurrency
    }
}

/// Chunked parallel HTTP download with bitmap resume (P3). Transport + files
/// live here; all arithmetic is `ChunkedPlan`/`DownloadBitmap` in Kit. The
/// work directory is `<destination>.dld/` holding `bitmap.bin` + `<i>.part`
/// files; on completion the parts merge into the destination and the dir is
/// removed. Partial state survives cancellation and restarts.
@MainActor
@Observable
public final class DownloadRunner {
    public private(set) var state: DownloadState = .idle
    private var workDir: URL?
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    public func start(spec: DownloadSpec) async {
        state = .downloading(fraction: 0)
        let dir = spec.destination.deletingLastPathComponent()
            .appendingPathComponent(spec.destination.lastPathComponent + ".dld")
        workDir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let total = try await Self.totalBytes(for: spec.url, session: session)
            guard total > 0 else {
                throw NSError(domain: "DownloadRunner", code: 3, userInfo: [NSLocalizedDescriptionKey: "zero-length file"])
            }
            let plan = ChunkedPlan(chunkSize: spec.chunkSize)
            let chunkCount = plan.chunkCount(forTotalBytes: total)

            var bitmap = Self.loadBitmap(dir: dir, chunkCount: chunkCount)
            // Self-healing: a set chunk whose part file is absent or short
            // resets the whole bitmap (v1 simplification; the file is the truth).
            for i in 0..<chunkCount where bitmap.isSet(i) {
                if Self.partSize(dir: dir, index: i) != plan.range(forChunk: i, totalBytes: total).count {
                    bitmap = DownloadBitmap(chunkCount: chunkCount)
                    break
                }
            }

            let missing = plan.missingChunkIndices(bitmap: bitmap)
            var doneBytes = plan.completedBytes(bitmap: bitmap, totalBytes: total)
            try await withThrowingTaskGroup(of: Int.self) { group in
                var next = 0
                func addOne() {
                    guard next < missing.count else { return }
                    let i = missing[next]
                    next += 1
                    group.addTask { [session] in
                        let range = plan.range(forChunk: i, totalBytes: total)
                        try await Self.fetchChunk(range: range, chunk: i, spec: spec, session: session, dir: dir)
                        return i
                    }
                }
                for _ in 0..<spec.maxConcurrency { addOne() }
                for try await done in group {
                    bitmap.set(done)
                    Self.persist(bitmap, dir: dir)
                    doneBytes += Int64(plan.range(forChunk: done, totalBytes: total).count)
                    state = .downloading(fraction: Double(doneBytes) / Double(total))
                    addOne()
                }
            }

            try Self.merge(plan: plan, total: total, bitmap: bitmap, spec: spec, dir: dir)
            try? FileManager.default.removeItem(at: dir)
            state = .done(spec.destination)
        } catch is CancellationError {
            state = .idle  // partial state remains on disk; resumable
        } catch {
            state = .failed("download failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private (nonisolated static so concurrent chunk fetches are not
    // serialized on the MainActor)

    private nonisolated static func totalBytes(for url: URL, session: URLSession) async throws -> Int64 {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: head)
        if let http = response as? HTTPURLResponse,
           let len = http.value(forHTTPHeaderField: "Content-Length"),
           let n = Int64(len) {
            return n
        }
        // Fallback: 1-byte Range probe, read Content-Range "bytes 0-0/total".
        var probe = URLRequest(url: url)
        probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, presp) = try await session.data(for: probe)
        if let http = presp as? HTTPURLResponse,
           let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let slash = cr.lastIndex(of: "/") {
            return Int64(cr[cr.index(after: slash)...]) ?? 0
        }
        throw NSError(domain: "DownloadRunner", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "cannot determine file size"])
    }

    private nonisolated static func fetchChunk(range: Range<Int64>, chunk: Int, spec: DownloadSpec, session: URLSession, dir: URL) async throws {
        var request = URLRequest(url: spec.url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (http.statusCode == 200 || http.statusCode == 206),
              data.count == range.count else {
            throw NSError(domain: "DownloadRunner", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "chunk \(chunk): bad response"])
        }
        try data.write(to: dir.appendingPathComponent("\(chunk).part"), options: .atomic)
    }

    private nonisolated static func loadBitmap(dir: URL, chunkCount: Int) -> DownloadBitmap {
        let url = dir.appendingPathComponent("bitmap.bin")
        if let data = try? Data(contentsOf: url),
           let bm = try? DownloadBitmap.deserialize(data, chunkCount: chunkCount) {
            return bm
        }
        return DownloadBitmap(chunkCount: chunkCount)
    }

    private nonisolated static func persist(_ bitmap: DownloadBitmap, dir: URL) {
        try? bitmap.serialize().write(to: dir.appendingPathComponent("bitmap.bin"), options: .atomic)
    }

    private nonisolated static func partSize(dir: URL, index: Int) -> Int64 {
        let path = dir.appendingPathComponent("\(index).part").path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    private nonisolated static func merge(plan: ChunkedPlan, total: Int64, bitmap: DownloadBitmap, spec: DownloadSpec, dir: URL) throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: spec.destination.path + ".tmp")
        fm.createFile(atPath: tmp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmp)
        defer { try? handle.close() }
        for i in 0..<bitmap.chunkCount where bitmap.isSet(i) {
            let part = dir.appendingPathComponent("\(i).part")
            try handle.write(contentsOf: Data(contentsOf: part))
        }
        try fm.moveItem(at: tmp, to: spec.destination)
    }
}
