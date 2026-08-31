# P2 — It Launches and Answers: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A regular macOS SwiftUI app (`SwiftStarKit` + `SwiftStar`) that spawns `ds4-server`, streams one chat turn over SSE, with a fast test tier guarded by a tripwire and an integration tier that compiles and exercises a fake engine generated from P1's capture.

**Architecture:** Pure logic lives in `SwiftStarKit` (no SwiftUI/IOKit/Process/network) — SSE parser, server argv builder, supervisor state machine, chat transcript reducer, fake-engine source generator. The app (`SwiftStar`) is thin: `Process` spawning, pipes, `URLSession` streaming, SwiftUI scenes. Fast tier = `SwiftStarKitTests` (fixtures only, tripwire-scanned). Integration tier = `SwiftStarIntegrationTests` (real `Process` + compiled fake engine, gated behind `SWIFTSTAR_INTEGRATION=1`).

**Tech Stack:** Swift 6.3.3 (language mode 6), SwiftPM only, swift-testing, SwiftUI, macOS 26. Docs/Sphinx unchanged.

**Spec:** `docs/superpowers/specs/2026-08-22-p2-it-launches-and-answers-design.md`

## Global Constraints

- **Targets:** `SwiftStarKit` (pure), `SwiftStar` (app executable), `SwiftStarKitTests` (fast, tripwire-scanned), `SwiftStarIntegrationTests` (marked, env-gated).
- **Swift 6 language mode**, `platforms: [.macOS(.v26)]`, SwiftPM only — no Xcode project.
- **swift-testing** for all new tests (never XCTest).
- **Fast tier** (`just test` = `swift test`): no model, no network, no subprocess — enforced by the `FastTierGuard` build-tool plugin scanning `SwiftStarKitTests` sources for `Process(`, `URLSession`, `NWConnection`, `posix_spawn`, `Darwin.`, `socket(`.
- **Integration tier** (`just integration` = `SWIFTSTAR_INTEGRATION=1 swift test`): real processes and files, fake engine binaries generated from `fixtures/server/golden.sse`.
- **Binding rules (BRIEF.md):** every new test must be shown to fail first (break it, watch it fail, restore); no source-text assertions (a test that wants to grep source means the logic belongs in Kit); a refusal test has a sibling success test.
- **The wire has no handshake until P5** — the P2 parser must parse and must not refuse its absence; unknown fields fall back to `.ignored`, never refusal.
- **Fakes are generated from committed captures, never hand-authored**, and validate argv strictly.
- **Facts cross the clean-room line only with a citation** (fixture or provenance path) and a fresh test.
- Do not modify `external/ds4` in this phase. No submodule bump.

## Glossary (concept budget, spec done-when 7)

- **seam** — the spawned-child-plus-wire boundary between the app and the engine.
- **wire** — the byte stream on that seam (P2: SSE from `ds4-server`).
- **capture** — a byte-for-byte recording of a wire, stored with a timestamp sidecar.
- **fixture** — a committed capture used by tests.

---

### Task 1: Package scaffolding + `EngineSettings`/`ServerCommand`

**Files:**
- Create: `Package.swift`, `Sources/SwiftStarKit/ServerCommand.swift`, `Tests/SwiftStarKitTests/ServerCommandTests.swift`
- Modify: `Justfile` (test/integration recipes), `.gitignore` (already has `.build/`; verify)
- Test: `Tests/SwiftStarKitTests/ServerCommandTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `EngineSettings` (struct: `engineDir: URL`, `modelPath: URL`, `contextSize: Int = 32768`, `port: Int`, `host: String = "127.0.0.1"`), `ServerCommand.argv(settings:) -> [String]` — the argv contract the fake validates (Task 6) and the app spawns (Task 8).

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/ServerCommandTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct ServerCommandTests {
    @Test func buildsExactArgv() {
        let settings = EngineSettings(
            engineDir: URL(fileURLWithPath: "/tmp/engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 32768,
            port: 43210
        )
        let argv = ServerCommand.argv(settings: settings)
        #expect(argv == [
            "/tmp/engine/ds4-server",
            "-m", "/tmp/model.gguf",
            "-c", "32768",
            "--host", "127.0.0.1",
            "--port", "43210",
        ])
    }

    @Test func honorsOverrides() {
        let settings = EngineSettings(
            engineDir: URL(fileURLWithPath: "/a"),
            modelPath: URL(fileURLWithPath: "/b.bin"),
            contextSize: 16384,
            port: 9,
            host: "0.0.0.0"
        )
        #expect(ServerCommand.argv(settings: settings).contains("16384"))
        #expect(ServerCommand.argv(settings: settings).contains("0.0.0.0"))
        #expect(ServerCommand.argv(settings: settings).contains("9"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test` (or `swift test`)
Expected: build error — `no such module 'SwiftStarKit'` (package not yet created) / types not found. The tests fail.

- [ ] **Step 3: Create the package and implement**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftStar",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SwiftStarKit", targets: ["SwiftStarKit"]),
        .executable(name: "SwiftStar", targets: ["SwiftStar"]),
    ],
    targets: [
        .target(name: "SwiftStarKit"),
        .executableTarget(name: "SwiftStar", dependencies: ["SwiftStarKit"]),
        .testTarget(
            name: "SwiftStarKitTests",
            dependencies: ["SwiftStarKit"],
            plugins: ["FastTierGuard"]
        ),
        .testTarget(
            name: "SwiftStarIntegrationTests",
            dependencies: ["SwiftStarKit"]
        ),
    ]
)
```

`Sources/SwiftStarKit/ServerCommand.swift`:

```swift
import Foundation

/// The engine launch settings. Pure value type; defaults live in the app, not here.
public struct EngineSettings: Equatable, Sendable {
    public var engineDir: URL
    public var modelPath: URL
    public var contextSize: Int
    public var port: Int
    public var host: String

    public init(
        engineDir: URL,
        modelPath: URL,
        contextSize: Int = 32768,
        port: Int,
        host: String = "127.0.0.1"
    ) {
        self.engineDir = engineDir
        self.modelPath = modelPath
        self.contextSize = contextSize
        self.port = port
        self.host = host
    }
}

/// The one argv contract: what the app spawns and what the fake engine validates.
public enum ServerCommand {
    public static func argv(settings: EngineSettings) -> [String] {
        [
            settings.engineDir.appendingPathComponent("ds4-server").path,
            "-m", settings.modelPath.path,
            "-c", String(settings.contextSize),
            "--host", settings.host,
            "--port", String(settings.port),
        ]
    }
}
```

`Justfile` — replace the `test:` recipe and add `integration:`:

```justfile
# Fast tier: SwiftStarKit against fixtures. No model, no network, no subprocess
# (enforced by the FastTierGuard build-tool plugin on SwiftStarKitTests).
test:
    swift test

# Integration tier: real processes and files against fake engine binaries
# generated from committed captures. Same suite, marked tests enabled.
integration:
    SWIFTSTAR_INTEGRATION=1 swift test
```

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: build succeeds; `ServerCommandTests` 2 tests pass; `SwiftStar` executable target compiles (empty app target is fine at this point — give it a minimal `main.swift` so the product builds: create `Sources/SwiftStar/main.swift` containing `print("SwiftStar app arrives in Task 8")` — remove in Task 8).

- [ ] **Step 5: Commit**

```bash
git add Package.swift Justfile Sources/SwiftStarKit/ServerCommand.swift Sources/SwiftStar/main.swift Tests/SwiftStarKitTests/ServerCommandTests.swift
git commit -m "P2: package scaffold, EngineSettings/ServerCommand argv contract"
```

---

### Task 2: The fast-tier tripwire

**Files:**
- Create: `Sources/FastTierGuard/FastTierGuard.swift`, `Sources/FastTierGuardTool/main.swift`
- Modify: `Package.swift` (declare the plugin + tool targets, attach plugin to `SwiftStarKitTests`)
- Test: build-level demonstration (a temporary violating test)

**Interfaces:**
- Consumes: nothing (build-time).
- Produces: a build failure naming `file:line` when a `SwiftStarKitTests` source contains a forbidden symbol.

- [ ] **Step 1: Write the guard tool and plugin**

`Sources/FastTierGuardTool/main.swift`:

```swift
import Foundation

// Fast-tier tripwire tool. Scans one Swift source file for symbols that could
// spawn a process or open a socket; exits 1 (build failure) with file:line hits.
// It is a drift alarm, not a sandbox — see the P2 spec D3.

let forbidden: [String] = [
    "Process(", "URLSession", "NWConnection", "posix_spawn", "Darwin.", "socket("
]

let path = CommandLine.arguments[1]
guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { exit(0) }

var hits: [String] = []
for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
    for symbol in forbidden where line.contains(symbol) {
        hits.append("\(path):\(index + 1): \(symbol)")
    }
}
if !hits.isEmpty {
    let message = """
    FAST-TIER TRIPWIRE: a default-tier test may spawn a process or open a socket.
    \(hits.joined(separator: "\n"))
    If this is deliberate, the test belongs in SwiftStarIntegrationTests (env-gated).
    """
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
exit(0)
```

`Sources/FastTierGuard/FastTierGuard.swift`:

```swift
import PackagePlugin

@main
struct FastTierGuard: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let tool = try context.tool(named: "FastTierGuardTool")
        return try sourceTarget.sourceFiles(withSuffix: "swift").map { file in
            .buildCommand(
                displayName: "FastTierGuard: \(file.path.lastComponent)",
                executable: tool.path,
                arguments: [file.path.string]
            )
        }
    }
}
```

`Package.swift` — add after the `.testTarget` declarations (plugin targets):

```swift
        .executableTarget(name: "FastTierGuardTool"),
        .plugin(
            name: "FastTierGuard",
            capability: .buildTool(),
            dependencies: [.target(name: "FastTierGuardTool")]
        ),
```

- [ ] **Step 2: Demonstrate the tripwire fires**

Create `Tests/SwiftStarKitTests/TripwireProbeTests.swift`:

```swift
import Testing
@testable import SwiftStarKit

struct TripwireProbeTests {
    @Test func probeMustFailTheBuild() {
        let p = Process()
        #expect(p.processIdentifier >= 0)
    }
}
```

Run: `just test`
Expected: build FAILS with the tripwire message naming `TripwireProbeTests.swift:6: Process(`. (This is the shown-fail for the tripwire itself.)

- [ ] **Step 3: Remove the probe and verify green**

Delete `Tests/SwiftStarKitTests/TripwireProbeTests.swift`. Run `just test`.
Expected: green. (Record: "tripwire demonstrated 2026-08-22 — a fast test referencing `Process(` failed the build with the plugin message; removal restored green.")

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/FastTierGuard Sources/FastTierGuardTool
git commit -m "P2: fast-tier tripwire build plugin"
```

---

### Task 3: The SSE parser

**Files:**
- Create: `Sources/SwiftStarKit/SSEParser.swift`, `Tests/SwiftStarKitTests/SSEParserTests.swift`
- Test: `Tests/SwiftStarKitTests/SSEParserTests.swift` (fixture-driven)

**Interfaces:**
- Consumes: `fixtures/server/golden.sse`, `fixtures/server/golden.short.sse`.
- Produces: `SSEEvent` (enum: `.roleAssistant`, `.reasoning(String)`, `.content(String)`, `.finish(SSEFinishReason)`, `.done`, `.ignored(String)`), `SSEFinishReason` (`.stop`, `.other(String)`), `SSEParser.feed(_ line: String) -> SSEEvent?` (streaming, `mutating`).

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/SSEParserTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct SSEParserTests {
    // Repo root derived from this file's path: Tests/SwiftStarKitTests/SSEParserTests.swift
    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/server")
    }

    private func parseFixture(_ name: String) throws -> [SSEEvent] {
        let text = try String(contentsOf: fixturesRoot.appendingPathComponent(name), encoding: .utf8)
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let event = parser.feed(String(line)) { events.append(event) }
        }
        return events
    }

    @Test func firstChunkIsRoleAssistant() throws {
        let events = try parseFixture("golden.short.sse")
        #expect(events.first == .roleAssistant)
    }

    @Test func reasoningAndContentDeltasBothPresent() throws {
        let events = try parseFixture("golden.short.sse")
        #expect(events.contains { if case .reasoning = $0 { return true } else { return false } })
        #expect(events.contains { if case .content = $0 { return true } else { return false } })
    }

    @Test func endsWithDoneAfterFinish() throws {
        let events = try parseFixture("golden.short.sse")
        #expect(events.last == .done)
        #expect(events.dropLast().last == .finish(.stop))
    }

    @Test func unknownFieldIsIgnoredNotRefused() {
        var parser = SSEParser()
        let line = #"data: {"id":"x","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"future_field":"z"},"finish_reason":null}]}"#
        let event = parser.feed(line)
        #expect(event == .ignored( """{"id":"x","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"future_field":"z"},"finish_reason":null}]}""" ))
    }

    @Test func nonDataLinesAreSkipped() {
        var parser = SSEParser()
        #expect(parser.feed("") == nil)
        #expect(parser.feed(": a comment") == nil)
        #expect(parser.feed("event: message") == nil)
    }

    @Test func doneLineParses() {
        var parser = SSEParser()
        #expect(parser.feed("data: [DONE]") == .done)
    }

    @Test func malformedDataIsIgnoredNotRefused() {
        var parser = SSEParser()
        #expect(parser.feed("data: not json at all") == .ignored("not json at all"))
    }

    @Test func noHandshakeRequired() throws {
        // The P1 wire has no version handshake (binding rule 7, P5 adds one).
        // Parsing the fixture must not refuse: it must produce events, not throw.
        let events = try parseFixture("golden.sse")
        #expect(events.count > 10)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: build error — `no such module 'SwiftStarKit'` symbols `SSEEvent`/`SSEParser` not found (tests fail).

- [ ] **Step 3: Implement**

`Sources/SwiftStarKit/SSEParser.swift`:

```swift
import Foundation

/// Finish reasons observed on the wire. Forward-compatible: unknown reasons
/// are preserved under `.other`, never refused.
public enum SSEFinishReason: Equatable, Sendable {
    case stop
    case other(String)
}

/// One modelled event from the SSE wire. `.ignored` carries the raw payload
/// for any line the parser does not model — the wire can grow and this parser
/// will not refuse it.
public enum SSEEvent: Equatable, Sendable {
    case roleAssistant
    case reasoning(String)
    case content(String)
    case finish(SSEFinishReason)
    case done
    case ignored(String)
}

/// Streaming SSE consumer. Feed it one wire line at a time; it returns an
/// event or nil. No handshake is required or refused (binding rule 7: the
/// wire announces itself from P5, not before).
public struct SSEParser: Sendable {
    public init() {}

    public mutating func feed(_ line: String) -> SSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }  // blank/comment/event: lines
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard
            let data = payload.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let choice = choices.first
        else { return .ignored(payload) }
        if let reason = choice["finish_reason"] as? String, !reason.isEmpty {
            return .finish(reason == "stop" ? .stop : .other(reason))
        }
        guard let delta = choice["delta"] as? [String: Any] else { return .ignored(payload) }
        if let role = delta["role"] as? String, role == "assistant" { return .roleAssistant }
        if let reasoning = delta["reasoning_content"] as? String { return .reasoning(reasoning) }
        if let content = delta["content"] as? String { return .content(content) }
        return .ignored(payload)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: `SSEParserTests` all pass (fixture-driven; both fixtures parse; `.ignored` for unknown fields, not refusal; no handshake required).

- [ ] **Step 5: Show the parser refuses nothing it can ignore — break/recover**

Temporarily change `SSEParserTests.malformedDataIsIgnoredNotRefused` to expect `.ignored("")` (wrong). Run `just test` — must fail. Restore. Run `just test` — green. (Records binding rule 2 for the refusal behavior.)

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/SSEParser.swift Tests/SwiftStarKitTests/SSEParserTests.swift
git commit -m "P2: SSE parser, fixture-driven, forward-compatible"
```

---

### Task 4: The supervisor state machine

**Files:**
- Create: `Sources/SwiftStarKit/Supervisor.swift`, `Tests/SwiftStarKitTests/SupervisorTests.swift`
- Test: `Tests/SwiftStarKitTests/SupervisorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `SupervisorState` (`.stopped`, `.starting`, `.ready`, `.generating`, `.stopping`, `.failed(EngineFailure)`), `EngineFailure` (`.engineMissing(URL)`, `.portInUse(Int)`, `.instanceLocked`, `.exited(code: Int32, stderrTail: String)`, `.timeout`), `SupervisorEvent` (`.launchRequested`, `.engineMissing(URL)`, `.stdoutLine(String)`, `.stderrLine(String)`, `.generationStarted`, `.generationFinished`, `.exit(Int32)`, `.stopRequested`, `.timeoutFired`), `Supervisor.transition(from:event:port:stderrTail:) -> SupervisorState` (pure).

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/SupervisorTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct SupervisorTests {
    @Test func launchLeadsToReadyViaListening() {
        var s = Supervisor.transition(from: .stopped, event: .launchRequested)
        #expect(s == .starting)
        s = Supervisor.transition(from: s, event: .stderrLine("0822 00:00:00 ds4-server: listening on http://127.0.0.1:8000"))
        #expect(s == .ready)
    }

    @Test func generationRoundTrip() {
        var s = Supervisor.transition(from: .ready, event: .generationStarted)
        #expect(s == .generating)
        s = Supervisor.transition(from: s, event: .generationFinished)
        #expect(s == .ready)
    }

    @Test func instanceLockMapsToFailure() {
        let s = Supervisor.transition(from: .starting, event: .stderrLine("ds4: another ds4 process is already running (pid 32046); refusing to start"))
        #expect(s == .failed(.instanceLocked))
    }

    @Test func portInUseMapsToFailure() {
        let s = Supervisor.transition(from: .starting, event: .stderrLine("ds4-server: failed to listen on 127.0.0.1:8000: address already in use"), port: 8000)
        #expect(s == .failed(.portInUse(8000)))
    }

    @Test func childExitMapsToFailureWithTail() {
        let s = Supervisor.transition(
            from: .starting,
            event: .exit(1),
            stderrTail: ["ds4: cannot open model '/nope.gguf': No such file or directory"]
        )
        #expect(s == .failed(.exited(code: 1, stderrTail: "ds4: cannot open model '/nope.gguf': No such file or directory")))
    }

    @Test func timeoutMapsToFailure() {
        #expect(Supervisor.transition(from: .starting, event: .timeoutFired) == .failed(.timeout))
    }

    @Test func stopFromReadyGoesToStoppingThenStopped() {
        var s = Supervisor.transition(from: .ready, event: .stopRequested)
        #expect(s == .stopping)
        s = Supervisor.transition(from: s, event: .exit(0))
        #expect(s == .stopped)
    }

    @Test func failedCanRestart() {
        let s = Supervisor.transition(from: .failed(.timeout), event: .launchRequested)
        #expect(s == .starting)
    }

    @Test func illegalTransitionKeepsState() {
        // A ready event while stopped is a lie from the harness: keep the state.
        #expect(Supervisor.transition(from: .stopped, event: .generationFinished) == .stopped)
    }

    @Test func engineMissingMapsToFailure() {
        let url = URL(fileURLWithPath: "/nope/ds4-server")
        #expect(Supervisor.transition(from: .stopped, event: .engineMissing(url)) == .failed(.engineMissing(url)))
    }

    @Test func readySignalWhileGeneratingIsIgnored() {
        // A late "listening" line (already ready) must not reset state.
        let s = Supervisor.transition(from: .generating, event: .stderrLine("ds4-server: listening on http://127.0.0.1:8000"))
        #expect(s == .generating)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: build error — `SupervisorState` etc. not found.

- [ ] **Step 3: Implement**

`Sources/SwiftStarKit/Supervisor.swift`:

```swift
import Foundation

public enum EngineFailure: Equatable, Sendable {
    case engineMissing(URL)
    case portInUse(Int)
    case instanceLocked
    case exited(code: Int32, stderrTail: String)
    case timeout
}

public enum SupervisorState: Equatable, Sendable {
    case stopped
    case starting
    case ready
    case generating
    case stopping
    case failed(EngineFailure)
}

public enum SupervisorEvent: Equatable, Sendable {
    case launchRequested
    case engineMissing(URL)
    case stdoutLine(String)
    case stderrLine(String)
    case generationStarted
    case generationFinished
    case exit(Int32)
    case stopRequested
    case timeoutFired
}

/// Pure transition function: all supervisor policy lives here, tested in
/// milliseconds. The app holds the state and forwards events; it never makes
/// policy. `port` and `stderrTail` are inputs the harness knows but the
/// transition needs (port for `.portInUse`, tail for the failure message).
public enum Supervisor {
    public static func transition(
        from state: SupervisorState,
        event: SupervisorEvent,
        port: Int = 0,
        stderrTail: [String] = []
    ) -> SupervisorState {
        switch (state, event) {
        case (.stopped, .launchRequested), (.failed, .launchRequested):
            return .starting

        case (.stopped, .engineMissing(let url)):
            return .failed(.engineMissing(url))

        case (.starting, .stderrLine(let line)):
            if line.contains("another ds4 process is already running") {
                return .failed(.instanceLocked)
            }
            if line.lowercased().contains("address already in use")
                || line.lowercased().contains("failed to listen") {
                return .failed(.portInUse(port))
            }
            if line.contains("listening on http") {
                return .ready
            }
            return .starting

        case (.starting, .exit(let code)):
            return .failed(.exited(code: code, stderrTail: stderrTail.joined(separator: "\n")))
        case (.starting, .timeoutFired):
            return .failed(.timeout)

        case (.ready, .generationStarted):
            return .generating
        case (.generating, .generationFinished):
            return .ready

        case (.ready, .exit(let code)), (.generating, .exit(let code)):
            return .failed(.exited(code: code, stderrTail: stderrTail.joined(separator: "\n")))

        case (.stopping, .exit):
            return .stopped
        case (.stopping, .timeoutFired):
            return .failed(.timeout)

        case (_, .stopRequested):
            return .stopping

        default:
            return state
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: all `SupervisorTests` pass, including `readySignalWhileGeneratingIsIgnored` (the `(.generating, .stderrLine)` case hits the `default` → state kept).

- [ ] **Step 5: Show a transition is wrong when broken — break/recover**

Temporarily reorder `(.ready, .exit)` handling so a ready child exit keeps `.ready` (delete the case). Run `just test` — `childExitMapsToFailureWithTail` and the stop test fail. Restore. Green.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/Supervisor.swift Tests/SwiftStarKitTests/SupervisorTests.swift
git commit -m "P2: supervisor state machine as a pure transition function"
```

---

### Task 5: The chat transcript reducer

**Files:**
- Create: `Sources/SwiftStarKit/ChatTranscript.swift`, `Tests/SwiftStarKitTests/ChatTranscriptTests.swift`
- Test: `Tests/SwiftStarKitTests/ChatTranscriptTests.swift`

**Interfaces:**
- Consumes: `SSEEvent` (Task 3).
- Produces: `TranscriptRow` (`.reasoning(String)`, `.content(String)`, `.finished`, `.system(String)`), `ChatTranscript` (mutable: `rows`, `apply(_ event: SSEEvent)`, `appendSystem(_ message: String)`).

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/ChatTranscriptTests.swift`:

```swift
import Testing
@testable import SwiftStarKit

struct ChatTranscriptTests {
    @Test func mapsEventsToRows() {
        var transcript = ChatTranscript()
        transcript.apply(.roleAssistant)
        transcript.apply(.reasoning("think"))
        transcript.apply(.content("Hello"))
        transcript.apply(.content(" world"))
        transcript.apply(.finish(.stop))
        transcript.apply(.done)
        #expect(transcript.rows == [
            .reasoning("think"),
            .content("Hello"),
            .content(" world"),
            .finished,
        ])
    }

    @Test func ignoresUnmodeledEvents() {
        var transcript = ChatTranscript()
        transcript.apply(.ignored("{\"future\":true}"))
        #expect(transcript.rows.isEmpty)
    }

    @Test func systemMessagesAppend() {
        var transcript = ChatTranscript()
        transcript.appendSystem("engine ready")
        #expect(transcript.rows == [.system("engine ready")])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: build error — `TranscriptRow`/`ChatTranscript` not found.

- [ ] **Step 3: Implement**

`Sources/SwiftStarKit/ChatTranscript.swift`:

```swift
public enum TranscriptRow: Equatable, Sendable {
    case reasoning(String)
    case content(String)
    case finished
    case system(String)
}

/// Reduces wire events to display rows. Kept in Kit so the chat view is thin
/// and the mapping is tested in the fast tier.
public struct ChatTranscript: Equatable, Sendable {
    public private(set) var rows: [TranscriptRow] = []

    public init() {}

    public mutating func apply(_ event: SSEEvent) {
        switch event {
        case .roleAssistant, .ignored, .done:
            break
        case .reasoning(let text):
            rows.append(.reasoning(text))
        case .content(let text):
            rows.append(.content(text))
        case .finish:
            rows.append(.finished)
        }
    }

    public mutating func appendSystem(_ message: String) {
        rows.append(.system(message))
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/ChatTranscript.swift Tests/SwiftStarKitTests/ChatTranscriptTests.swift
git commit -m "P2: chat transcript reducer"
```

---

### Task 6: The fake engine source generator

**Files:**
- Create: `Sources/SwiftStarKit/FakeServerSource.swift`, `Tests/SwiftStarKitTests/FakeServerSourceTests.swift`
- Test: `Tests/SwiftStarKitTests/FakeServerSourceTests.swift` (fixture-driven determinism + refusal)

**Interfaces:**
- Consumes: `EngineSettings`/`ServerCommand` (Task 1) for argv; fixtures.
- Produces: `FakeServerError` (`.lineCountMismatch(capture:sidecar:)`, `.malformedCaptureLine(line:content:)`), `FakeServerSource.generate(capture:sidecar:engineArgv:) throws -> String` — a self-contained Swift executable source.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/FakeServerSourceTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct FakeServerSourceTests {
    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/server")
    }
    private func load(_ name: String) throws -> Data {
        try Data(contentsOf: fixturesRoot.appendingPathComponent(name))
    }

    @Test func generationIsDeterministic() throws {
        let capture = try load("golden.short.sse")
        let sidecar = try load("golden.short.sse.sidecar")
        let settings = EngineSettings(
            engineDir: URL(fileURLWithPath: "/tmp/e"),
            modelPath: URL(fileURLWithPath: "/tmp/m.gguf"), port: 12345
        )
        let a = try FakeServerSource.generate(capture: capture, sidecar: sidecar, engineArgv: ServerCommand.argv(settings: settings))
        let b = try FakeServerSource.generate(capture: capture, sidecar: sidecar, engineArgv: ServerCommand.argv(settings: settings))
        #expect(a == b)
    }

    @Test func generatedSourceEmbedsExpectedArgv() throws {
        let capture = try load("golden.short.sse")
        let sidecar = try load("golden.short.sse.sidecar")
        let settings = EngineSettings(
            engineDir: URL(fileURLWithPath: "/tmp/e"),
            modelPath: URL(fileURLWithPath: "/tmp/m.gguf"), port: 12345
        )
        let source = try FakeServerSource.generate(capture: capture, sidecar: sidecar, engineArgv: ServerCommand.argv(settings: settings))
        #expect(source.contains(#""-m""#))
        #expect(source.contains(#""/tmp/m.gguf""#))
        #expect(source.contains(#""--port""#))
    }

    @Test func generatedSourceEmbedsEveryCaptureLine() throws {
        let capture = try load("golden.short.sse")
        let sidecar = try load("golden.short.sse.sidecar")
        let source = try FakeServerSource.generate(
            capture: capture, sidecar: sidecar,
            engineArgv: ["/tmp/e/ds4-server", "-m", "/tmp/m.gguf", "-c", "32768", "--host", "127.0.0.1", "--port", "12345"]
        )
        let lines = String(decoding: capture, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for line in lines {
            #expect(source.contains(String(line)), "generated source must embed every capture line")
        }
    }

    @Test func refusesMalformedCapture() {
        let capture = Data("data: {\"a\":1}\nthis line is not sse\n".utf8)
        let sidecar = Data("1000\n2000\n".utf8)
        #expect(throws: FakeServerError.self) {
            _ = try FakeServerSource.generate(
                capture: capture, sidecar: sidecar,
                engineArgv: ["/tmp/e/ds4-server"]
            )
        }
    }

    @Test func refusesLineCountMismatch() {
        let capture = Data("data: {\"a\":1}\n".utf8)
        let sidecar = Data("1000\n2000\n".utf8)
        #expect(throws: FakeServerError.self) {
            _ = try FakeServerSource.generate(
                capture: capture, sidecar: sidecar,
                engineArgv: ["/tmp/e/ds4-server"]
            )
        }
    }

    @Test func refusalSiblingSucceeds() throws {
        // Sibling to refusesMalformedCapture: a clean capture generates.
        let capture = Data("data: {\"a\":1}\ndata: [DONE]\n".utf8)
        let sidecar = Data("1000\n3000\n".utf8)
        let source = try FakeServerSource.generate(
            capture: capture, sidecar: sidecar,
            engineArgv: ["/tmp/e/ds4-server"]
        )
        #expect(source.contains("data: {\"a\":1}"))
        #expect(source.contains("data: [DONE]"))
    }

    @Test func stringEscapingSurvivesQuotesAndNewlines() throws {
        // A capture containing a quote inside a JSON string must be escaped in
        // the generated literal (this is what keeps determinism byte-exact).
        let capture = Data("data: {\"s\":\"a \\\"quoted\\\" value\"}\ndata: [DONE]\n".utf8)
        let sidecar = Data("1000\n3000\n".utf8)
        let source = try FakeServerSource.generate(
            capture: capture, sidecar: sidecar,
            engineArgv: ["/tmp/e/ds4-server"]
        )
        #expect(source.contains("a \\\\\"quoted\\\\\" value") || source.contains("a \\\"quoted\\\" value"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: build error — `FakeServerSource`/`FakeServerError` not found.

- [ ] **Step 3: Implement**

`Sources/SwiftStarKit/FakeServerSource.swift`:

```swift
import Foundation

public enum FakeServerError: Error, Equatable, Sendable {
    case lineCountMismatch(capture: Int, sidecar: Int)
    case malformedCaptureLine(line: Int, content: String)
}

/// Generates the complete Swift source of a fake `ds4-server` from a committed
/// capture + sidecar. The fake validates its argv strictly, listens on `--port`,
/// prints the listening line to stderr (so the supervisor's ready detection works
/// against it), and replays the capture with sidecar-derived delays. `FAKE_SPEED`
/// env (0 = no delay) keeps integration tests fast; env is not argv, so argv
/// stays strict.
public enum FakeServerSource {

    public static func generate(capture: Data, sidecar: Data, engineArgv: [String]) throws -> String {
        let captureText = String(decoding: capture, as: UTF8.self)
        let sidecarText = String(decoding: sidecar, as: UTF8.self)

        var captureLines = captureText.split(separator: "\n", omittingEmptySubsequences: false)
        if captureLines.last == "" { captureLines.removeLast() }
        let stamps = sidecarText.split(separator: "\n", omittingEmptySubsequences: false).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        guard stamps.count == captureLines.count else {
            throw FakeServerError.lineCountMismatch(capture: captureLines.count, sidecar: stamps.count)
        }

        // Validate every non-blank line, and build the replay list with per-line
        // delays (µs) derived from consecutive sidecar timestamps.
        var replay: [(Int, String)] = []
        var lastStamp = stamps.first ?? 0
        for (index, line) in captureLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard trimmed.hasPrefix("data:") else {
                throw FakeServerError.malformedCaptureLine(line: index + 1, content: trimmed)
            }
            let delayMicros = max(0, (stamps[index] - lastStamp) / 1000)
            lastStamp = stamps[index]
            replay.append((delayMicros, String(line)))
        }

        let argvLiteral = engineArgv.map(swiftStringLiteral).joined(separator: ", ")
        let replayLiteral = replay
            .map { "    (\($0.0), \(swiftStringLiteral($0.1)))" }
            .joined(separator: ",\n")

        return """
        import Foundation
        import Darwin

        // GENERATED by SwiftStarKit.FakeServerSource — do not hand-edit.
        // Regenerate from the committed capture; a drift test pins this.

        let expectedArgv: [String] = [\(argvLiteral)]
        let replay: [(Int, String)] = [
        \(replayLiteral)
        ]

        func validateArgv() -> Bool {
            let actual = Array(CommandLine.arguments.dropFirst())
            return actual == expectedArgv
        }

        if !validateArgv() {
            FileHandle.standardError.write(Data("fake ds4-server: argv mismatch; expected \\(expectedArgv) got \\(Array(CommandLine.arguments.dropFirst()))\\n".utf8))
            exit(1)
        }

        guard let portIndex = CommandLine.arguments.firstIndex(of: "--port"),
              CommandLine.arguments.count > portIndex + 1,
              let port = Int(CommandLine.arguments[portIndex + 1]) else {
            FileHandle.standardError.write(Data("fake ds4-server: missing --port\\n".utf8))
            exit(2)
        }

        let speed = Double(ProcessInfo.processInfo.environment["FAKE_SPEED"] ?? "1.0") ?? 1.0

        final class ServerSocket {
            private let fd: Int32
            init(port: Int) throws {
                let s = socket(AF_INET, SOCK_STREAM, 0)
                guard s >= 0 else { throw NSError(domain: "fake", code: 1) }
                var opt: Int32 = 1
                setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = in_port_t(port).bigEndian
                addr.sin_addr.s_addr = inet_addr("127.0.0.1")
                let bindResult = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                guard bindResult == 0 else { close(s); throw NSError(domain: "fake", code: 2) }
                guard listen(s, 8) == 0 else { close(s); throw NSError(domain: "fake", code: 3) }
                self.fd = s
            }
            func accept() throws -> Client {
                let c = Darwin.accept(fd, nil, nil)
                guard c >= 0 else { throw NSError(domain: "fake", code: 4) }
                return Client(fd: c)
            }
        }

        final class Client {
            private let fd: Int32
            init(fd: Int32) { self.fd = fd }
            func write(_ s: String) throws {
                let bytes = Array(s.utf8)
                var offset = 0
                while offset < bytes.count {
                    let written = bytes.withUnsafeBytes { raw -> Int in
                        Darwin.write(fd, raw.baseAddress!.advanced(by: offset), bytes.count - offset)
                    }
                    if written <= 0 { throw NSError(domain: "fake", code: 5) }
                    offset += written
                }
            }
            func close() { Darwin.close(fd) }
        }

        do {
            let server = try ServerSocket(port: port)
            FileHandle.standardError.write(Data("fake ds4-server: listening on http://127.0.0.1:\\(port)\\n".utf8))
            while true {
                let client = try server.accept()
                for (delay, line) in replay {
                    if speed > 0 { usleep(useconds_t(Double(delay) / speed)) }
                    try client.write(line + "\\n")
                }
                try client.write("\\n")
                client.close()
            }
        } catch {
            FileHandle.standardError.write(Data("fake ds4-server: \\(error)\\n".utf8))
            exit(3)
        }
        """
    }

    /// Escapes a string for embedding as a Swift string literal in the
    /// generated source (backslash, quote, newline, carriage return, tab).
    static func swiftStringLiteral(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: all `FakeServerSourceTests` pass (determinism, embedding, refusal + sibling, escaping).

- [ ] **Step 5: Show refusal is real — break/recover**

Temporarily make the generator accept any non-`data:` line (delete the `guard trimmed.hasPrefix("data:")` throw). Run `just test` — `refusesMalformedCapture` fails. Restore. Green.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/FakeServerSource.swift Tests/SwiftStarKitTests/FakeServerSourceTests.swift
git commit -m "P2: fake engine source generator (capture-driven, argv-strict)"
```

---

### Task 7: Integration tier — compile, spawn, stream, assert

**Files:**
- Create: `Tests/SwiftStarIntegrationTests/FakeServerHarness.swift`, `Tests/SwiftStarIntegrationTests/FakeServerIntegrationTests.swift`
- Test: `Tests/SwiftStarIntegrationTests/FakeServerIntegrationTests.swift` (env-gated)

**Interfaces:**
- Consumes: `FakeServerSource` (Task 6), `ServerCommand` (Task 1), `SSEParser` (Task 3); fixtures.
- Produces: a demonstrated green `just integration` run; the fake engine compiled and exercised for real.

- [ ] **Step 1: Write the harness + failing tests**

`Tests/SwiftStarIntegrationTests/FakeServerHarness.swift`:

```swift
import Foundation
import SwiftStarKit

enum FakeServerHarness {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func fixture(_ name: String) throws -> URL {
        repoRoot.appendingPathComponent("fixtures/server").appendingPathComponent(name)
    }

    static func freePort() throws -> Int {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(s) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let r = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard r == 0 else { throw NSError(domain: "harness", code: 1) }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var got = sockaddr_in()
        let g = withUnsafeMutablePointer(to: &got) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(s, $0, &len)
            }
        }
        guard g == 0 else { throw NSError(domain: "harness", code: 2) }
        return Int(got.sin_port.bigEndian)
    }

    static func compileFake(source: String, into dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mainFile = dir.appendingPathComponent("main.swift")
        try source.write(to: mainFile, atomically: true, encoding: .utf8)
        let binary = dir.appendingPathComponent("fake-ds4-server")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        process.arguments = [mainFile.path, "-o", binary.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "compile", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: out])
        }
        return binary
    }

    static func spawn(_ binary: URL, arguments: [String], env: [String: String]) throws -> Process {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = env
        let out = Pipe(); let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        return process
    }

    /// Reads the SSE stream from the fake server until `data: [DONE]`, feeding
    /// the Kit parser, and returns the events.
    static func readEvents(port: Int, timeout: TimeInterval = 30) throws -> [SSEEvent] {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(s) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw NSError(domain: "connect", code: 3) }

        var parser = SSEParser()
        var events: [SSEEvent] = []
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        while Date() < deadline {
            var byte: UInt8 = 0
            let n = Darwin.read(s, &byte, 1)
            if n <= 0 { break }
            buffer.append(byte)
            if byte == 0x0A {
                let line = String(decoding: buffer, as: UTF8.self)
                buffer.removeAll(keepingCapacity: true)
                if let event = parser.feed(line) {
                    events.append(event)
                    if event == .done { return events }
                }
            }
        }
        throw NSError(domain: "timeout", code: 4, userInfo: [NSLocalizedDescriptionKey: "timed out waiting for [DONE]; got \(events.count) events"])
    }
}
```

`Tests/SwiftStarIntegrationTests/FakeServerIntegrationTests.swift`:

```swift
import Testing
import Foundation
import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct FakeServerIntegrationTests {

    private func makeSettings(port: Int) -> EngineSettings {
        EngineSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            port: port
        )
    }

    @Test func fakeReplaysCaptureEventsEquivalently() throws {
        let capture = try Data(contentsOf: FakeServerHarness.fixture("golden.sse"))
        let sidecar = try Data(contentsOf: FakeServerHarness.fixture("golden.sse.sidecar"))
        let port = try FakeServerHarness.freePort()
        let settings = makeSettings(port: port)

        let source = try FakeServerSource.generate(
            capture: capture, sidecar: sidecar,
            engineArgv: ServerCommand.argv(settings: settings)
        )
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("p2-fake-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeServerHarness.compileFake(source: source, into: work)

        let process = try FakeServerHarness.spawn(binary, arguments: ServerCommand.argv(settings: settings), env: ["FAKE_SPEED": "0"])

        // Expected: the same event sequence as parsing the fixture directly.
        var direct = SSEParser()
        var expected: [SSEEvent] = []
        for line in String(decoding: capture, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            if let e = direct.feed(String(line)) { expected.append(e) }
        }

        let actual = try FakeServerHarness.readEvents(port: port)
        #expect(actual == expected)

        process.terminate()
        process.waitUntilExit()
    }

    @Test func fakeRefusesWrongArgv() throws {
        let capture = try Data(contentsOf: FakeServerHarness.fixture("golden.short.sse"))
        let sidecar = try Data(contentsOf: FakeServerHarness.fixture("golden.short.sse.sidecar"))
        let port = try FakeServerHarness.freePort()
        let settings = makeSettings(port: port)

        let source = try FakeServerSource.generate(
            capture: capture, sidecar: sidecar,
            engineArgv: ServerCommand.argv(settings: settings)
        )
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("p2-fake-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeServerHarness.compileFake(source: source, into: work)

        // Wrong argv: context size differs from what the fake was generated with.
        var wrong = settings
        wrong.contextSize = 16384
        let process = try FakeServerHarness.spawn(binary, arguments: ServerCommand.argv(settings: wrong), env: ["FAKE_SPEED": "0"])
        let err = Pipe()
        process.standardError = err
        process.waitUntilExit()
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus != 0)
        #expect(stderr.contains("argv mismatch"))
    }

    @Test func fakeAnnouncesListeningOnStderr() throws {
        let capture = try Data(contentsOf: FakeServerHarness.fixture("golden.short.sse"))
        let sidecar = try Data(contentsOf: FakeServerHarness.fixture("golden.short.sse.sidecar"))
        let port = try FakeServerHarness.freePort()
        let settings = makeSettings(port: port)
        let source = try FakeServerSource.generate(
            capture: capture, sidecar: sidecar,
            engineArgv: ServerCommand.argv(settings: settings)
        )
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("p2-fake-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeServerHarness.compileFake(source: source, into: work)
        let process = try FakeServerHarness.spawn(binary, arguments: ServerCommand.argv(settings: settings), env: ["FAKE_SPEED": "0"])
        let err = Pipe()
        process.standardError = err
        let out = Pipe()
        process.standardOutput = out

        // Read one line of stderr; it must be the listening announcement.
        let handle = err.fileHandleForReading
        let lineData = handle.availableData
        let line = String(data: lineData, encoding: .utf8) ?? ""
        #expect(line.contains("listening on http://127.0.0.1:\(port)"))

        process.terminate()
        process.waitUntilExit()
    }
}
```

- [ ] **Step 2: Run to verify failure (fast tier still green)**

Run: `just test`
Expected: green (integration suites disabled without the env var — this is the gate working). Then run `just integration`.
Expected on first run: FAILURE — `FakeServerSource`-generated code does not yet exist / compile issues in the harness are surfaced here. Iterate until the three integration tests pass. (If a generated-source bug appears, fix the generator in Task 6's file, not the fake by hand.)

- [ ] **Step 3: Show the integration tier catches a real wire break**

Temporarily change `SSEParser`'s `.finish` mapping to require a nonexistent field (e.g., `choice["finish_reason_text"]`). Run `just integration` — `fakeReplaysCaptureEventsEquivalently` must fail (the parsed sequence diverges from the fixture). Restore the parser. Run `just integration` — green. (Records binding rule 2 at the integration tier: parser and fake drift together, so a wire change is caught.)

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiftStarIntegrationTests
git commit -m "P2: integration tier — fake engine compiled from capture, argv-strict"
```

---

### Task 8: The app — SwiftStar

**Files:**
- Create: `Sources/SwiftStar/SwiftStarApp.swift`, `Sources/SwiftStar/MainView.swift`, `Sources/SwiftStar/ChatView.swift`, `Sources/SwiftStar/EngineController.swift`, `Sources/SwiftStar/SettingsView.swift`, `Tools/make-icon.swift`, `Tools/make-app.sh`, `Sources/SwiftStar/Resources/AppIcon.icns`
- Delete: `Sources/SwiftStar/main.swift` (Task 1 placeholder)
- Modify: `Justfile` (app recipe)
- Test: fast-tier logic already in Kit; app verified by `just app` + live smoke (done-when 5) + a `SWIFTSTAR_LOG` transcript artifact

**Interfaces:**
- Consumes: `EngineSettings`, `ServerCommand`, `Supervisor`, `SSEParser`, `ChatTranscript` (all Kit).
- Produces: `just app` → `.build/SwiftStar.app` (bundle + icon); app with Chat tab, Settings scene, engine spawn/stream.

- [ ] **Step 1: EngineController (the thin app-side glue)**

Delete `Sources/SwiftStar/main.swift`. Create `Sources/SwiftStar/EngineController.swift`:

```swift
import Foundation
import Observation
import SwiftStarKit

@MainActor
@Observable
final class EngineController {
    var state: SupervisorState = .stopped
    private(set) var transcript = ChatTranscript()
    private(set) var stderrTail: [String] = []

    var settings: EngineSettings
    private var process: Process?
    private var parser = SSEParser()
    private let logURL: URL?

    init(settings: EngineSettings = EngineController.defaultSettings()) {
        self.settings = settings
        if let logPath = ProcessInfo.processInfo.environment["SWIFTSTAR_LOG"] {
            self.logURL = URL(fileURLWithPath: logPath)
        } else {
            self.logURL = nil
        }
    }

    static func defaultSettings() -> EngineSettings {
        let engineDir: URL
        if let dir = ProcessInfo.processInfo.environment["DS4_DIR"] {
            engineDir = URL(fileURLWithPath: dir)
        } else {
            engineDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("external/ds4")
        }
        let modelPath = URL(fileURLWithPath: "/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf")
        return EngineSettings(engineDir: engineDir, modelPath: modelPath, port: EngineController.probeFreePort())
    }

    static func probeFreePort() -> Int {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(s) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard r == 0 else { return 8000 }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var got = sockaddr_in()
        let g = withUnsafeMutablePointer(to: &got) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(s, $0, &len)
            }
        }
        guard g == 0 else { return 8000 }
        return Int(got.sin_port.bigEndian)
    }

    var canSend: Bool { state == .ready || state == .generating }

    func startEngine() {
        let binary = settings.engineDir.appendingPathComponent("ds4-server")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            state = Supervisor.transition(from: state, event: .engineMissing(binary))
            return
        }
        state = Supervisor.transition(from: state, event: .launchRequested)
        let process = Process()
        process.executableURL = binary
        process.arguments = ServerCommand.argv(settings: settings)
        process.environment = ProcessInfo.processInfo.environment
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()  // SSE goes to the HTTP layer, not stdout
        process.terminationHandler = { [weak self] p in
            Task { @MainActor in
                self?.process = nil
                self?.state = Supervisor.transition(from: self?.state ?? .stopped, event: .exit(p.terminationStatus))
            }
        }
        self.process = process
        do { try process.run() } catch {
            state = .failed(.exited(code: -1, stderrTail: "\(error)"))
        }
        Task {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                self.consumeStderr(String(line))
            }
        }
    }

    private func consumeStderr(_ line: String) {
        stderrTail.append(line)
        if stderrTail.count > 20 { stderrTail.removeFirst(stderrTail.count - 20) }
        log(line)
        state = Supervisor.transition(from: state, event: .stderrLine(line), port: settings.port, stderrTail: stderrTail)
    }

    func send(_ message: String) {
        transcript.appendSystem(message)
        if state != .ready, state != .generating { startEngine() }
        Task {
            await streamTurn(message)
        }
    }

    private func streamTurn(_ message: String) async {
        let url = URL(string: "http://127.0.0.1:\(settings.port)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "messages": [["role": "user", "content": message]],
            "stream": true,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            state = Supervisor.transition(from: state, event: .generationStarted)
            for try await line in bytes.lines {
                if let event = parser.feed(line) {
                    transcript.apply(event)
                    if case .finish = event { state = Supervisor.transition(from: state, event: .generationFinished) }
                }
            }
        } catch {
            log("stream error: \(error)")
            transcript.appendSystem("stream error: \(error.localizedDescription)")
            state = Supervisor.transition(from: state, event: .generationFinished)
        }
    }

    func stopEngine() {
        state = Supervisor.transition(from: state, event: .stopRequested)
        process?.terminate()
    }

    private func log(_ s: String) {
        guard let logURL else { return }
        try? (s + "\n").append(to: logURL)
    }
}
```

- [ ] **Step 2: ChatView + MainView**

`Sources/SwiftStar/ChatView.swift`:

```swift
import SwiftUI
import SwiftStarKit

struct ChatView: View {
    @State private var controller = EngineController()
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            transcriptView
            Divider()
            composer
        }
        .navigationTitle("Chat")
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText).font(.caption)
            Spacer()
            if controller.state == .ready || controller.state == .generating {
                Button("Stop Engine") { controller.stopEngine() }
            } else {
                Button("Start Engine") { controller.startEngine() }
            }
        }
        .padding(8)
    }

    private var statusText: String {
        switch controller.state {
        case .stopped: return "Engine stopped"
        case .starting: return "Starting engine…"
        case .ready: return "Engine ready"
        case .generating: return "Generating…"
        case .stopping: return "Stopping…"
        case .failed(let failure): return "Failed: \(failureDescription(failure))"
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .stopped: return .gray
        case .starting, .stopping: return .yellow
        case .ready: return .green
        case .generating: return .blue
        case .failed: return .red
        }
    }

    private func failureDescription(_ failure: EngineFailure) -> String {
        switch failure {
        case .engineMissing(let url): return "engine binary missing at \(url.path)"
        case .portInUse(let port): return "port \(port) is already in use"
        case .instanceLocked: return "another ds4 process is already running"
        case .exited(let code, let tail): return "engine exited (\(code)): \(tail)"
        case .timeout: return "engine start timed out"
        }
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(controller.transcript.rows.enumerated()), id: \.offset) { _, row in
                        rowView(row)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: TranscriptRow) -> some View {
        switch row {
        case .reasoning(let text):
            Text(text).font(.callout).foregroundStyle(.secondary).italic()
        case .content(let text):
            Text(text).font(.body).textSelection(.enabled)
        case .finished:
            EmptyView()
        case .system(let text):
            Text(text).font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var composer: some View {
        HStack {
            TextField("Message the engine", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button("Send", action: send)
                .disabled(!controller.canSend || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
    }

    private func send() {
        let message = input
        input = ""
        controller.send(message)
    }
}
```

`Sources/SwiftStar/MainView.swift`:

```swift
import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            PlaceholderView(title: "Agent", phase: "P7")
                .tabItem { Label("Agent", systemImage: "person.crop.circle") }
            PlaceholderView(title: "Metrics", phase: "P4")
                .tabItem { Label("Metrics", systemImage: "gauge.with.dots.needle.50percent") }
            PlaceholderView(title: "Diagnostics", phase: "P6")
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            PlaceholderView(title: "Help", phase: "P13")
                .tabItem { Label("Help", systemImage: "questionmark.circle") }
        }
        .frame(minWidth: 800, minHeight: 560)
    }
}

struct PlaceholderView: View {
    let title: String
    let phase: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.title2)
            Text("\(title) arrives in \(phase).").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`Sources/SwiftStar/SwiftStarApp.swift`:

```swift
import AppKit
import SwiftUI

@main
struct SwiftStarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("SwiftStar") {
            MainView()
        }
        .defaultSize(width: 900, height: 640)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

`Sources/SwiftStar/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("engineDir") private var engineDir = ""
    @AppStorage("modelPath") private var modelPath = ""
    @AppStorage("contextSize") private var contextSize = 32768
    @AppStorage("port") private var port = 0

    var body: some View {
        TabView {
            Form {
                TextField("Engine directory (DS4_DIR)", text: $engineDir)
                TextField("Model file", text: $modelPath)
                Stepper("Context size: \(contextSize)", value: $contextSize, in: 1024...262144, step: 1024)
                Stepper("Port (0 = auto): \(port)", value: $port, in: 0...65535, step: 1)
            }
            .padding(20)
            .frame(width: 460)
            .tabItem { Label("Engine", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 220)
    }
}
```

- [ ] **Step 3: Build the app target**

Run: `swift build`
Expected: `SwiftStar` executable builds. (Fast tests still green via `just test`.)

- [ ] **Step 4: Icon + bundle recipe**

`Tools/make-icon.swift` — renders a star-on-rounded-rect at all iconset sizes and runs `iconutil`:

```swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(named: "iconBg") ?? NSColor.systemIndigo.setFill()
    NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
    let star = NSBezierPath()
    let center = NSPoint(x: size / 2, y: size / 2)
    let radius = Double(size) * 0.34
    for i in 0..<10 {
        let angle = Double.pi / 2 + Double(i) * Double.pi / 5
        let r = (i % 2 == 0) ? radius : radius * 0.45
        let p = NSPoint(x: center.x + CGFloat(cos(angle) * r), y: center.y + CGFloat(sin(angle) * r))
        if i == 0 { star.move(to: p) } else { star.line(to: p) }
    }
    star.close()
    NSColor.white.setFill()
    star.fill()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let filename = size <= 512
        ? "icon_\(size)x\(size).png"
        : "icon_512x512@2x.png"
    try png.write(to: iconset.appendingPathComponent(filename))
}
```

`Tools/make-app.sh`:

```bash
#!/usr/bin/env bash
# Assemble .build/SwiftStar.app from the release build + committed icon.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
APP=.build/SwiftStar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SwiftStar "$APP/Contents/MacOS/SwiftStar"
cp Sources/SwiftStar/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SwiftStar</string>
    <key>CFBundleDisplayName</key><string>SwiftStar</string>
    <key>CFBundleIdentifier</key><string>com.pauleveritt.SwiftStar</string>
    <key>CFBundleExecutable</key><string>SwiftStar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
PLIST
echo "Wrote $APP"
```

Generate + commit the icon:

```bash
chmod +x Tools/make-app.sh
mkdir -p /tmp/ss-icon && swift Tools/make-icon.swift /tmp/ss-icon/AppIcon.iconset
iconutil -c icns /tmp/ss-icon/AppIcon.iconset -o Sources/SwiftStar/Resources/AppIcon.icns
ls -la Sources/SwiftStar/Resources/AppIcon.icns
```

`Justfile` — add the `app` recipe:

```justfile
# Assemble .build/SwiftStar.app (release build + Info.plist + icon)
app:
    Tools/make-app.sh
```

- [ ] **Step 5: Bundle + smoke**

Run: `just app`
Expected: `.build/SwiftStar.app` exists; `open .build/SwiftStar.app` (or run the binary directly) launches; the window shows five tabs; ⌘, opens Settings.

Run the log-producing smoke (evidence without the screen):

```bash
cd ~/projects/pauleveritt/swiftstar
DS4_DIR=$PWD/external/ds4 SWIFTSTAR_LOG=/tmp/p2-live-smoke.log .build/SwiftStar.app/Contents/MacOS/SwiftStar &
SMOKE_PID=$!
sleep 180   # model load + one turn is minutes; the log records the transcript
kill $SMOKE_PID 2>/dev/null
tail -20 /tmp/p2-live-smoke.log
```

Expected: the log shows engine stderr (`listening on http://…`, `ds4: memory:` line) and, after a send, `content` rows — evidence of a real streamed turn. (The chat turn must be triggered for the smoke; if the app requires a manual Send, note in the log run that the smoke verifies launch/engine-ready only, and record the send-trigger as a manual step for the human. Simpler: the smoke is a launch+ready check with a note.)

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStar Tools Justfile
git commit -m "P2: SwiftStar app — window, chat, settings, icon, bundle"
```

---

### Task 9: ROADMAP close + concept budget

**Files:**
- Modify: `ROADMAP.md` (P2 status → complete; concept budget terms defined)
- Create: `docs/superpowers/research/2026-08-22-p2-verification-record.md` (test evidence, shown-fail records, smoke result)

- [ ] **Step 1: Verification record**

Write `docs/superpowers/research/2026-08-22-p2-verification-record.md` with: `just test` output (counts), tripwire demonstration (probe test added → build failed → removed), `just integration` output (3 tests), `just app` bundle existence, live-smoke log excerpt, and the shown-fail/recover records from Tasks 3–7.

- [ ] **Step 2: ROADMAP update**

`ROADMAP.md`: P2 row → `complete (2026-08-22)`; move the P2 prose under "Now" to "Prior work"; define in the concept budget: **seam**, **wire**, **capture**, **fixture** (the plan glossary, promoted).

- [ ] **Step 3: Final gates**

Run `just test` and `just integration` — both green. Run `git status` — clean.

- [ ] **Step 4: Commit**

```bash
git add ROADMAP.md docs/superpowers/research/2026-08-22-p2-verification-record.md
git commit -m "P2: close — roadmap, concept budget, verification record"
```

---

## Self-Review (run before execution)

**Spec coverage:** every spec D and done-when item maps to a task — D1 targets (T1, T8), D2 gating (T1 Justfile, T7 `@Suite(.enabled)`), D3 tripwire (T2), D4 parser (T3), D5 argv contract (T1, enforced at T6/T7), D6 supervisor (T4), D7 fake generator (T6/T7), D8 app (T8), D9 scope (no tasks for P3+ work). Done-when 1–7 → T1/T3/T4/T5/T6 fast (1), T2 (2), T7 (3), T8/T9 (4, 5, 7).

**Placeholder scan:** every step has real code or a real command; no TBDs.

**Type consistency:** `EngineSettings`/`ServerCommand.argv` defined T1, consumed T6/T7/T8. `SSEEvent`/`SSEParser.feed` T3, consumed T5/T7/T8. `SupervisorState`/`SupervisorEvent`/`transition(from:event:port:stderrTail:)` T4, consumed T8. `TranscriptRow`/`ChatTranscript` T5, consumed T8. `FakeServerSource.generate(capture:sidecar:engineArgv:)` T6, consumed T7. `FAKE_SPEED` env T6/T7.
