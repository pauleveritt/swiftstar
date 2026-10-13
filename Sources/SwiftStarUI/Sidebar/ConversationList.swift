import SwiftUI
import SwiftStarKit

/// This project's conversations, newest first (SU.7a). Choosing one resumes
/// it; mid-turn, an alert asks first.
struct ConversationList: View {
    @Environment(EngineController.self) private var controller
    @State private var confirming: Conversation?

    var body: some View {
        Group {
            if controller.workspace == nil {
                Color.clear
            } else if controller.conversations.isEmpty {
                ContentUnavailableView(
                    "No conversations yet in \(controller.workspace?.leafName ?? "this project")",
                    systemImage: "bubble.left.and.bubble.right")
            } else {
                // The row is built inline: as a separate `View` type or
                // `@ViewBuilder` method it crashed SwiftUI's outline list in
                // previews (TableViewListCore_Mac2.swift:5538), SU.7a Task 4.
                List(controller.conversations, selection: selection) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).lineLimit(1)
                        Text(Conversations.subtitle(c, now: Date())).font(.caption).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(c.resumable ? .primary : .tertiary)
                    .help(c.resumable ? c.title
                          : (c.problems.isEmpty ? "This conversation can't be resumed"
                             : c.problems.joined(separator: "; ")))
                    .selectionDisabled(!c.resumable)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await controller.newConversation() }
                } label: {
                    Label("New Conversation", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n")
                .help("New Conversation (⌘N): ends this session and starts a fresh one")
            }
        }
        .task { await controller.reloadConversations() }
        .alert("End the running turn and resume?", isPresented: Binding(
            get: { confirming != nil }, set: { if !$0 { confirming = nil } }
        )) {
            Button("Resume") {
                if let c = confirming { Task { await controller.resume(c) } }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text(confirming?.title ?? "")
        }
    }

    /// The selection follows the running conversation; choosing another one
    /// resumes it.
    private var selection: Binding<String?> {
        Binding(
            get: { controller.currentConversationID },
            set: { id in
                guard let id, id != controller.currentConversationID,
                      let c = controller.conversations.first(where: { $0.id == id }) else { return }
                if controller.resumeNeedsConfirmation { confirming = c } else { Task { await controller.resume(c) } }
            })
    }
}

#Preview("Conversations", traits: .runningSession) {
    ConversationList()
        .frame(width: 260, height: 360)
}

#Preview("Empty") {
    ConversationList()
        .environment(EngineController(
            model: EngineSessionModel(), workspace: URL(fileURLWithPath: "/Users/example/projects/swiftstar")))
        .frame(width: 260, height: 360)
}

#Preview("No workspace", traits: .idleSession) {
    ConversationList()
        .frame(width: 260, height: 360)
}
