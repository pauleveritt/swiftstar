import SwiftUI

// Shared controller fixtures for previews, applied as traits:
// `#Preview("Running", traits: .runningSession) { SessionView() }`.
//
// Each modifier's context is built once and shared, by reference, across every
// preview that uses it. A preview that mutates the controller (sending a
// prompt, say) should build its own fixture in the preview body instead.
// Fixture controllers never start the engine (`EngineController(model:)`).

struct IdleSessionPreview: PreviewModifier {
    static func makeSharedContext() async throws -> EngineController { .previewIdle }

    func body(content: Content, context: EngineController) -> some View {
        content.environment(context)
    }
}

struct RunningSessionPreview: PreviewModifier {
    static func makeSharedContext() async throws -> EngineController { .previewRunning }

    func body(content: Content, context: EngineController) -> some View {
        content.environment(context)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    /// A fresh session that has not started.
    static var idleSession: Self { .modifier(IdleSessionPreview()) }
    /// One answered turn with a tool call, metrics including GPU memory.
    static var runningSession: Self { .modifier(RunningSessionPreview()) }
}
