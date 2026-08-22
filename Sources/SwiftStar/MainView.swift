import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            PlaceholderView(title: "Agent", phase: "P7")
                .tabItem { Label("Agent", systemImage: "person.crop.circle") }
            PlaceholderView(title: "Metrics", phase: "P4")
                .tabItem { Label("Metrics", systemImage: "gauge") }
            PlaceholderView(title: "Diagnostics", phase: "P6")
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            PlaceholderView(title: "Help", phase: "P13")
                .tabItem { Label("Help", systemImage: "questionmark.circle") }
        }
        .frame(minWidth: 800, minHeight: 560)
    }
}

struct PlaceholderView: View {
    let title: String
    let phase: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.title2)
            Text("\(title) arrives in \(phase).").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
