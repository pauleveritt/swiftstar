import SwiftUI
import SwiftStarKit

/// The window: this project's conversations, the session, and the inspector
/// (SU.7a, D4).
public struct MainView: View {
    @AppStorage(DefaultsKey.inspectorPresented.rawValue) private var inspectorPresented = false
    @AppStorage(DefaultsKey.sidebarVisible.rawValue) private var sidebarVisible = true

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { sidebarVisible ? .all : .detailOnly },
            set: { sidebarVisible = $0 != .detailOnly }
        )) {
            ConversationList()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            SessionView()
                .inspector(isPresented: $inspectorPresented) {
                    InspectorView()
                }
        }
        .frame(minWidth: 800, minHeight: 560)
    }
}

#Preview("Running", traits: .runningSession) {
    MainView()
}
