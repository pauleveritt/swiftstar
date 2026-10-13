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
        EngineController(model: runningModel(withGPU: true))
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
        model.apply(.session(EngineSessionInfo(id: "preview", modelID: "laguna-xs-2.1", contextSize: 8192)))
        _ = model.send("Summarize SessionView.swift")
        model.apply(.prompt("Summarize SessionView.swift"))
        let tool = EngineTool(op: "read", path: "Sources/SwiftStarUI/SessionView.swift")
        model.apply(.toolStart(tool))
        model.apply(.toolEnd(tool, ok: true, durationMs: 420))
        model.apply(.toolResult(EngineToolResult(
            tool: tool, preview: "struct SessionView: View {\n    @Environment(EngineController.self)...",
            truncated: true)))
        model.apply(.answer(EngineAnswer(
            text: "`SessionView` renders the transcript, composer, and status bar for one engine session.",
            contextUsed: 512, contextSize: 8192, durationMs: 1830)))
        model.apply(.pause(PauseMetrics(prefillTokens: 512, prefillMs: 210, evalCount: 64, evalMs: 980)))
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
        EngineToolCard(tool: EngineTool(op: "read", path: "Sources/SwiftStarUI/SessionView.swift"))
    }

    static var previewSucceeded: EngineToolCard {
        EngineToolCard(
            tool: EngineTool(op: "read", path: "Sources/SwiftStarUI/SessionView.swift"),
            ok: true, durationMs: 420,
            result: EngineToolResult(
                tool: EngineTool(op: "read", path: "Sources/SwiftStarUI/SessionView.swift"),
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
