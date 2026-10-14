import SwiftUI
import SwiftStarKit

/// The prompt field and its send/stop button, plus the engine-not-found
/// notice above them.
struct ComposerView: View {
    @Environment(EngineController.self) private var controller
    @State private var input: String
    @State private var history = PromptHistory()
    /// The `@` picker's highlighted row, and the query Esc closed it for
    /// (SU.14): it stays shut until the `@word` changes (SU.17).
    @State private var pick = 0
    @State private var dismissal = FileMentions.Dismissal()
    @FocusState private var inputFocused: Bool
    @Environment(\.fontSize) private var fontSize: CGFloat

    /// `initialInput` is for previews: the "@ picker" one opens with a query.
    init(initialInput: String = "") { _input = State(initialValue: initialInput) }

    private var composerState: EngineComposer { controller.composer }

    private var mentionQuery: String? { FileMentions.activeQuery(in: input) }
    private var candidates: [String] {
        guard let query = mentionQuery, !dismissal.hides(query) else { return [] }
        return FileMentions.match(query, in: controller.workspaceFiles)
    }

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
            let files = candidates
            if !files.isEmpty {
                FilePickerList(files: files, selected: min(pick, files.count - 1), choose: choose)
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
                        // The `@` picker has the arrows while it's open; then
                        // prompt history (SU.14, D1).
                        .onKeyPress(.upArrow) {
                            if !candidates.isEmpty { pick = max(pick - 1, 0); return .handled }
                            return recall(history.up(current: input, entries: promptEntries))
                        }
                        .onKeyPress(.downArrow) {
                            if !candidates.isEmpty { pick = min(pick + 1, candidates.count - 1); return .handled }
                            return recall(history.down(current: input, entries: promptEntries))
                        }
                        .onKeyPress(.return) { chooseHighlighted() }
                        .onKeyPress(.tab) { chooseHighlighted() }
                        .onKeyPress(.escape) {
                            guard !candidates.isEmpty else { return .ignored }
                            dismissal.dismiss(mentionQuery)
                            return .handled
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
        .onChange(of: mentionQuery) { _, query in
            pick = 0
            dismissal.observe(query)
        }
        .task { inputFocused = true }
        .onChange(of: composerState.canStop) { _, stoppable in
            if !stoppable { inputFocused = true }
        }
    }

    /// Return or Tab with the picker open inserts its highlighted file;
    /// closed, Return sends as before.
    private func chooseHighlighted() -> KeyPress.Result {
        let files = candidates
        guard !files.isEmpty else { return .ignored }
        choose(files[min(pick, files.count - 1)])
        return .handled
    }

    private func choose(_ path: String) {
        input = FileMentions.insert(path, into: input)
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

/// The `@` picker's suggestions, above the field: the file name, then its
/// folder, the highlighted row tinted (SU.14, D1). Clicking one inserts it.
private struct FilePickerList: View {
    let files: [String]
    let selected: Int
    let choose: (String) -> Void
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        // About eight rows, then it scrolls: sixteen at once ran off the top
        // and hid the best matches. The highlighted row stays in view.
        ScrollViewReader { proxy in
            ScrollView {
                rows
            }
            .frame(maxHeight: fontSize * 14)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selected) { _, row in proxy.scrollTo(row) }
        }
        .padding(6)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File suggestions")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(files.enumerated()), id: \.offset) { index, path in
                Button { choose(path) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                        Text((path as NSString).lastPathComponent)
                        Text((path as NSString).deletingLastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: 0)
                    }
                    .font(.scaled(.caption, base: fontSize))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .background(index == selected ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .id(index)
            }
        }
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

// SU.14: the `@` picker. Open with a query, for RenderPreview; and empty,
// for typing `@` in the live canvas (↑/↓, Return or Tab, Esc).
#Preview("@ picker") {
    ComposerView(initialInput: "Compare @sess")
        .environment(EngineController(
            model: EngineController.runningModel(withGPU: true), workspaceFiles: .previewFiles))
        .frame(width: 600, height: 420, alignment: .bottom)
}

#Preview("@ picker, type here") {
    ComposerView()
        .environment(EngineController(
            model: EngineController.runningModel(withGPU: true), workspaceFiles: .previewFiles))
        .frame(width: 600, height: 420, alignment: .bottom)
}
