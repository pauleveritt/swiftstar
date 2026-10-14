import SwiftUI
import SwiftStarKit

/// The window: this project's conversations, the session, and the inspector
/// (SU.7a, D4).
public struct MainView: View {
    @AppStorage(DefaultsKey.inspectorPresented.rawValue) private var inspectorPresented = false
    @AppStorage(DefaultsKey.sidebarVisible.rawValue) private var sidebarVisible = true
    @AppStorage(DefaultsKey.fontSize.rawValue) private var fontSize = TranscriptFontScale.defaultSize

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { sidebarVisible ? .all : .detailOnly },
            set: { sidebarVisible = $0 != .detailOnly }
        )) {
            ConversationList()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            SessionView()
                .inspector(isPresented: $inspectorPresented) {
                    InspectorView()
                }
        }
        // Wide enough that the session column keeps its minimum (about
        // 380 pt) beside the widest sidebar (300) and the inspector (300).
        // Squeezed below it, AppKit's split view looped its layout until it
        // threw (SU.11, found in the gallery at 900 pt).
        .frame(minWidth: 1000, minHeight: 560)
        // The sidebar and the inspector sit outside SessionView, which sets
        // its own copy; both read the one setting (SU.9).
        .environment(\.fontSize, CGFloat(TranscriptFontScale.clamp(fontSize)))
    }
}

#Preview("Running", traits: .runningSession) {
    MainView()
}
