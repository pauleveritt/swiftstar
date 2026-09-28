import SwiftUI

struct MainView: View {
    let engine: EngineController
    @State private var metricsModel = MetricsModel()
    @AppStorage("appShellInspectorPresented") private var inspectorPresented = false

    var body: some View {
        AgentView(controller: engine)
            .inspector(isPresented: $inspectorPresented) {
                InspectorView(metricsModel: metricsModel)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        inspectorPresented.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.trailing")
                    }
                    .help(inspectorPresented ? "Hide Inspector" : "Show Inspector")
                }
            }
            .frame(minWidth: 800, minHeight: 560)
            .onChange(of: engine.metrics, initial: true) { _, metrics in
                metricsModel.state = metrics
            }
    }
}
