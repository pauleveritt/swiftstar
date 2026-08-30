import Foundation
import Darwin
import SwiftStarKit

enum PollingLineReaderError: Error, Equatable {
    case endOfFile
    case timedOut
    case readFailed(Int32)
}

/// A deadline-aware, stateful reader for line-oriented pipe protocols.
///
/// The reader owns both the incremental byte framer and completed lines that
/// arrived in the same read. That matters when a caller stops at a predicate:
/// bytes already pulled from the pipe must remain available to the next call.
final class PollingLineReader {
    private let fd: Int32
    private var framing = LineBuffer()
    private var pending: [Data] = []

    init(fd: Int32) {
        self.fd = fd
    }

    func nextLine(timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while pending.isEmpty {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw PollingLineReaderError.timedOut }
            let milliseconds = max(1, Int(min(remaining * 1000, Double(Int32.max))))
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, Int32(milliseconds))
            if ready == 0 { throw PollingLineReaderError.timedOut }
            if ready < 0 {
                if errno == EINTR { continue }
                throw PollingLineReaderError.readFailed(errno)
            }
            guard (descriptor.revents & Int16(POLLIN | POLLHUP)) != 0 else { continue }

            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count == 0 { throw PollingLineReaderError.endOfFile }
            if count < 0 {
                if errno == EINTR { continue }
                throw PollingLineReaderError.readFailed(errno)
            }
            pending.append(contentsOf: framing.append(Data(chunk[0..<count])))
        }

        let line = pending.removeFirst()
        return String(decoding: line, as: UTF8.self)
    }
}
