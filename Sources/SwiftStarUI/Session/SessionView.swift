import SwiftUI
import SwiftStarKit

/// One engine session's window content: the parts in `Session/`, composed,
/// plus the session's start-up tasks and the toolbar's two entry alerts.
struct SessionView: View {
    @Environment(EngineController.self) private var controller
    @AppStorage(DefaultsKey.inspectorPresented.rawValue) private var inspectorPresented = false
    @State private var askingModel = false
    @State private var askingContext = false
    @State private var entry = ""
    @AppStorage(DefaultsKey.transcriptFontSize.rawValue) private var transcriptFontSize = TranscriptFontScale.defaultSize

    var body: some View {
        VStack(spacing: 0) {
            if controller.model.showsAnalysisBanner {
                AnalysisBanner(canFinish: controller.model.canFinishAnalysis, done: controller.doneAnalyzing)
                Divider()
            }
            TranscriptView(
                transcript: controller.transcript, source: controller.source,
                analyze: controller.canAnalyze ? { Task { await controller.analyze() } } : nil,
                analysisFirstRow: controller.analysis?.firstRow)
            Divider()
            ComposerView()
            Divider()
            StatusBarView(phase: controller.phase, composerLabel: controller.composer.label, metrics: controller.metrics)
        }
        .navigationTitle(WindowTitle.text(workspace: controller.workspace))
        .toolbar {
            SessionToolbar(
                askingModel: $askingModel, askingContext: $askingContext,
                entry: $entry, inspectorPresented: $inspectorPresented)
        }
        // Applied after the toolbar so its items, too, sit below this value.
        .environment(\.transcriptFontSize, CGFloat(TranscriptFontScale.clamp(transcriptFontSize)))
        // One task: the start waits for the model list, so a saved model the
        // engine dropped is cleared before the spawn (EN.1, D1).
        .task {
            if controller.phase == .idle { await controller.start() }
            else { await controller.loadCatalogIfNeeded() }
        }
        // No usable workspace (SU.6c, D1): ask for one, and start in it.
        // The modal panel runs on a later main-actor turn, not inside
        // SwiftUI's update of `.onChange` (final review).
        .onChange(of: controller.wantsFolder) { _, wants in
            guard wants else { return }
            Task { @MainActor in
                if let url = WorkspacePicker.run(from: controller.workspace) {
                    controller.select(workspace: url)
                    await controller.start()
                } else {
                    controller.folderPickerDismissed()
                }
            }
        }
        .alert("Other model", isPresented: $askingModel) {
            TextField("Model id", text: $entry)
            Button("Use") { controller.select(modelID: entry) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type an engine model id, e.g. qwen3.8-27b. A running session switches with /model and keeps its files.")
        }
        .alert("Custom context size", isPresented: $askingContext) {
            TextField("Tokens", text: $entry)
            Button("Use") {
                if let n = ContextMenu.parseCustom(entry) {
                    controller.select(contextSize: n)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type a context size in tokens. A running session restarts.")
        }
    }
}

#Preview("Running", traits: .runningSession) {
    SessionView()
}

#Preview("Idle", traits: .idleSession) {
    SessionView()
}

#Preview("Analyzing") {
    // Its own controller, built fresh for this preview.
    SessionView()
        .environment(EngineController(model: .previewAnalyzing))
}

#Preview("Large font", traits: .runningSession) {
    SessionView()
        .defaultAppStorage(PreviewDefaults.largeFont)
}
