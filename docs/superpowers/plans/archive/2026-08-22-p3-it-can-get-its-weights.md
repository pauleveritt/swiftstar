# P3 — It Can Get Its Weights: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A chunked parallel HTTP downloader with bitmap resume across restarts (in `SwiftStarKit` plan/bitmap math + `SwiftStar` transport), plus a feasibility gate that refuses an infeasible engine launch with a computed, actionable message.

**Architecture:** Pure logic in `SwiftStarKit`: `Feasibility.check`, `DownloadBitmap`, `ChunkedPlan`, and a boot-line memory parser. The app (`SwiftStar`) owns URLSession transport, file layout, and the Settings download UI. Integration tier uses a committed minimal HTTP Range server (compiled by the harness) against which full download, resume, and failure paths are verified byte-for-byte.

**Tech Stack:** Swift 6.3, SwiftPM, swift-testing, URLSession, Darwin host statistics. Sphinx docs unchanged.

**Spec:** `docs/superpowers/specs/2026-08-22-p3-it-can-get-its-weights-design.md`

## Global Constraints

- Fast tier (`just test`): no model, no network, no subprocess (tripwire-scanned).
- Integration tier (`just integration`): real processes + local HTTP server; env-gated.
- Binding rules: every new test shown to fail first; refusal tests have sibling success tests; no source-text assertions.
- Kit is pure: no SwiftUI/IOKit/Process/network. All URLSession/file work is in `SwiftStar` or the integration tier.
- Facts cross with citations: HF URL pattern from `download_model.sh`; memory fields from P1 fixtures/P2 smoke.

---

### Task 1: Feasibility (Kit)

**Files:**
- Create: `Sources/SwiftStarKit/Feasibility.swift`, `Tests/SwiftStarKitTests/FeasibilityTests.swift`
- Test: `Tests/SwiftStarKitTests/FeasibilityTests.swift`

**Interfaces:**
- Produces: `FeasibilityReason` (struct: `message`, `deficitBytes`, `availableBytes`, `plannedBytes` — all `Int64`), `FeasibilityVerdict` (`.feasible` / `.infeasible(FeasibilityReason)`), `Feasibility.check(plannedBytes:availableBytes:modelName:) -> FeasibilityVerdict`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct FeasibilityTests {
    @Test func knownGoodFits() {
        let verdict = Feasibility.check(
            plannedBytes: 49_943_965_040,   // 46.51 GiB — the P1 config's plan
            availableBytes: 100 * 1024 * 1024 * 1024,
            modelName: "laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf"
        )
        #expect(verdict == .feasible)
    }

    @Test func knownBrokenRefuses() {
        let verdict = Feasibility.check(
            plannedBytes: 49_943_965_040,
            availableBytes: 24 * 1024 * 1024 * 1024,
            modelName: "laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf"
        )
        guard case .infeasible(let reason) = verdict else {
            Issue.record("expected infeasible"); return
        }
        #expect(reason.deficitBytes > 0)
        // The message must carry the numbers and an actionable lever.
        #expect(reason.message.contains("46.5"))
        #expect(reason.message.contains("24.0"))
        #expect(reason.message.contains("close"))
        #expect(reason.message.contains("smaller"))
    }

    @Test func modelLargerThanTotalRAMAlwaysRefused() {
        // No prior run needed: planned >= total is refused outright.
        let verdict = Feasibility.check(
            plannedBytes: 200 * 1024 * 1024 * 1024,
            availableBytes: 128 * 1024 * 1024 * 1024,
            modelName: "big"
        )
        #expect(if case .infeasible = verdict, true)
    }

    @Test func exactFitIsFeasible() {
        let verdict = Feasibility.check(
            plannedBytes: 1_000_000_000,
            availableBytes: 1_000_000_000,
            modelName: "exact"
        )
        #expect(verdict == .feasible)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test` — build error (`Feasibility` not found).

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct FeasibilityReason: Equatable, Sendable {
    public let message: String
    public let deficitBytes: Int64
    public let availableBytes: Int64
    public let plannedBytes: Int64
}

public enum FeasibilityVerdict: Equatable, Sendable {
    case feasible
    case infeasible(FeasibilityReason)
}

/// Arithmetic on the engine's own startup memory plan. Never a percentage
/// heuristic: the engine's planned_bytes is the number that matters, and the
/// message is computed from it.
public enum Feasibility {
    public static func check(
        plannedBytes: Int64,
        availableBytes: Int64,
        modelName: String
    ) -> FeasibilityVerdict {
        guard plannedBytes > availableBytes else { return .feasible }
        let deficit = plannedBytes - availableBytes
        let message = """
        "\(modelName)" needs \(gib(plannedBytes)) GiB of RAM but only \
        \(gib(availableBytes)) GiB is available (short \(gib(deficit)) GiB). \
        Close memory-heavy apps, or pick a smaller quant and check again.
        """
        return .infeasible(FeasibilityReason(
            message: message,
            deficitBytes: deficit,
            availableBytes: availableBytes,
            plannedBytes: plannedBytes
        ))
    }

    private static func gib(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }
}
```

- [ ] **Step 4: Run to verify pass** — `just test` green.

- [ ] **Step 5: Shown-fail — temporarily flip `>` to `>=` (exact fit refuses); `exactFitIsFeasible` fails; restore; green.**

- [ ] **Step 6: Commit** — `git add Sources/SwiftStarKit/Feasibility.swift Tests/SwiftStarKitTests/FeasibilityTests.swift && git commit -m "P3: feasibility gate (Kit)"`

---

### Task 2: DownloadBitmap + ChunkedPlan (Kit)

**Files:**
- Create: `Sources/SwiftStarKit/ChunkedDownload.swift`, `Tests/SwiftStarKitTests/ChunkedDownloadTests.swift`
- Test: `Tests/SwiftStarKitTests/ChunkedDownloadTests.swift`

**Interfaces:**
- Produces: `DownloadBitmapError` (`.widthMismatch`), `DownloadBitmap` (`init(chunkCount:)`, `set(_:)`, `isSet(_:)`, `completedCount`, `isEmpty`, `serialize() -> Data`, `deserialize(_:chunkCount:) throws`), `ChunkedPlan` (`init(chunkSize: Int = 16_777_216)`, `chunkCount(forTotalBytes:) -> Int`, `range(forChunk:totalBytes:) -> Range<Int64>`, `completedBytes(bitmap:totalBytes:) -> Int64`, `missingChunkIndices(bitmap:) -> [Int]`, `isComplete(bitmap:) -> Bool`).

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run to verify failure** — build error.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum DownloadBitmapError: Error, Equatable, Sendable {
    case widthMismatch(expectedWords: Int, actualWords: Int)
}

/// Fixed-width bitset over download chunks. The last word's high bits are
/// unused and never counted.
public struct DownloadBitmap: Equatable, Sendable {
    public private(set) var words: [UInt64]
    public let chunkCount: Int

    private var wordCount: Int { (chunkCount + 63) / 64 }

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
        var count = 0
        for (w, word) in words.enumerated() {
            let usable = (w == words.count - 1) ? (chunkCount % 64 == 0 ? 64 : chunkCount % 64) : 64
            count += word.nonzeroBitCount  // high unused bits are zero, so they don't count
            _ = usable
        }
        return count
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
```

- [ ] **Step 4: Run to verify pass** — green. (The `completedCount` `_ = usable` line: the high unused bits of the last word are zero by construction — `set` never touches them — so `nonzeroBitCount` already excludes them; simplify to a plain reduce and delete the `usable` stub.)

- [ ] **Step 5: Shown-fail — break `missingChunkIndices` to return only even indices; `planProgressAndMissing` fails; restore; green.**

- [ ] **Step 6: Commit** — `git commit -m "P3: download bitmap + chunk plan (Kit)"`

---

### Task 3: Boot-line memory parser + launch refusal (Kit + app)

**Files:**
- Create: `Sources/SwiftStarKit/BootLineParser.swift`, `Tests/SwiftStarKitTests/BootLineParserTests.swift`
- Modify: `Sources/SwiftStarKit/Supervisor.swift` (add `.infeasible(String)` to `EngineFailure`), `Sources/SwiftStar/EngineController.swift` (feasibility gate + plan persistence)
- Test: `Tests/SwiftStarKitTests/BootLineParserTests.swift`

**Interfaces:**
- Consumes: `Feasibility` (Task 1).
- Produces: `BootLineParser.plannedBytes(from: String) -> Int64?` (parses `… = 46.51 GiB planned` from the engine boot line), `EngineFailure.infeasible(String)`, and the app's launch-refusal behavior.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SwiftStarKit

struct BootLineParserTests {
    @Test func parsesPlannedGib() {
        let line = "ds4: memory: KV 1.57 GiB (raw 1.57 + compressed 0.00) + buffers 0.00 GiB + resident model 44.94 GiB = 46.51 GiB planned"
        let bytes = BootLineParser.plannedBytes(from: line)
        #expect(bytes != nil)
        // 46.51 GiB → integer bytes (rounded); within a GiB of the fixture's planned_bytes.
        let expected = Int64(49_943_965_040)
        #expect(abs((bytes! - expected)) < 1_073_741_824)
    }

    @Test func nonMemoryLineReturnsNil() {
        #expect(BootLineParser.plannedBytes(from: "ds4: Metal device Apple M5 Max") == nil)
        #expect(BootLineParser.plannedBytes(from: "") == nil)
    }

    @Test func missingPlannedWordReturnsNil() {
        #expect(BootLineParser.plannedBytes(from: "ds4: memory: KV 1.57 GiB") == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum BootLineParser {
    /// Extracts the engine's startup memory plan (bytes) from the boot line
    /// "… = 46.51 GiB planned" (the `ds4: memory:` stderr line, P1/P2 verified).
    public static func plannedBytes(from line: String) -> Int64? {
        let parts = line.split(separator: " ")
        guard let i = parts.firstIndex(of: "="), i + 2 < parts.count,
              parts[i + 2] == "planned" else { return nil }
        let value = Double(parts[i + 1].trimmingCharacters(in: .whitespaces))
        guard let value else { return nil }
        return Int64(value * 1_073_741_824)
    }
}
```

`Supervisor.swift` — add the case to `EngineFailure`:

```swift
public enum EngineFailure: Equatable, Sendable {
    case engineMissing(URL)
    case portInUse(Int)
    case instanceLocked
    case exited(code: Int32, stderrTail: String)
    case timeout
    case infeasible(String)   // P3: refused before spawn
}
```

- [ ] **Step 4: Run to verify pass.**

- [ ] **Step 5: App gate.** In `EngineController.startEngine`, before the idempotency check, apply the gate:

```swift
// Feasibility: refuse before spawning with a computed, actionable message.
let available = MemorySnapshot.availableBytes()
let planned = EngineController.lastKnownPlannedBytes ?? Int64(0)
if planned > 0 {
    let verdict = Feasibility.check(
        plannedBytes: planned,
        availableBytes: available,
        modelName: settings.modelPath.lastPathComponent
    )
    if case .infeasible(let reason) = verdict {
        state = .failed(.infeasible(reason.message))
        log("feasibility refusal: \(reason.message)")
        return
    }
}
```

Add to `EngineController`: `nonisolated static func availableBytes() -> Int64` using Darwin `host_statistics64` (HOST_VM_INFO: `free_count + inactive_count` bytes), and `static var lastKnownPlannedBytes: Int64?` backed by `UserDefaults.standard` (`lastKnownPlannedBytes`), written from `consumeStderr` when `BootLineParser.plannedBytes(from: line)` succeeds. `ChatView.failureDescription` gains `.infeasible(let message): return message`.

- [ ] **Step 6: Run both tiers** — `just test` green; `just integration` green (no download tests yet).

- [ ] **Step 7: Shown-fail for the gate (fast tier)** — a `BootLineParserTests` break on the `= ` splitting; restore.

- [ ] **Step 8: Commit** — `git commit -m "P3: launch refusal on feasibility (Kit + app)"`

---

### Task 4: The Range-file HTTP server (integration fixture)

**Files:**
- Create: `Tests/SwiftStarIntegrationTests/RangeFileServer.swift` (a standalone executable main, committed), and a `compileFile` helper in `FakeServerHarness.swift`.

**Interfaces:**
- Produces: an executable that takes `--port N --file PATH --log PATH`, serves `GET /` with HTTP byte ranges (`Range: bytes=a-b` → `206` with the slice; no range → `200` full), and appends one line per served range (`a-b`) to the log file.

- [ ] **Step 1: Write the server**

```swift
import Foundation
import Darwin

// Minimal HTTP Range server for P3 integration tests. Committed (test infra,
// not an engine fake). Serves one file; logs every served range.
let args = CommandLine.arguments
guard let pi = args.firstIndex(of: "--port"), args.count > pi + 1, let port = Int(args[pi + 1]),
      let fi = args.firstIndex(of: "--file"), args.count > fi + 1,
      let li = args.firstIndex(of: "--log"), args.count > li + 1 else {
    FileHandle.standardError.write(Data("usage: RangeFileServer --port N --file F --log L\n".utf8))
    exit(2)
}
let fileURL = URL(fileURLWithPath: args[fi + 1])
let logURL = URL(fileURLWithPath: args[li + 1])
let data = try! Data(contentsOf: fileURL)

func logRange(_ r: ClosedRange<Int>) {
    try? "\(r.lowerBound)-\(r.upperBound)\n".data(using: .utf8)?.write(to: logURL, options: .atomic)
}

let sock = socket(AF_INET, SOCK_STREAM, 0)
var opt: Int32 = 1
setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
var addr = sockaddr_in()
addr.sin_family = sa_family_t(AF_INET)
addr.sin_port = in_port_t(port).bigEndian
addr.sin_addr.s_addr = inet_addr("127.0.0.1")
_ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
_ = listen(sock, 8)
FileHandle.standardError.write(Data("range-file-server: listening on http://127.0.0.1:\(port)\n".utf8))

while true {
    let c = Darwin.accept(sock, nil, nil)
    guard c >= 0 else { continue }
    var request = Data()
    var byte: UInt8 = 0
    var headerDone = false
    var readBuffer = [UInt8](repeating: 0, count: 4096)
    while !headerDone {
        let n = Darwin.read(c, &readBuffer, readBuffer.count)
        if n <= 0 { break }
        request.append(contentsOf: readBuffer[0..<n])
        if let r = request.range(of: Data("\r\n\r\n".utf8)) {
            request.removeSubrange(r.upperBound..<request.endIndex)
            headerDone = true
        }
    }
    let text = String(decoding: request, as: UTF8.self)
    let lines = text.split(separator: "\r\n").map(String.init)
    let rangeHeader = lines.first { $0.lowercased().hasPrefix("range:") }
    var body: Data
    var status = "200 OK"
    if let range = rangeHeader, let dash = range.firstIndex(of: "-") {
        let fromStr = range[range.index(range.startIndex, offsetBy: 6)..<dash].trimmingCharacters(in: .whitespaces)
        let toStr = String(range[range.index(after: dash)...]).trimmingCharacters(in: .whitespaces)
        let from = Int(fromStr) ?? 0
        let to = Int(toStr) ?? (data.count - 1)
        let clampedTo = min(to, data.count - 1)
        body = data.subdata(in: from...clampedTo)
        status = "206 Partial Content"
        logRange(from...clampedTo)
    } else {
        body = data
        logRange(0...(data.count - 1))
    }
    let head = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\n\r\n"
    var out = Data(head.utf8); out.append(body)
    _ = out.withUnsafeBytes { Darwin.write(c, $0.baseAddress!, $0.count) }
    Darwin.close(c)
}
```

Add `compileFile` to `FakeServerHarness` (compiles any committed Swift main file; the existing `compileFake` writes a generated source — extract a shared `compile(source:into:)` and add `compileFile(at:into:)` that reads the file then compiles).

- [ ] **Step 2: Manual compile check** — `swiftc Tests/SwiftStarIntegrationTests/RangeFileServer.swift -o /tmp/rfs && echo ok`.

- [ ] **Step 3: Commit** — `git commit -m "P3: range-file HTTP server for integration tests"`

---

### Task 5: DownloadRunner (app)

**Files:**
- Create: `Sources/SwiftStar/DownloadRunner.swift`
- Test: integration tier (Task 6); fast-tier math already in Kit (Task 2)

**Interfaces:**
- Consumes: `ChunkedPlan`, `DownloadBitmap` (Task 2), `DownloadSpec` (defined here).
- Produces: `DownloadSpec` (struct: `url: URL`, `destination: URL`, `chunkSize: Int = 16 MiB`, `maxConcurrency: Int = 4`), `DownloadRunner` (`@MainActor @Observable`: `state: DownloadState`; `start(spec:) async`; `cancel()`), `DownloadState` (`.idle`, `.downloading(Double)`, `.done(URL)`, `.failed(String)`).

- [ ] **Step 1: Implement the runner**

```swift
import Foundation
import Observation
import SwiftStarKit

enum DownloadState: Equatable {
    case idle
    case downloading(fraction: Double)
    case done(URL)
    case failed(String)
}

struct DownloadSpec: Equatable {
    var url: URL
    var destination: URL
    var chunkSize: Int = 16 * 1024 * 1024
    var maxConcurrency: Int = 4
}

@MainActor
@Observable
final class DownloadRunner {
    private(set) var state: DownloadState = .idle
    private var workDir: URL?
    private let session = URLSession(configuration: .ephemeral)

    func start(spec: DownloadSpec) async {
        state = .downloading(fraction: 0)
        let fm = FileManager.default
        // Work dir: <destination parent>/<filename>.dld
        let dir = spec.destination.deletingLastPathComponent()
            .appendingPathComponent(spec.destination.lastPathComponent + ".dld")
        workDir = dir
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            let total = try await totalBytes(for: spec)
            let plan = ChunkedPlan(chunkSize: spec.chunkSize)
            let chunkCount = plan.chunkCount(forTotalBytes: total)

            var bitmap = loadBitmap(dir: dir, chunkCount: chunkCount)
            // Self-healing: a set bit whose part file is missing/short is redone.
            for i in 0..<chunkCount where bitmap.isSet(i) {
                let part = partURL(dir: dir, index: i)
                let size = (try? fm.attributesOfItem(atPath: part.path)[.size] as? Int64) ?? 0
                if size != plan.range(forChunk: i, totalBytes: total).count { bitmap = DownloadBitmap(chunkCount: chunkCount) }
            }
            // (Simplification: on any mismatch, restart the bitmap — acceptable v1; a
            // per-chunk repair is a refinement.)

            let missing = plan.missingChunkIndices(bitmap: bitmap)
            try await downloadMissing(missing, plan: plan, spec: spec, total: total, bitmap: &bitmap, dir: dir)
            try merge(plan: plan, spec: spec, total: total, bitmap: bitmap, dir: dir)
            cleanup(dir: dir)
            state = .done(spec.destination)
        } catch is CancellationError {
            // Partial state remains on disk; resume later.
            state = .idle
        } catch {
            state = .failed("download failed: \(error.localizedDescription)")
        }
    }

    func cancel() {
        // The runner's Task is the caller's; we only record intent and let the
        // in-flight URLSession calls finish or fail. state is set by start()'s
        // CancellationError path when the caller cancels the enclosing Task.
    }
    // (private helpers: totalBytes via HEAD with Range-probe fallback,
    // loadBitmap, partURL, downloadMissing via a TaskGroup with per-chunk
    // Range requests writing part files and persisting the bitmap atomically,
    // merge by concatenating part files to destination.tmp then renaming.)
}
```

The private helpers (write them fully during implementation):

```swift
private func totalBytes(for spec: DownloadSpec) async throws -> Int64 {
    var request = URLRequest(url: spec.url)
    request.httpMethod = "HEAD"
    let (_, response) = try await session.data(for: request)
    if let http = response as? HTTPURLResponse,
       let len = http.value(forHTTPHeaderField: "Content-Length"), let n = Int64(len) {
        return n
    }
    // Fallback: probe a 1-byte range and read Content-Range "bytes a-b/total".
    var probe = URLRequest(url: spec.url)
    probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
    let (_, presp) = try await session.data(for: probe)
    if let http = presp as? HTTPURLResponse,
       let cr = http.value(forHTTPHeaderField: "Content-Range"),
       let slash = cr.lastIndex(of: "/") {
        return Int64(cr[cr.index(after: slash)...]) ?? 0
    }
    throw NSError(domain: "DownloadRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot determine file size"])
}

private func downloadMissing(_ indices: [Int], plan: ChunkedPlan, spec: DownloadSpec, total: Int64, bitmap: inout DownloadBitmap, dir: URL) async throws {
    let startTotal = bitmap.completedBytes(bitmap: bitmap, totalBytes: total)
    var done = startTotal
    let count = Int64(total)
    try await withThrowingTaskGroup(of: Void.self) { group in
        var next = 0
        func addOne() {
            guard next < indices.count else { return }
            let i = indices[next]; next += 1
            group.addTask {
                let range = plan.range(forChunk: i, totalBytes: total)
                try await self.fetchChunk(range, chunk: i, spec: spec, dir: dir)
            }
        }
        for _ in 0..<spec.maxConcurrency { addOne() }
        for try await _ in group {
            addOne()
        }
    }
}
// fetchChunk: Range request; write Data to part file; MainActor: set bit, persist bitmap, update state.
```

The state/progress updates, bitmap persistence (write `bitmap.bin` atomically), part file writing, and the merge step must all be implemented concretely in this task; keep them small and direct.

- [ ] **Step 2: Build** — `swift build` green.

- [ ] **Step 3: Commit** — `git commit -m "P3: DownloadRunner (chunked, parallel, bitmap-resumed)"`

---

### Task 6: Integration tests — download, resume, failure

**Files:**
- Create: `Tests/SwiftStarIntegrationTests/DownloadIntegrationTests.swift`

**Interfaces:**
- Consumes: `RangeFileServer` (Task 4), `DownloadRunner` + `DownloadSpec` (Task 5), `ChunkedPlan` (Task 2).

- [ ] **Step 1: Write the tests**

```swift
import Testing
import Foundation
@testable import SwiftStar

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct DownloadIntegrationTests {
    // A generated file, a range server, a spec.
    private func makeFileAndServer(bytes: Int, chunkSize: Int) throws -> (URL, URL, Int) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("source.bin")
        var data = Data()
        for i in 0..<bytes { data.append(UInt8(i % 251)) }
        try data.write(to: source)
        let port = try FakeServerHarness.freePort()
        let log = dir.appendingPathComponent("ranges.log")
        let binary = try FakeServerHarness.compileFile(at: dir.appendingPathComponent("rfs.swift"))
        let server = try FakeServerHarness.spawn(binary, arguments: ["--port", "\(port)", "--file", source.path, "--log", log.path], env: [:])
        // wait for listening line
        _ = server.stderr.fileHandleForReading.availableData
        return (source, log, port)
    }

    @Test func fullDownloadIsByteIdentical() async throws {
        let (source, log, port) = try makeFileAndServer(bytes: 1_000_000, chunkSize: 100_000)
        let dest = source.deletingLastPathComponent().appendingPathComponent("out.bin")
        let runner = DownloadRunner()
        await runner.start(spec: DownloadSpec(url: URL(string: "http://127.0.0.1:\(port)/")!, destination: dest, chunkSize: 100_000, maxConcurrency: 3))
        #expect(runner.state == .done(dest))
        #expect(try Data(contentsOf: dest) == try Data(contentsOf: source))
    }

    @Test func resumeDownloadsOnlyMissingChunks() async throws {
        let (source, log, port) = try makeFileAndServer(bytes: 1_000_000, chunkSize: 100_000)
        let dest = source.deletingLastPathComponent().appendingPathComponent("out2.bin")
        // Seed the first two chunks + bitmap, as if a prior run died.
        let dir = dest.deletingLastPathComponent().appendingPathComponent("out2.bin.dld")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plan = ChunkedPlan(chunkSize: 100_000)
        let total = Int64(1_000_000)
        let full = try Data(contentsOf: source)
        for i in 0..<2 {
            let r = plan.range(forChunk: i, totalBytes: total)
            try full.subdata(in: r).write(to: dir.appendingPathComponent("\(i).part"))
        }
        var bm = DownloadBitmap(chunkCount: plan.chunkCount(forTotalBytes: total))
        bm.set(0); bm.set(1)
        try bm.serialize().write(to: dir.appendingPathComponent("bitmap.bin"))
        // Fresh runner (a "restart").
        let runner = DownloadRunner()
        await runner.start(spec: DownloadSpec(url: URL(string: "http://127.0.0.1:\(port)/")!, destination: dest, chunkSize: 100_000, maxConcurrency: 3))
        #expect(runner.state == .done(dest))
        #expect(try Data(contentsOf: dest) == full)
        let ranges = try String(contentsOf: log, encoding: .utf8)
        #expect(!ranges.contains("0-99999"), "chunk 0 must not be re-downloaded")
        #expect(!ranges.contains("100000-199999"), "chunk 1 must not be re-downloaded")
        #expect(ranges.contains("200000-"), "chunk 2 must be downloaded")
    }

    @Test func serverErrorFailsCleanly() async throws {
        let (_, _, port) = try makeFileAndServer(bytes: 100_000, chunkSize: 100_000)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("p3-fail-\(UUID().uuidString)").appendingPathComponent("out.bin")
        let runner = DownloadRunner()
        await runner.start(spec: DownloadSpec(url: URL(string: "http://127.0.0.1:\(port - 1)/")!, destination: dest))  // wrong port → connect failure
        if case .failed(let message) = runner.state {
            #expect(!message.isEmpty)
        } else {
            Issue.record("expected .failed, got \(runner.state)")
        }
    }
}
```

- [ ] **Step 2: Iterate** — `just integration` until green (the runner's `@testable import SwiftStar` needs the app target's testability; add `@testable` support by building tests with `-enable-testing` — SwiftPM does this automatically for debug builds of all targets).

- [ ] **Step 3: Shown-fail for resume** — break the self-healing size check (always trust the bit); `resumeDownloadsOnlyMissingChunks` fails (the seeded part files get skipped incorrectly or a partial chunk poisons the merge); restore; green.

- [ ] **Step 4: Commit** — `git commit -m "P3: integration tests — download, resume, failure"`

---

### Task 7: Settings download UI + smoke

**Files:**
- Modify: `Sources/SwiftStar/SettingsView.swift` (Download section), `Sources/SwiftStar/SettingsView.swift` (model picker)

**Interfaces:**
- Consumes: `DownloadRunner`/`DownloadSpec` (Task 5), the HF URL fact (spec).

- [ ] **Step 1: Implement the section**

A "Download model" section in the Engine pane: a `Picker` over the known targets (`[("Laguna S 2.1 Q2/Q3 (48 GB)", "antirez/Laguna-S-2.1-GGUF", "706fa69799926b6afde1af9e24ca2a4923f110a1", "laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf")]` — one entry, the P1 model; more targets later), a **Download** button, `ProgressView` + percent when downloading, **Cancel**, and status text. The destination is `~/Library/Application Support/SwiftStar/Downloads/<file>` (override via `SWIFTSTAR_DOWNLOAD_DIR`). `@State private var runner = DownloadRunner()` and a `Task` handle for cancel.

- [ ] **Step 2: Smoke** — set `SWIFTSTAR_DOWNLOAD_DIR` to a temp dir and run a download against a local RangeFileServer; verify the file lands byte-identical and the UI state reaches `.done` (log evidence via the runner's state printed to `SWIFTSTAR_LOG`-style app log if present, else the file existence + the Settings pane's own status).

- [ ] **Step 3: Commit** — `git commit -m "P3: Settings download section"`

---

### Task 8: ROADMAP close + verification record

**Files:**
- Modify: `ROADMAP.md` (P3 → complete; **feasibility** defined in the concept budget)
- Create: `docs/superpowers/research/2026-08-22-p3-verification-record.md`

- [ ] **Step 1: Verification record** — fast-tier counts, the shown-fail records, integration evidence (byte-identical download, resume-only-missing via the range log, clean failure), the launch-refusal smoke, and the drain/endpoint lessons from the session.

- [ ] **Step 2: ROADMAP** — P3 row → `complete (2026-08-22)`; Prior work entry; concept budget: **feasibility** defined ("the engine's startup memory plan vs. available RAM, computed, with an actionable refusal").

- [ ] **Step 3: Final gates** — `just test`, `just integration`, `just docs` all green; tree clean.

- [ ] **Step 4: Commit** — `git commit -m "P3: close — roadmap, concept budget, verification record"`

---

## Self-Review

**Spec coverage:** D1 feasibility (T1), D2 refusal policy (T3), D3 plan/bitmap + runner (T2/T5), D4 storage layout (T5/T6), D5 UI (T7), D6 scope (no tasks for out-of-scope work). Done-when 1–7 → T1, T3, T6, T2, T7, all, T8.

**Placeholder scan:** the DownloadRunner's private helpers are sketched but the task names them concretely and the integration tests exercise them; the merge/bitmap-persist steps are implemented in T5 with the tests in T6 as the gate. No TBDs.

**Type consistency:** `DownloadBitmap`/`ChunkedPlan` (T2) used by T5/T6; `DownloadSpec`/`DownloadState`/`DownloadRunner` (T5) used by T6/T7; `Feasibility`/`BootLineParser` (T1/T3) used by T3; `EngineFailure.infeasible` (T3) rendered by `ChatView.failureDescription` (T3).
