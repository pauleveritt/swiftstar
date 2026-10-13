import Foundation
import Testing
import SwiftStarKit

extension Trait where Self == ConditionTrait {
    /// The integration tier: real processes, run by `just integration`.
    static var integration: Self {
        .enabled(
            if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1",
            "set SWIFTSTAR_INTEGRATION=1 (just integration)")
    }
}

extension Tag {
    @Tag static var integration: Self
}

/// The committed engine fixtures (`fixtures/engine/`).
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/engine")

    static func path(_ name: String) -> String { root.appendingPathComponent(name).path }
}

/// Polls until `condition` holds, or `within` passes; returns whether it held.
@discardableResult
func eventually(within: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + within
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

/// A fresh path in the temporary directory; nothing is created.
func tempPath(_ name: String) -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("swiftstar-\(name)-\(UUID().uuidString)").path
}

/// Sets each key (a nil value removes it) until `restore()`, which puts back
/// every key's previous value. The test runner's own defaults domain, not the
/// app's. Use as `let defaults = DefaultsScope(...); defer { defaults.restore() }`.
///
/// Not a `withDefaults { ... }` closure: Swift 6.4 can give a closure written
/// inside `#expect(...)` and another same-typed closure in the same enclosing
/// closure one identity, so one body runs in place of the other (SU.5b Task 5
/// found `eventually { A }` running `B`). Test bodies stay at function level.
struct DefaultsScope {
    private let saved: [(DefaultsKey, Any?)]

    init(_ values: [DefaultsKey: Any?]) {
        let defaults = UserDefaults.standard
        saved = values.keys.map { ($0, defaults.object(forKey: $0.rawValue)) }
        for (key, value) in values {
            if let value { defaults.set(value, forKey: key.rawValue) } else { defaults.removeObject(forKey: key.rawValue) }
        }
    }

    func restore() {
        for (key, value) in saved {
            if let value { UserDefaults.standard.set(value, forKey: key.rawValue) }
            else { UserDefaults.standard.removeObject(forKey: key.rawValue) }
        }
    }
}

/// One JSON array per line (an argv log), unparseable lines skipped.
func argvLog(_ path: String) -> [[String]] {
    ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
        .split(separator: "\n")
        .compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String] }
}

/// `fake-ds4-dogfood` behind a `/bin/sh` wrapper that bakes in its
/// environment: `EngineController` spawns with the test process's
/// environment, so the fake's settings can't come from the test. Every
/// setting is a parameter. `remove()` also SIGKILLs every `tui` process it
/// started: `EngineSession`'s deinit sends only SIGTERM, which a fake told to
/// ignore it would outlive.
struct FakeEngine {
    let script = tempPath("wrapper"), spawns = tempPath("spawns"), inputs = tempPath("inputs"),
        pids = tempPath("pids")

    init(
        fixture: String = "tool-read.ndjson", resumeFixture: String = "resumed.ndjson",
        models: String = "models-real.json", sessions: String? = nil, refuseResume: Bool = false,
        extra: [String: String] = [:]
    ) throws {
        var lines = [
            "#!/bin/sh",
            "export FAKE_ENGINE_FIXTURE=\(Fixtures.path(fixture))",
            "export FAKE_ENGINE_RESUME_FIXTURE=\(Fixtures.path(resumeFixture))",
            "export FAKE_ENGINE_MODELS=\(Fixtures.path(models))",
            "export FAKE_ENGINE_SPAWN_LOG=\(spawns)",
            "export FAKE_ENGINE_LOG=\(inputs)",
            "export FAKE_ENGINE_PACE_MS=50",
        ]
        if let sessions { lines.append("export FAKE_ENGINE_SESSIONS=\(Fixtures.path(sessions))") }
        if refuseResume { lines.append(#"case "$*" in *--resume*) export FAKE_ENGINE_REFUSE=1;; esac"#) }
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { lines.append("export \(k)=\(v)") }
        lines.append(#"case "$1" in tui) echo $$ >> "# + pids + ";; esac")
        lines.append("exec /usr/bin/env python3 \(Fixtures.path("fake-ds4-dogfood")) \"$@\"")
        try lines.joined(separator: "\n").write(toFile: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
    }

    /// The argv of each `tui` spawn, in order.
    var spawnArgv: [[String]] { argvLog(spawns) }

    /// The text of each prompt the fake received, in order.
    var prompts: [String] {
        ((try? String(contentsOfFile: inputs, encoding: .utf8)) ?? "")
            .split(separator: "\n")
            .compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
            .compactMap { $0["text"] as? String }
    }

    func remove() {
        for pid in ((try? String(contentsOfFile: pids, encoding: .utf8)) ?? "").split(separator: "\n") {
            if let pid = Int32(pid), pid > 0 { kill(pid, SIGKILL) }
        }
        for p in [script, spawns, inputs, pids] { try? FileManager.default.removeItem(atPath: p) }
    }
}
