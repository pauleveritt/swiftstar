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
            TranscriptView(transcript: controller.transcript, workspace: controller.workspace)
            Divider()
            ComposerView()
            Divider()
            StatusBarView(phase: controller.phase, composerLabel: controller.composer.label, metrics: controller.metrics)
        }
        .navigationTitle("Agent")
        .toolbar {
            SessionToolbar(
                askingModel: $askingModel, askingContext: $askingContext,
                entry: $entry, inspectorPresented: $inspectorPresented)
        }
        // Applied after the toolbar so its items, too, sit below this value.
        .environment(\.transcriptFontSize, CGFloat(TranscriptFontScale.clamp(transcriptFontSize)))
        .task { if controller.phase == .idle { controller.start() } }
        .task { await controller.loadCatalogIfNeeded() }
        .alert("Other model", isPresented: $askingModel) {
            TextField("Model id", text: $entry)
            Button("Use") { controller.select(modelID: entry) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type an engine model id, e.g. laguna-xs-2.1. A running session restarts.")
        }
        .alert("Custom context size", isPresented: $askingContext) {
            TextField("Tokens", text: $entry)
            Button("Use") {
                if let n = Int(entry.trimmingCharacters(in: .whitespaces)), n > 0 {
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

#Preview("Large font", traits: .runningSession) {
    SessionView()
        .defaultAppStorage(PreviewDefaults.largeFont)
}
