import Foundation
import Testing

struct PollingLineReaderTests {

    @Test func retainsPartialAndMultipleLines() throws {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close() }
        let reader = PollingLineReader(fd: pipe.fileHandleForReading.fileDescriptor)

        pipe.fileHandleForWriting.write(Data("first\nsecond".utf8))
        #expect(try reader.nextLine(timeout: 1) == "first")

        DispatchQueue.global().async {
            pipe.fileHandleForWriting.write(Data("\nthird\n".utf8))
            try? pipe.fileHandleForWriting.close()
        }
        #expect(try reader.nextLine(timeout: 1) == "second")
        #expect(try reader.nextLine(timeout: 1) == "third")
    }

    @Test func timesOutWhenNoLineArrives() {
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
        }
        let reader = PollingLineReader(fd: pipe.fileHandleForReading.fileDescriptor)

        #expect(throws: PollingLineReaderError.timedOut) {
            try reader.nextLine(timeout: 0.02)
        }
    }

    @Test func reportsEOFAfterWriterCloses() {
        let pipe = Pipe()
        pipe.fileHandleForWriting.closeFile()
        defer { try? pipe.fileHandleForReading.close() }
        let reader = PollingLineReader(fd: pipe.fileHandleForReading.fileDescriptor)

        #expect(throws: PollingLineReaderError.endOfFile) {
            try reader.nextLine(timeout: 1)
        }
    }
}
