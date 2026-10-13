import Foundation
import SwiftStarKit

/// Fixture states for SwiftUI previews, shared across views that need a
/// representative `EngineController` or `EngineToolCard` without spawning
/// a real engine process.
extension EngineController {
    static var previewIdle: EngineController {
        EngineController(model: EngineSessionModel())
    }

    /// A running session, mid-conversation: one answered turn with a tool
    /// call, metrics populated, awaiting the next prompt.
    static var previewRunning: EngineController {
        EngineController(
            model: runningModel(withGPU: true), conversations: .preview,
            workspace: URL(fileURLWithPath: "/Users/example/projects/swiftstar"))
    }

    /// The running session without GPU metrics, as before the engine's first
    /// `memory` event: the status bar shows no memory widget.
    static var previewRunningNoGPU: EngineController {
        EngineController(model: runningModel(withGPU: false))
    }

    private static func runningModel(withGPU: Bool) -> EngineSessionModel {
        var model = EngineSessionModel()
        // `.ready` only moves a `.starting` session to `.running`. Left
        // `.idle`, SessionView's auto-start `.task` calls `start()` inside
        // the preview and this fixture's state is lost.
        model.didStart()
        model.apply(.ready)
        model.apply(.session(EngineSessionInfo(
            modelID: "qwen3.8-27b", contextSize: 8192,
            dflash: EngineDFlash(
                on: true, reason: "plan 19.27 GiB <= budget 107.52 GiB",
                drafter: "/Users/example/models/dflash-Qwen3.8-27B-Q4_0.gguf"))))
        model.apply(.prefixCache(EnginePrefixCache(outcome: "hit", tokens: 944, loadMs: 20, fillMs: nil)))
        _ = model.send("Summarize SessionView.swift")
        model.apply(.prompt("Summarize SessionView.swift"))
        let tool = EngineTool(op: "read", path: "Sources/SwiftStarUI/Session/SessionView.swift")
        model.apply(.toolStart(tool))
        model.apply(.toolEnd(tool, ok: true, durationMs: 420))
        model.apply(.toolResult(EngineToolResult(
            tool: tool, preview: "struct SessionView: View {\n    @Environment(EngineController.self)...",
            truncated: true)))
        model.apply(.answer(EngineAnswer(
            text: "`SessionView` renders the transcript, composer, and status bar for one engine session.",
            contextUsed: 512, contextSize: 8192, durationMs: 1830)))
        // Session 20261013-154825's first checkpoint, after its 944-token cache hit.
        model.apply(.pause(PauseMetrics(
            prefillTokens: 1146, prefillMs: 1084, evalCount: 64, evalMs: 980,
            capturePath: "/Users/example/.local/state/ds4-engine/sessions/20261013-121126-swiftstar/run-1.partial.json")))
        if withGPU {
            model.apply(.memory(EngineMemory(allocatedBytes: 6_400_000_000, budgetBytes: 21_000_000_000, planGiB: 6.0)))
        }
        model.apply(.awaitingInput)
        return model
    }
}

extension EngineMetricsState {
    /// The running fixture's metrics, for views that take metrics as a value.
    static var previewRunning: EngineMetricsState {
        EngineController.previewRunning.metrics
    }
}

extension EngineToolCard {
    static var previewRunning: EngineToolCard {
        EngineToolCard(tool: EngineTool(op: "read", path: "Sources/SwiftStarUI/Session/SessionView.swift"))
    }

    static var previewSucceeded: EngineToolCard {
        EngineToolCard(
            tool: EngineTool(op: "read", path: "Sources/SwiftStarUI/Session/SessionView.swift"),
            ok: true, durationMs: 420,
            result: EngineToolResult(
                tool: EngineTool(op: "read", path: "Sources/SwiftStarUI/Session/SessionView.swift"),
                preview: "struct SessionView: View {\n    @Environment(EngineController.self) private var controller",
                truncated: true))
    }

    /// A call the engine declined: the loop guard's `repeated-call`.
    static var previewDeclined: EngineToolCard {
        let rejection = EngineToolRejection(
            name: "read", reason: "repeated-call", path: "Package.swift",
            text: "Tool error: the same read was called three times in a row")
        return EngineToolCard(tool: EngineTool(op: "read", path: "Package.swift"), rejection: rejection)
    }

    static var previewFailed: EngineToolCard {
        EngineToolCard(
            tool: EngineTool(op: "bash", path: nil),
            ok: false, durationMs: 3_200,
            result: EngineToolResult(
                tool: EngineTool(op: "bash", path: nil),
                preview: "command not found: swiift", truncated: false))
    }
}

/// `UserDefaults` for previews that need a stored setting, kept out of the
/// real app's defaults: apply with `.defaultAppStorage(...)`.
enum PreviewDefaults {
    /// The transcript font at its largest slot.
    static var largeFont: UserDefaults {
        let defaults = UserDefaults(suiteName: "SwiftStarPreview.largeFont") ?? .standard
        defaults.set(TranscriptFontScale.sizes.last, forKey: DefaultsKey.transcriptFontSize.rawValue)
        return defaults
    }
}

extension EngineTranscript {
    /// After `/rewind 1`: the divider, then the one turn the engine kept
    /// (the shape of `fixtures/engine/resumed.ndjson`).
    static var previewRewound: EngineTranscript {
        var t = EngineTranscript()
        t.rebuild(
            from: EngineResumed(
                sessionID: "20261013-113020-swiftstar",
                turns: [.init(prompt: "Answer in one short sentence, without tools: what is 2 + 2?",
                              answer: "2 + 2 equals 4.", stopped: false)],
                rewoundTo: 1, filesChanged: 0, contextUsed: 1071),
            divider: "Rewound to prompt 1")
        return t
    }
}

extension [Conversation] {
    /// Three conversations for the sidebar: the second is the running one,
    /// the third can't be resumed.
    static var preview: [Conversation] {
        let now = Date()
        return [
            Conversation(
                id: "20261013-123136-swiftstar", title: "Hello", updated: now.addingTimeInterval(-12 * 60),
                modelID: "qwen3.8-flash-next", resumable: true, problems: [],
                sessionIDs: ["20261013-123136-swiftstar", "20261013-122439-swiftstar"]),
            Conversation(
                id: "20261013-121126-swiftstar",
                title: "Answer in one short sentence, without tools: what is 2 + 2?",
                updated: now.addingTimeInterval(-40 * 60), modelID: "qwen3.8-27b", resumable: true, problems: [],
                sessionIDs: ["20261013-121126-swiftstar", "20261013-121116-swiftstar"]),
            Conversation(
                id: "20261003-203830-swiftstar", title: "Untitled", updated: now.addingTimeInterval(-10 * 86_400),
                modelID: "laguna-xs-2.1", resumable: false, problems: ["no receipt", "no capture"],
                sessionIDs: ["20261003-203830-swiftstar"]),
        ]
    }
}
