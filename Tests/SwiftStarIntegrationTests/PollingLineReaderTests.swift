import Foundation
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct PollingLineReaderTests {

    @Test func retainsPartialAndMultipleLines() throws {
        let pipe = Pipe()
        let writer = Process()
        writer.executableURL = URL(fileURLWithPath: "/bin/sh")
        writer.arguments = ["-c", "printf 'first\\nsecond'; sleep 0.05; printf '\\nthird\\n'"]
        writer.standardOutput = pipe
        writer.standardError = FileHandle.standardError
        try writer.run()
        defer {
            if writer.isRunning { writer.terminate() }
            writer.waitUntilExit()
            try? pipe.fileHandleForReading.close()
        }
        let reader = PollingLineReader(fd: pipe.fileHandleForReading.fileDescriptor)

        #expect(try reader.nextLine(timeout: 1) == "first")
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
