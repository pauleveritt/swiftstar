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
    /// call, metrics populated, awaiting the next prompt. Its workspace has
    /// files, so the gallery's `@` picker opens (SU.17).
    static var previewRunning: EngineController {
        EngineController(
            model: runningModel(withGPU: true), conversations: .preview,
            workspace: URL(fileURLWithPath: "/Users/example/projects/swiftstar"), workspaceFiles: .previewFiles,
            catalog: .preview, source: previewCheckout)
    }

    /// This repository, where the previews' file names exist, so their
    /// links resolve (SU.16). A path on the machine that built the preview.
    static let previewCheckout = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// The running session without GPU metrics, as before the engine's first
    /// `memory` event: the status bar shows no memory widget.
    static var previewRunningNoGPU: EngineController {
        EngineController(model: runningModel(withGPU: false))
    }

    static func runningModel(withGPU: Bool) -> EngineSessionModel {
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
        // EN.2's start-up reports, in the engine's order (ds4-engine tests/test_baseline.py:136-141).
        model.apply(.startup(.baseline(commit: "5cc0836aa1", excludedCount: 1), summary:
            "The model works on a clean copy of commit 5cc0836; 1 uncommitted file in your checkout is not included: app.py."))
        model.apply(.startup(.candidateReady(createdMs: 812, waitedMs: 40), summary: nil))
        model.apply(.startup(.envSync(outcome: "ok", durationMs: 2300), summary: nil))
        model.apply(.startup(.projectInstructions(file: "AGENTS.md", tokens: 1000, cut: false), summary:
            "Loaded AGENTS.md (40 lines, about 1,000 tokens)."))
        model.apply(.prefixCache(EnginePrefixCache(
            outcome: "hit", tokens: 944, loadMs: 20, fillMs: nil, entryFillMs: 1729)))
        _ = model.send("Summarize SessionView.swift")
        model.apply(.prompt("Summarize SessionView.swift"))
        let tool = EngineTool(op: "read", path: "Sources/SwiftStarUI/Session/SessionView.swift")
        model.apply(.toolStart(tool))
        model.apply(.toolEnd(tool, ok: true, durationMs: 420))
        model.apply(.toolResult(EngineToolResult(
            tool: tool, preview: "struct SessionView: View {\n    @Environment(EngineController.self)...",
            truncated: true)))
        model.apply(.answer(EngineAnswer(
            text: "`SessionView.swift` renders the transcript, composer, and status bar for one engine session.",
            contextUsed: 512, contextSize: 8192, durationMs: 1830)))
        // Session 20261013-154825's first checkpoint, after its 944-token cache hit.
        model.apply(.pause(PauseMetrics(
            prefillTokens: 1146, prefillMs: 1084, evalCount: 64, evalMs: 980,
            capturePath: "/Users/example/.local/state/ds4-engine/sessions/20261013-121126-swiftstar/run-1.partial.json")))
        model.apply(.startup(.indexPrimed(sinceStartMs: 3336), summary: nil))
        if withGPU {
            model.apply(.memory(EngineMemory(allocatedBytes: 6_400_000_000, budgetBytes: 21_000_000_000, planGiB: 9.4)))
        }
        model.apply(.awaitingInput)
        return model
    }
}

extension EngineModelList {
    /// `fixtures/engine/models-real.json`'s three models (ds4-engine
    /// `models --json`, EN.2): sizes and plans for the menus' titles.
    static let preview: EngineModelList? = try? EngineModelList.decode(Data("""
        {"gpu_budget_bytes": 115448725504, "models": [
          {"id": "qwen3.8-27b", "display_name": "Qwen3.8 27B", "on_this_mac": true,
           "path": "/Users/example/models/Qwen3.8-27B-Q4_K_M.gguf", "size_bytes": 16810714336,
           "downloadable": true, "fits": true, "context": 131072, "plan_gib": 24.74},
          {"id": "qwen3.8-flash-next", "display_name": "Qwen3.8 Flash Next", "on_this_mac": true,
           "path": "/Users/example/models/flash-next.gguf", "size_bytes": 177280286720,
           "downloadable": true, "fits": true, "context": 20000, "plan_gib": 77.91},
          {"id": "qwen3.8-flash-next-q2", "display_name": "Qwen3.8 Flash Next Q2", "on_this_mac": false,
           "path": null, "size_bytes": 147207127040, "downloadable": true, "fits": null,
           "context": null, "plan_gib": null}]}
        """.utf8)).get()
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

    /// A `run` that fell back to bash (SU.18), its output headed as the
    /// engine heads it (ds4-engine `run_tool.py:119-124`).
    static func previewBash(_ preview: String) -> EngineToolCard {
        let tool = EngineTool(op: "run", path: "")
        return EngineToolCard(
            tool: tool, ok: true, durationMs: 2400,
            result: EngineToolResult(tool: tool, preview: preview, truncated: false))
    }

    /// EN.2's `git` and `test` calls: no path on the wire, so no link.
    static var previewGit: EngineToolCard {
        let tool = EngineTool(op: "git", path: "")
        return EngineToolCard(
            tool: tool, ok: true, durationMs: 40,
            result: EngineToolResult(tool: tool, preview: """
                diff --git a/Sources/SwiftStarKit/Severity.swift b/Sources/SwiftStarKit/Severity.swift
                @@ -3,7 +3,7 @@
                -    case warning
                +    case caution
                """, truncated: false))
    }

    static var previewTest: EngineToolCard {
        let tool = EngineTool(op: "test", path: "")
        return EngineToolCard(
            tool: tool, ok: true, durationMs: 2300,
            result: EngineToolResult(tool: tool, preview: """
                [pytest with the project's .venv: exit 1 in 2.3 s]
                FAILED tests/test_app.py::test_start - AssertionError
                1 failed, 12 passed
                """, truncated: false))
    }

    /// A finished `read` of `path` returning `preview` (SU.15's languages).
    static func previewRead(_ path: String, _ preview: String) -> EngineToolCard {
        let tool = EngineTool(op: "read", path: path)
        return EngineToolCard(
            tool: tool, ok: true, durationMs: 12,
            result: EngineToolResult(tool: tool, preview: preview, truncated: false))
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
        defaults.set(TranscriptFontScale.sizes.last, forKey: DefaultsKey.fontSize.rawValue)
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

    /// ds4-engine's report (AN.4) on `fixtures/sessions/20261013-123136-swiftstar`,
    /// as `SessionReport.markdown` renders `fixtures/engine/report.json`, trimmed.
    static let previewReport = """
        **report**: 20261013-123136-swiftstar, qwen3.8-flash-next, ctx 20,000, 188s, answered

        ### Flagged steps

        | Prompt | Did | Why |
        |---|---|---|
        | 2 | run | failed: Tool error: unknown tool: run. There is no shell, so nothing can be ru… |
        | 2 | run | refused: unknown-tool |
        | 4 | read Sources/SwiftStarKit/Severity.swift | loop guard: already_shown |
        | — | — | loop guard fired: already_shown x2 |

        ### Session

        | Row | Value |
        |---|---|
        | Continues | 20261013-122439-swiftstar (3 prompts), 20261013-122106-swiftstar (1 of 4 prompts kept) |
        | Prefix cache | prompt 1: prefix-cache miss: 944 tokens filled, 1.75 s spent; what changed was not recorded |

        ### Prefill

        | Prompt | Step | After | Tokens | Time | Rate | Label |
        |---|---|---|---|---|---|---|
        | 2 | 1 | user | 45 | 794 ms | 56.7 tok/s | short batch, two tiles, fixed cost |
        | 2 | 5 | host_results | 32 | 104 ms | 306.3 tok/s | short batch, fixed cost |

        19 syncs with nothing new to prefill are not listed.
        """
}

extension EngineSessionModel {
    /// In an analysis's fork (AN.2): the main session's turn rebuilt, the
    /// report card, the analysis prompt and its answer, at `input`.
    static var previewAnalyzing: EngineSessionModel {
        var model = EngineController.runningModel(withGPU: true)
        guard let fork = model.beginAnalysis(
            report: EngineTranscript.previewReport, source: URL(fileURLWithPath: "/repo")) else { return model }
        model.didRelaunch(fork)
        model.apply(.ready)
        model.apply(.resumed(EngineResumed(
            sessionID: "20261013-123136-swiftstar",
            turns: [.init(prompt: "Summarize SessionView.swift",
                          answer: "`SessionView` renders the transcript, composer, and status bar.", stopped: false)],
            rewoundTo: nil, filesChanged: 0, contextUsed: 512)))
        model.apply(.awaitingInput)
        if let prompt = model.takeAnalysisPrompt() {
            _ = model.send(prompt.text, shown: prompt.shown)
            model.apply(.prompt(prompt.text))
            model.apply(.answer(EngineAnswer(
                text: "Step 17 called `run`, which doesn't exist: there is no shell. Steps 36–37 re-read files the engine had already shown. Remedy: name the available tools in the prompt, and check the list before calling.",
                contextUsed: 1300, contextSize: 8192, durationMs: 2400)))
            model.apply(.awaitingInput)
        }
        return model
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

extension [String] {
    /// The `@` picker's files (SU.14): real paths from this repository, so
    /// the canvas never runs git.
    static var previewFiles: [String] {
        [
            "Package.swift",
            "README.md",
            "ROADMAP.md",
            "Sources/SwiftStar/SwiftStarApp.swift",
            "Sources/SwiftStarEngine/EngineJSONCommand.swift",
            "Sources/SwiftStarEngine/EngineModelCatalogLoader.swift",
            "Sources/SwiftStarEngine/EngineSession.swift",
            "Sources/SwiftStarEngine/PipeReading.swift",
            "Sources/SwiftStarEngine/ProcessRunner.swift",
            "Sources/SwiftStarEngine/SessionListLoader.swift",
            "Sources/SwiftStarEngine/SessionReportLoader.swift",
            "Sources/SwiftStarEngine/WorkspaceFileLister.swift",
            "Sources/SwiftStarGallery/GalleryApp.swift",
            "Sources/SwiftStarKit/DefaultsKey.swift",
            "Sources/SwiftStarKit/EngineAnalysis.swift",
            "Sources/SwiftStarKit/EngineCommand.swift",
            "Sources/SwiftStarKit/EngineEvent.swift",
            "Sources/SwiftStarKit/EngineExit.swift",
            "Sources/SwiftStarKit/EngineGraces.swift",
            "Sources/SwiftStarKit/EngineMetrics.swift",
            "Sources/SwiftStarKit/EngineModelCatalog.swift",
            "Sources/SwiftStarKit/EngineSessionList.swift",
            "Sources/SwiftStarKit/EngineSessionModel.swift",
            "Sources/SwiftStarKit/EngineTranscript.swift",
            "Sources/SwiftStarKit/EngineWireParser.swift",
            "Sources/SwiftStarKit/FileMentions.swift",
            "Sources/SwiftStarKit/Foundation+SwiftStar.swift",
            "Sources/SwiftStarKit/MarkdownPreprocess.swift",
            "Sources/SwiftStarKit/MetricsFormatting.swift",
            "Sources/SwiftStarKit/ProjectRoot.swift",
            "Sources/SwiftStarKit/PromptHistory.swift",
            "Sources/SwiftStarKit/Severity.swift",
            "Sources/SwiftStarKit/ToolbarMenus.swift",
            "Sources/SwiftStarKit/TranscriptFontScale.swift",
            "Sources/SwiftStarKit/WindowTitle.swift",
            "Sources/SwiftStarKit/WorkspaceChoice.swift",
            "Sources/SwiftStarUI/Components/FontSize.swift",
            "Sources/SwiftStarUI/Components/NativeTooltip.swift",
            "Sources/SwiftStarUI/Components/ValueGaugeView.swift",
            "Sources/SwiftStarUI/Components/WorkspacePicker.swift",
            "Sources/SwiftStarUI/Inspector/InspectorView.swift",
            "Sources/SwiftStarUI/PreviewSupport/Gallery.swift",
            "Sources/SwiftStarUI/PreviewSupport/PreviewFixtures.swift",
            "Sources/SwiftStarUI/PreviewSupport/PreviewTraits.swift",
            "Sources/SwiftStarUI/Session/AnalysisBanner.swift",
            "Sources/SwiftStarUI/Session/ComposerView.swift",
            "Sources/SwiftStarUI/Session/MemoryStatusView.swift",
            "Sources/SwiftStarUI/Session/RecentProjectRows.swift",
            "Sources/SwiftStarUI/Session/SessionToolbar.swift",
            "Sources/SwiftStarUI/Session/SessionView.swift",
            "Sources/SwiftStarUI/Session/StatusBarView.swift",
            "Sources/SwiftStarUI/Session/TranscriptRowView.swift",
            "Sources/SwiftStarUI/Session/TranscriptView.swift",
            "Sources/SwiftStarUI/Settings/SettingsView.swift",
            "Sources/SwiftStarUI/Shell/MainView.swift",
            "Sources/SwiftStarUI/Shell/SwiftStarCommands.swift",
            "Sources/SwiftStarUI/Sidebar/ConversationList.swift",
            "Sources/SwiftStarUI/State/EngineController.swift",
            "Sources/SwiftStarUI/Transcript/MarkdownText.swift",
            "Sources/SwiftStarUI/Transcript/PromptBubble.swift",
        ]
    }
}
