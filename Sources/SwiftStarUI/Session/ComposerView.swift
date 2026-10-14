import SwiftUI
import SwiftStarKit

/// The prompt field and its send/stop button, plus the engine-not-found
/// notice above them.
struct ComposerView: View {
    @Environment(EngineController.self) private var controller
    @State private var input = ""
    @State private var history = PromptHistory()
    @FocusState private var inputFocused: Bool
    @Environment(\.fontSize) private var fontSize: CGFloat

    private var composerState: EngineComposer { controller.composer }

    var body: some View {
        VStack(spacing: 4) {
            if let notice = controller.phase.notFoundNotice {
                HStack {
                    Text(notice)
                        .font(.system(size: fontSize))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
            GlassEffectContainer {
                HStack(alignment: .bottom, spacing: 8) {
                    let analyzing = controller.analysis != nil
                    TextField(analyzing ? EngineAnalysis.composerPlaceholder : "Ask about this project…", text: $input, axis: .vertical)
                        .font(.system(size: fontSize))
                        .textFieldStyle(.plain)
                        .lineLimit(1...15)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .focused($inputFocused)
                        // Analyzing tints the glass itself; at full strength the
                        // tint turns the field solid and hides the placeholder.
                        .glassEffect(analyzing ? .regular.tint(.accentColor.opacity(0.25)) : .regular,
                                     in: .rect(cornerRadius: 20))
                        .onKeyPress(.upArrow) {
                            recall(history.up(current: input, entries: promptEntries))
                        }
                        .onKeyPress(.downArrow) {
                            recall(history.down(current: input, entries: promptEntries))
                        }
                        .onSubmit { send() }
                        .disabled(!composerState.canSend)
                    let button = composerState.button(forInput: input)
                    let showsStop = button == .stop
                    Button {
                        if showsStop {
                            controller.stop()
                        } else {
                            send()
                        }
                    } label: {
                        Image(systemName: showsStop ? "stop.fill" : "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .symbolEffect(.variableColor.iterative, isActive: showsStop)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(showsStop ? .red : .accentColor)
                    // Icon-only, and the icon carries the whole meaning — the label
                    // has to move with the state or VoiceOver announces nothing.
                    .accessibilityLabel(showsStop ? "Stop generating" : "Send message")
                    .disabled(button == .send(enabled: false))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task { inputFocused = true }
        .onChange(of: composerState.canStop) { _, stoppable in
            if !stoppable { inputFocused = true }
        }
    }

    private var promptEntries: [String] {
        PromptHistory.entries(from: controller.transcript.rows)
    }

    /// A recalled prompt fills the field; nil leaves the arrow to the field.
    private func recall(_ text: String?) -> KeyPress.Result {
        guard let text else { return .ignored }
        input = text
        return .handled
    }

    private func send() {
        guard composerState.canSend, let message = input.trimmedOrNil else { return }
        input = ""
        controller.send(message)
    }
}

#Preview("Ready", traits: .runningSession) {
    ComposerView()
        .frame(width: 600)
}

#Preview("Idle", traits: .idleSession) {
    ComposerView()
        .frame(width: 600)
}

#Preview("Analyzing") {
    // Its own controller, built fresh for this preview.
    ComposerView()
        .environment(EngineController(model: .previewAnalyzing))
        .frame(width: 600)
}

#Preview("Engine not found") {
    // Its own fixture, not a shared trait: built fresh for this preview.
    var model = EngineSessionModel()
    model.didNotFind(searched: ["/opt/homebrew/bin/ds4-dogfood", "~/.local/bin/ds4-dogfood"])
    return ComposerView()
        .environment(EngineController(model: model))
        .frame(width: 600)
}
