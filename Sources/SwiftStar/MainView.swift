import SwiftUI

struct MainView: View {
    let engine: EngineController
    @AppStorage("appShellInspectorPresented") private var inspectorPresented = false

    var body: some View {
        AgentView(controller: engine)
            .inspector(isPresented: $inspectorPresented) {
                InspectorView(engine: engine)
            }
            .frame(minWidth: 800, minHeight: 560)
    }
}
