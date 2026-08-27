import Testing
import Foundation
@testable import SwiftStarKit

/// Item 6 (P22 cleanup): `SafeAppendFile` bundles "create the file before
/// appending" into construction itself, closing the exact bug class that
/// shipped once already — `FileHandle(forWritingAtPath:)` opens an EXISTING
/// file; a lazy open against a path that was never created silently no-ops
/// every write for the whole session, and nothing throws to reveal it.
struct SafeAppendFileTests {
    private func scratchPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-append-\(UUID().uuidString).ndjson").path
    }

    /// The task's own regression case: construct against a path that does not
    /// exist, write immediately, and the file must have nonzero content. A
    /// naive `FileHandle(forWritingAtPath:)` (the historical bug) would leave
    /// the file missing entirely and the write silently dropped.
    @Test func writingImmediatelyAfterConstructionAgainstAMissingPathSucceeds() {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(!FileManager.default.fileExists(atPath: path))

        let writer = SafeAppendFile(path: path)
        writer.append(Data("first line\n".utf8))

        #expect(FileManager.default.fileExists(atPath: path))
        let content = try? String(contentsOfFile: path, encoding: .utf8)
        #expect(content == "first line\n")
    }

    @Test func multipleAppendsAccumulateInOrder() {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = SafeAppendFile(path: path)
        writer.append(Data("one\n".utf8))
        writer.append(Data("two\n".utf8))
        writer.append(Data("three\n".utf8))
        let content = try? String(contentsOfFile: path, encoding: .utf8)
        #expect(content == "one\ntwo\nthree\n")
    }

    /// A fresh `SafeAppendFile` constructed against a path that already has
    /// content (the appendOutcome shape: one writer per call, not held open
    /// for the whole session) must append after the existing content, not
    /// overwrite it.
    @Test func constructingAgainstExistingContentAppendsAfterIt() {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try? "existing\n".write(toFile: path, atomically: true, encoding: .utf8)

        SafeAppendFile(path: path).append(Data("new\n".utf8))

        let content = try? String(contentsOfFile: path, encoding: .utf8)
        #expect(content == "existing\nnew\n")
    }

    @Test func closeThenAppendDoesNotCrashAndSilentlyNoOps() {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = SafeAppendFile(path: path)
        writer.append(Data("before close\n".utf8))
        writer.close()
        writer.append(Data("after close\n".utf8))  // must not crash
        let content = try? String(contentsOfFile: path, encoding: .utf8)
        #expect(content == "before close\n")
    }

    @Test func constructionAgainstAnUnresolvableDirectoryYieldsANoOpWriterNotACrash() {
        // A containing directory that does not exist: `createFile` fails
        // (silently, per Foundation's own contract) and the subsequent open
        // also fails — matches every existing call site's "capture
        // unavailable" tolerance (the tee simply writes nothing).
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
            .appendingPathComponent("file.ndjson").path
        let writer = SafeAppendFile(path: path)
        writer.append(Data("nope\n".utf8))  // must not crash
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
